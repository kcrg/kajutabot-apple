import Foundation
import Observation

enum RealtimeConnectionState: String, Sendable {
    case disconnected
    case connecting
    case subscribing
    case connected
    case reconnecting

    var label: String {
        switch self {
        case .disconnected: "Rozłączono"
        case .connecting: "Łączenie…"
        case .subscribing: "Subskrybowanie serwera…"
        case .connected: "Połączono"
        case .reconnecting: "Ponowne łączenie…"
        }
    }
}

@MainActor
@Observable
final class RealtimeClient {
    private let baseURL: URL
    private let tokenProvider: @Sendable () async throws -> String
    private var socket: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var pingTask: Task<Void, Error>?
    private var recoveryTask: Task<Void, Never>?
    private var desiredGuildId: String?
    private var generation = 0
    private var reconnectAttempt = 0
    private var subscriptionGeneration = 0

    var state: RealtimeConnectionState = .disconnected
    var lastFrameAt: Date?
    var lastQueueUpdateAt: Date?
    var reconnectAttempts = 0
    var onSnapshot: ((QueueSnapshotResponse) -> Void)?
    var onRecoveryNeeded: ((String) -> Void)?

    init(baseURL: URL, tokenProvider: @escaping @Sendable () async throws -> String) {
        self.baseURL = baseURL
        self.tokenProvider = tokenProvider
    }

    func connect(guildId: String?) {
        guard desiredGuildId != guildId || socket == nil else { return }
        desiredGuildId = guildId
        generation += 1
        reconnectAttempt = 0
        reconnectAttempts = 0
        cancelConnectionTasks()

        guard let guildId else {
            state = .disconnected
            return
        }

        let epoch = generation
        receiveTask = Task { [weak self] in
            await self?.runConnection(guildId: guildId, epoch: epoch, reconnecting: false)
        }
    }

    func stop() {
        desiredGuildId = nil
        generation += 1
        reconnectAttempt = 0
        reconnectAttempts = 0
        cancelConnectionTasks()
        state = .disconnected
    }

    private func cancelConnectionTasks() {
        reconnectTask?.cancel()
        reconnectTask = nil
        recoveryTask?.cancel()
        recoveryTask = nil
        pingTask?.cancel()
        pingTask = nil
        receiveTask?.cancel()
        receiveTask = nil
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
    }

    private func runConnection(guildId: String, epoch: Int, reconnecting: Bool) async {
        guard generation == epoch, desiredGuildId == guildId else { return }
        state = reconnecting ? .reconnecting : .connecting

        do {
            let token = try await tokenProvider()
            let connectionToken = try await negotiate(accessToken: token)
            guard generation == epoch, desiredGuildId == guildId else { return }

            let task = makeWebSocket(connectionToken: connectionToken, accessToken: token)
            socket = task
            task.resume()
            defer {
                pingTask?.cancel()
                recoveryTask?.cancel()
                task.cancel(with: .goingAway, reason: nil)
                if socket === task { socket = nil }
            }

            try await task.send(.string("{\"protocol\":\"json\",\"version\":1}\u{001e}"))
            state = .subscribing
            subscriptionGeneration += 1
            let subscriptionEpoch = subscriptionGeneration
            try await task.send(.string("{\"type\":1,\"invocationId\":\"1\",\"target\":\"SubscribeGuild\",\"arguments\":[\"\(jsonEscaped(guildId))\"]}\u{001e}"))

            pingTask = Task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(15))
                    guard !Task.isCancelled else { return }
                    try await task.send(.string("{\"type\":6}\u{001e}"))
                }
            }

            try await receiveLoop(task: task, guildId: guildId, epoch: epoch, subscriptionEpoch: subscriptionEpoch)
        } catch is CancellationError {
            return
        } catch {
            guard generation == epoch, desiredGuildId == guildId else { return }
            scheduleReconnect(guildId: guildId, epoch: epoch)
        }
    }

    private func receiveLoop(
        task: URLSessionWebSocketTask,
        guildId: String,
        epoch: Int,
        subscriptionEpoch: Int
    ) async throws {
        while !Task.isCancelled, generation == epoch, desiredGuildId == guildId {
            let message = try await task.receive()
            lastFrameAt = .now
            let text: String
            switch message {
            case let .string(value): text = value
            case let .data(data): text = String(decoding: data, as: UTF8.self)
            @unknown default: continue
            }

            for frame in text.split(separator: "\u{001e}", omittingEmptySubsequences: true) {
                try handleFrame(Data(frame.utf8), guildId: guildId, subscriptionEpoch: subscriptionEpoch)
            }
        }
    }

    private func handleFrame(_ data: Data, guildId: String, subscriptionEpoch: Int) throws {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any], let type = object["type"] as? Int else {
            return // SignalR handshake response is an empty JSON object.
        }

        switch type {
        case 1:
            guard let target = object["target"] as? String, let arguments = object["arguments"] as? [Any] else { return }
            if target == "QueueUpdated", let payload = arguments.first {
                let encoded = try JSONSerialization.data(withJSONObject: payload)
                let snapshot = try JSONDecoder().decode(QueueSnapshotResponse.self, from: encoded)
                guard snapshot.guildId == guildId else { return }
                recoveryTask?.cancel()
                recoveryTask = nil
                reconnectAttempt = 0
                reconnectAttempts = 0
                lastQueueUpdateAt = .now
                state = .connected
                onSnapshot?(snapshot)
            } else if target == "RealtimeHeartbeat" {
                if state == .subscribing { state = .connected }
            }

        case 3:
            guard object["invocationId"] as? String == "1" else { return }
            if object["error"] != nil { throw RealtimeError.subscriptionFailed }
            state = .connected
            let initialSnapshotAvailable = object["result"] as? Bool ?? false
            scheduleInitialSnapshotRecovery(
                guildId: guildId,
                subscriptionEpoch: subscriptionEpoch,
                immediate: !initialSnapshotAvailable
            )

        case 6:
            if state == .subscribing { state = .connected }

        case 7:
            throw RealtimeError.serverClosed

        default:
            break
        }
    }

    private func scheduleInitialSnapshotRecovery(guildId: String, subscriptionEpoch: Int, immediate: Bool) {
        recoveryTask?.cancel()
        recoveryTask = Task { [weak self] in
            if !immediate { try? await Task.sleep(for: .seconds(3)) }
            guard !Task.isCancelled, let self else { return }
            guard self.desiredGuildId == guildId, self.subscriptionGeneration == subscriptionEpoch else { return }
            self.onRecoveryNeeded?(guildId)
        }
    }

    private func negotiate(accessToken: String) async throws -> String {
        var components = URLComponents(url: baseURL.appending(path: "hubs/playback/negotiate"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "negotiateVersion", value: "1")]
        guard let url = components.url else { throw RealtimeError.negotiateFailed }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw RealtimeError.negotiateFailed
        }
        let result = try JSONDecoder().decode(NegotiateResponse.self, from: data)
        guard let token = result.connectionToken ?? result.connectionId, !token.isEmpty else {
            throw RealtimeError.negotiateFailed
        }
        return token
    }

    private func makeWebSocket(connectionToken: String, accessToken: String) -> URLSessionWebSocketTask {
        var components = URLComponents(url: baseURL.appending(path: "hubs/playback"), resolvingAgainstBaseURL: false)!
        components.scheme = components.scheme == "https" ? "wss" : "ws"
        components.queryItems = [URLQueryItem(name: "id", value: connectionToken)]
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        return URLSession.shared.webSocketTask(with: request)
    }

    private func scheduleReconnect(guildId: String, epoch: Int) {
        guard desiredGuildId == guildId, generation == epoch else { return }
        state = .reconnecting
        reconnectTask?.cancel()

        let backoff: [Duration] = [.zero, .seconds(1), .seconds(2), .seconds(5), .seconds(8)]
        let delay = backoff[min(reconnectAttempt, backoff.count - 1)]
        reconnectAttempt += 1
        reconnectAttempts += 1
        let jitter = Duration.milliseconds(Int.random(in: 0...250))

        reconnectTask = Task { [weak self] in
            try? await Task.sleep(for: delay + jitter)
            guard !Task.isCancelled else { return }
            await self?.runConnection(guildId: guildId, epoch: epoch, reconnecting: true)
        }
    }
}

private struct NegotiateResponse: Decodable {
    let connectionId: String?
    let connectionToken: String?
}

private enum RealtimeError: Error {
    case negotiateFailed
    case subscriptionFailed
    case serverClosed
}

private func jsonEscaped(_ value: String) -> String {
    let data = try? JSONEncoder().encode(value)
    guard let encoded = data.flatMap({ String(data: $0, encoding: .utf8) }), encoded.count >= 2 else { return value }
    return String(encoded.dropFirst().dropLast())
}
