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
final class RealtimeClient: LocalVolumeTransport {
    private let hubURL: String
    private let tokenProvider: @Sendable () async throws -> String
    @ObservationIgnored private var connection: HubConnection?
    @ObservationIgnored private var connectionTask: Task<Void, Never>?
    @ObservationIgnored private var subscriptionTask: Task<Void, Never>?
    @ObservationIgnored private var recoveryTask: Task<Void, Never>?
    @ObservationIgnored private var desiredGuildId: String?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var subscriptionGeneration = 0
    @ObservationIgnored private var lastSnapshot: QueueSnapshotResponse?
    @ObservationIgnored private var ready = false
    @ObservationIgnored private var hasStarted = false
    @ObservationIgnored private var active = false

    var state: RealtimeConnectionState = .disconnected
    var lastFrameAt: Date?
    var lastQueueUpdateAt: Date?
    var reconnectAttempts = 0
    @ObservationIgnored var onSnapshot: (@MainActor (QueueSnapshotResponse) -> Void)?
    @ObservationIgnored var onRecoveryNeeded: (@MainActor (String) -> Void)?
    @ObservationIgnored var onLocalVolume: (@MainActor (LocalVolumeState) -> Void)?
    @ObservationIgnored var onConnectionChanged: (@MainActor (Bool) -> Void)?

    init(baseURL: URL, tokenProvider: @escaping @Sendable () async throws -> String) {
        hubURL = baseURL.appending(path: "api/v1/app/hubs/playback").absoluteString
        self.tokenProvider = tokenProvider
    }

    /// The socket belongs to the authenticated session; guild is only a subscription.
    func connect(guildId: String?) {
        let changed = desiredGuildId != guildId
        desiredGuildId = guildId
        active = true
        if connection == nil {
            generation &+= 1
            let epoch = generation
            state = .connecting
            connectionTask = Task { [weak self] in await self?.start(epoch: epoch) }
        } else if changed {
            lastSnapshot = nil
            scheduleSubscription()
        }
    }

    func stop() {
        active = false
        generation &+= 1
        subscriptionGeneration &+= 1
        desiredGuildId = nil
        ready = false
        hasStarted = false
        lastSnapshot = nil
        connectionTask?.cancel()
        subscriptionTask?.cancel()
        recoveryTask?.cancel()
        connectionTask = nil
        subscriptionTask = nil
        recoveryTask = nil
        let previous = connection
        connection = nil
        state = .disconnected
        onConnectionChanged?(false)
        if let previous { Task { await previous.stop() } }
    }

    func getLocalVolume() async throws -> LocalVolumeState {
        guard ready, let connection else { throw URLError(.notConnectedToInternet) }
        let epoch = generation
        let result: LocalVolumeState = try await withInvocationDeadline {
            try await connection.invoke(method: "GetLocalVolumeState")
        }
        guard generation == epoch, ready else { throw CancellationError() }
        return result
    }

    func setLocalVolume(_ volume: Int) async throws {
        guard (0...200).contains(volume), ready, let connection else { throw APIError.invalidResponse }
        let epoch = generation
        // invoke waits for Completion; send only writes a frame.
        try await withInvocationDeadline {
            try await connection.invoke(method: "SetLocalVolume", arguments: volume) as Void
        }
        guard generation == epoch, ready else { throw CancellationError() }
    }

    private func start(epoch: Int) async {
        guard isCurrent(epoch) else { return }
        var options = HttpConnectionOptions()
        options.transport = .webSockets
        options.accessTokenFactory = { [tokenProvider] in try await tokenProvider() }
        let hub = HubConnectionBuilder()
            .withUrl(url: hubURL, options: options)
            .withAutomaticReconnect(retryPolicy: KajutaBotRetryPolicy { [weak self] attempt in
                Task { @MainActor [weak self] in
                    guard let self, self.isCurrent(epoch) else { return }
                    self.reconnectAttempts = attempt
                }
            })
            .withServerTimeout(serverTimeout: 30)
            .withKeepAliveInterval(keepAliveInterval: 15)
            .build()
        connection = hub
        await registerHandlers(hub, epoch: epoch)
        var attempt = 0
        while isCurrent(epoch), !Task.isCancelled {
            do {
                try await hub.start()
                guard isCurrent(epoch), !Task.isCancelled else { await hub.stop(); return }
                hasStarted = true
                ready = true
                state = .connected
                reconnectAttempts = 0
                onConnectionChanged?(true)
                scheduleSubscription()
                return
            } catch is CancellationError { await hub.stop(); return } catch {
                guard isCurrent(epoch), !Task.isCancelled else { return }
                attempt &+= 1
                reconnectAttempts = attempt
                state = .reconnecting
                Diagnostics.warning("realtime", "Connection attempt failed")
                try? await Task.sleep(for: .seconds(KajutaBotRetryPolicy.delay(forAttempt: attempt - 1)))
            }
        }
    }

    private func registerHandlers(_ hub: HubConnection, epoch: Int) async {
        await hub.on("QueueUpdated") { @Sendable [weak self] (snapshot: QueueSnapshotResponse) in
            await self?.receive(snapshot, epoch: epoch)
        }
        await hub.on("RealtimeHeartbeat") { @Sendable [weak self] (_: Int64) in
            await self?.heartbeat(epoch: epoch)
        }
        await hub.on("LocalVolumeStateChanged") { @Sendable [weak self] (volume: LocalVolumeState) in
            await self?.receive(volume, epoch: epoch)
        }
        await hub.onReconnecting { @Sendable [weak self] _ in await self?.reconnecting(epoch: epoch) }
        await hub.onReconnected { @Sendable [weak self] in await self?.reconnected(epoch: epoch) }
        await hub.onClosed { @Sendable [weak self] _ in await self?.closed(epoch: epoch) }
    }

    private func receive(_ snapshot: QueueSnapshotResponse, epoch: Int) {
        guard isCurrent(epoch), snapshot.guildId == desiredGuildId else { return }
        lastFrameAt = .now
        lastQueueUpdateAt = .now
        recoveryTask?.cancel()
        if snapshot != lastSnapshot {
            lastSnapshot = snapshot
            onSnapshot?(snapshot)
        }
    }

    private func receive(_ volume: LocalVolumeState, epoch: Int) {
        guard isCurrent(epoch), ready else { return }
        lastFrameAt = .now
        onLocalVolume?(volume)
    }

    private func heartbeat(epoch: Int) {
        guard isCurrent(epoch) else { return }
        lastFrameAt = .now
    }

    private func reconnecting(epoch: Int) {
        guard isCurrent(epoch) else { return }
        ready = false
        state = .reconnecting
        recoveryTask?.cancel()
        onConnectionChanged?(false)
    }

    private func reconnected(epoch: Int) {
        guard isCurrent(epoch) else { return }
        ready = true
        lastSnapshot = nil
        state = .connected
        reconnectAttempts = 0
        onConnectionChanged?(true)
        scheduleSubscription()
    }

    private func closed(epoch: Int) {
        guard isCurrent(epoch), hasStarted else { return }
        ready = false
        onConnectionChanged?(false)
        recoveryTask?.cancel()
        subscriptionTask?.cancel()
        generation &+= 1
        let nextEpoch = generation
        hasStarted = false
        state = .reconnecting
        connectionTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, let self, self.isCurrent(nextEpoch) else { return }
            await self.start(epoch: nextEpoch)
        }
    }

    private func scheduleSubscription() {
        subscriptionGeneration &+= 1
        let subscription = subscriptionGeneration
        let epoch = generation
        let previous = subscriptionTask
        recoveryTask?.cancel()
        guard ready, let guild = desiredGuildId, let hub = connection else { return }
        // Serialize SubscribeGuild itself, so late invocations cannot switch the
        // server subscription back after a newer selection.
        subscriptionTask = Task { [weak self] in
            await previous?.value
            guard !Task.isCancelled, let self, self.isCurrent(epoch),
                  self.subscriptionGeneration == subscription else { return }
            self.state = .subscribing
            do {
                let available: Bool = try await withInvocationDeadline {
                    try await hub.invoke(method: "SubscribeGuild", arguments: guild)
                }
                guard self.isCurrent(epoch), self.subscriptionGeneration == subscription else { return }
                self.state = .connected
                self.scheduleRecovery(guild: guild, epoch: epoch, subscription: subscription, immediate: !available)
            } catch {
                guard self.isCurrent(epoch) else { return }
                if self.desiredGuildId == guild { self.onRecoveryNeeded?(guild) }
                self.closed(epoch: epoch)
                await hub.stop()
                Diagnostics.warning("realtime", "Guild subscription failed; recovering through REST")
            }
        }
    }

    private func scheduleRecovery(guild: String, epoch: Int, subscription: Int, immediate: Bool) {
        guard lastSnapshot?.guildId != guild else { return }
        recoveryTask = Task { [weak self] in
            if !immediate { try? await Task.sleep(for: .seconds(3)) }
            guard !Task.isCancelled, let self, self.isCurrent(epoch),
                  self.subscriptionGeneration == subscription, self.lastSnapshot?.guildId != guild else { return }
            self.onRecoveryNeeded?(guild)
        }
    }

    private func isCurrent(_ epoch: Int) -> Bool { active && generation == epoch }
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
