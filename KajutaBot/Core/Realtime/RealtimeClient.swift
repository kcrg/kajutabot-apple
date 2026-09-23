import Foundation
import Observation
import SignalRClient

enum RealtimeConnectionState: String, Sendable {
    case disconnected
    case connecting
    case subscribing
    case connected
    case reconnecting

    var label: LocalizedStringResource {
        switch self {
        case .disconnected: .realtimeDisconnected
        case .connecting: .realtimeConnecting
        case .subscribing: .realtimeSubscribing
        case .connected: .realtimeConnected
        case .reconnecting: .realtimeReconnecting
        }
    }
}

@MainActor
@Observable
final class RealtimeClient {
    private let hubURL: String
    private let tokenProvider: @Sendable () async throws -> String

    @ObservationIgnored private var connection: HubConnection?
    @ObservationIgnored private var connectionTask: Task<Void, Never>?
    @ObservationIgnored private var recoveryTask: Task<Void, Never>?
    @ObservationIgnored private var desiredGuildId: String?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var subscriptionGeneration = 0
    @ObservationIgnored private var snapshotSubscriptionGeneration: Int?

    var state: RealtimeConnectionState = .disconnected
    var lastFrameAt: Date?
    var lastQueueUpdateAt: Date?
    var reconnectAttempts = 0
    @ObservationIgnored var onSnapshot: ((QueueSnapshotResponse) -> Void)?
    @ObservationIgnored var onRecoveryNeeded: ((String) -> Void)?

    init(baseURL: URL, tokenProvider: @escaping @Sendable () async throws -> String) {
        hubURL = baseURL.appending(path: "hubs/playback").absoluteString
        self.tokenProvider = tokenProvider
    }

    func connect(guildId: String?) {
        guard desiredGuildId != guildId || connection == nil else { return }

        generation += 1
        let epoch = generation
        desiredGuildId = guildId
        subscriptionGeneration = 0
        snapshotSubscriptionGeneration = nil
        reconnectAttempts = 0
        recoveryTask?.cancel()
        recoveryTask = nil
        connectionTask?.cancel()
        connectionTask = nil

        let previousConnection = connection
        connection = nil
        if let previousConnection {
            Task { await previousConnection.stop() }
        }

        guard let guildId else {
            state = .disconnected
            return
        }

        state = .connecting
        connectionTask = Task { [weak self] in
            await self?.startConnection(guildId: guildId, epoch: epoch)
        }
    }

    func stop() {
        desiredGuildId = nil
        generation += 1
        subscriptionGeneration = 0
        snapshotSubscriptionGeneration = nil
        reconnectAttempts = 0
        recoveryTask?.cancel()
        recoveryTask = nil
        connectionTask?.cancel()
        connectionTask = nil

        let activeConnection = connection
        connection = nil
        state = .disconnected

        if let activeConnection {
            Task { await activeConnection.stop() }
        }
    }

    private func startConnection(guildId: String, epoch: Int) async {
        guard isCurrent(guildId: guildId, epoch: epoch) else { return }

        var options = HttpConnectionOptions()
        options.transport = .webSockets
        options.accessTokenFactory = { [tokenProvider] in
            try await tokenProvider()
        }

        let retryPolicy = KajutaBotRetryPolicy { [weak self] attempt in
            Task { @MainActor [weak self] in
                guard let self, self.isCurrent(guildId: guildId, epoch: epoch) else { return }
                self.reconnectAttempts = attempt
            }
        }

        let hubConnection = HubConnectionBuilder()
            .withUrl(url: hubURL, options: options)
            .withAutomaticReconnect(retryPolicy: retryPolicy)
            .withServerTimeout(serverTimeout: 30)
            .withKeepAliveInterval(keepAliveInterval: 15)
            .build()

        connection = hubConnection
        await registerHandlers(on: hubConnection, guildId: guildId, epoch: epoch)

        var initialAttempt = 0
        while isCurrent(guildId: guildId, epoch: epoch), !Task.isCancelled {
            do {
                state = initialAttempt == 0 ? .connecting : .reconnecting
                try await hubConnection.start()
                guard isCurrent(guildId: guildId, epoch: epoch), !Task.isCancelled else {
                    await hubConnection.stop()
                    return
                }

                reconnectAttempts = 0
                try await subscribe(guildId: guildId, epoch: epoch, on: hubConnection)
                return
            } catch is CancellationError {
                await hubConnection.stop()
                return
            } catch {
                guard isCurrent(guildId: guildId, epoch: epoch), !Task.isCancelled else { return }

                initialAttempt += 1
                reconnectAttempts = initialAttempt
                state = .reconnecting
                await hubConnection.stop()

                let delay = KajutaBotRetryPolicy.delay(forAttempt: initialAttempt - 1)
                try? await Task.sleep(for: .seconds(delay))
            }
        }
    }

    private func registerHandlers(on connection: HubConnection, guildId: String, epoch: Int) async {
        await connection.on("QueueUpdated") { @Sendable [weak self] (snapshot: QueueSnapshotResponse) in
            await self?.handleQueueUpdated(snapshot, guildId: guildId, epoch: epoch)
        }

        await connection.on("RealtimeHeartbeat") { @Sendable [weak self] (_: Int64) in
            await self?.handleHeartbeat(guildId: guildId, epoch: epoch)
        }

        await connection.onReconnecting { @Sendable [weak self] _ in
            await self?.handleReconnecting(guildId: guildId, epoch: epoch)
        }

        await connection.onReconnected { @Sendable [weak self] in
            await self?.handleReconnected(guildId: guildId, epoch: epoch)
        }

        await connection.onClosed { @Sendable [weak self] _ in
            await self?.handleClosed(guildId: guildId, epoch: epoch)
        }
    }

    private func handleQueueUpdated(_ snapshot: QueueSnapshotResponse, guildId: String, epoch: Int) {
        guard isCurrent(guildId: guildId, epoch: epoch), snapshot.guildId == guildId else { return }

        lastFrameAt = .now
        lastQueueUpdateAt = .now
        snapshotSubscriptionGeneration = subscriptionGeneration
        reconnectAttempts = 0
        recoveryTask?.cancel()
        recoveryTask = nil
        state = .connected
        onSnapshot?(snapshot)
    }

    private func handleHeartbeat(guildId: String, epoch: Int) {
        guard isCurrent(guildId: guildId, epoch: epoch) else { return }
        lastFrameAt = .now
    }

    private func handleReconnecting(guildId: String, epoch: Int) {
        guard isCurrent(guildId: guildId, epoch: epoch) else { return }
        recoveryTask?.cancel()
        recoveryTask = nil
        state = .reconnecting
    }

    private func handleReconnected(guildId: String, epoch: Int) async {
        guard isCurrent(guildId: guildId, epoch: epoch), let connection else { return }

        do {
            try await subscribe(guildId: guildId, epoch: epoch, on: connection)
        } catch {
            guard isCurrent(guildId: guildId, epoch: epoch) else { return }
            state = .reconnecting
            await connection.stop()

            // Automatic reconnect covers transport loss. A failed hub subscription is a
            // domain-level failure, so rebuild the connection to obtain a clean session.
            self.connection = nil
            connectionTask?.cancel()
            connectionTask = Task { [weak self] in
                guard let self else { return }
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                self.restartIfCurrent(guildId: guildId, epoch: epoch)
            }
        }
    }

    private func handleClosed(guildId: String, epoch: Int) {
        guard isCurrent(guildId: guildId, epoch: epoch) else { return }
        recoveryTask?.cancel()
        recoveryTask = nil
        state = .disconnected
    }

    private func subscribe(guildId: String, epoch: Int, on connection: HubConnection) async throws {
        guard isCurrent(guildId: guildId, epoch: epoch) else { return }

        state = .subscribing
        subscriptionGeneration += 1
        let subscriptionEpoch = subscriptionGeneration
        snapshotSubscriptionGeneration = nil
        recoveryTask?.cancel()
        recoveryTask = nil

        let initialSnapshotAvailable: Bool = try await connection.invoke(
            method: "SubscribeGuild",
            arguments: guildId
        )

        guard isCurrent(guildId: guildId, epoch: epoch), subscriptionGeneration == subscriptionEpoch else { return }

        reconnectAttempts = 0
        if state != .connected {
            state = .connected
        }

        guard snapshotSubscriptionGeneration != subscriptionEpoch else { return }
        scheduleInitialSnapshotRecovery(
            guildId: guildId,
            epoch: epoch,
            subscriptionEpoch: subscriptionEpoch,
            immediate: !initialSnapshotAvailable
        )
    }

    private func scheduleInitialSnapshotRecovery(
        guildId: String,
        epoch: Int,
        subscriptionEpoch: Int,
        immediate: Bool
    ) {
        recoveryTask?.cancel()
        recoveryTask = Task { [weak self] in
            if !immediate {
                try? await Task.sleep(for: .seconds(3))
            }
            guard !Task.isCancelled, let self else { return }
            guard self.isCurrent(guildId: guildId, epoch: epoch) else { return }
            guard self.subscriptionGeneration == subscriptionEpoch else { return }
            guard self.snapshotSubscriptionGeneration != subscriptionEpoch else { return }
            self.onRecoveryNeeded?(guildId)
        }
    }

    private func restartIfCurrent(guildId: String, epoch: Int) {
        guard isCurrent(guildId: guildId, epoch: epoch) else { return }
        generation += 1
        let newEpoch = generation
        state = .reconnecting
        connectionTask = Task { [weak self] in
            await self?.startConnection(guildId: guildId, epoch: newEpoch)
        }
    }

    private func isCurrent(guildId: String, epoch: Int) -> Bool {
        desiredGuildId == guildId && generation == epoch
    }
}

private struct KajutaBotRetryPolicy: RetryPolicy {
    private let onRetry: @Sendable (Int) -> Void

    init(onRetry: @escaping @Sendable (Int) -> Void) {
        self.onRetry = onRetry
    }

    func nextRetryInterval(retryContext: RetryContext) -> TimeInterval? {
        let attempt = retryContext.retryCount + 1
        onRetry(attempt)
        return Self.delay(forAttempt: retryContext.retryCount)
    }

    static func delay(forAttempt attempt: Int) -> TimeInterval {
        let backoff: [TimeInterval] = [0, 1, 2, 5, 8]
        let base = backoff[min(max(attempt, 0), backoff.count - 1)]
        return base + Double.random(in: 0...0.25)
    }
}
