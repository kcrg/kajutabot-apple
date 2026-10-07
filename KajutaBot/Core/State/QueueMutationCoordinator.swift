import Foundation

/// One serialization boundary for every queue mutation in this process.
/// The server remains the concurrency boundary between devices and extensions.
@MainActor
final class QueueMutationCoordinator {
    private var tails: [String: Task<QueueSnapshotResponse, Error>] = [:]
    private var snapshots: [String: QueueSnapshotResponse] = [:]
    private var generation = 0

    func observe(_ snapshot: QueueSnapshotResponse) {
        guard snapshot.version >= (snapshots[snapshot.guildId]?.version ?? .min) else { return }
        snapshots[snapshot.guildId] = snapshot
    }

    func reset() {
        generation &+= 1
        tails.values.forEach { $0.cancel() }
        tails.removeAll()
        snapshots.removeAll()
    }

    func run(
        guildId: String,
        fetch: @escaping @MainActor () async throws -> QueueSnapshotResponse,
        publish: @escaping @MainActor (QueueSnapshotResponse) -> Void,
        mutation: @escaping @MainActor (Int64) async throws -> QueueSnapshotResponse
    ) async throws -> QueueSnapshotResponse {
        let epoch = generation
        let previous = tails[guildId]
        let task = Task { @MainActor [weak self] in
            _ = await previous?.result
            try Task.checkCancellation()
            guard let self, self.generation == epoch else { throw CancellationError() }
            if self.snapshots[guildId] == nil {
                let fresh = try await fetch()
                try Task.checkCancellation()
                guard self.generation == epoch else { throw CancellationError() }
                self.observe(fresh)
                publish(fresh)
            }
            guard let token = self.snapshots[guildId]?.queueVersion else { throw APIError.invalidResponse }
            do {
                let result = try await mutation(token)
                try Task.checkCancellation()
                guard self.generation == epoch else { throw CancellationError() }
                self.observe(result)
                publish(result)
                return result
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                let failure = error
                // A transport failure can happen after the server committed a POST.
                // Reconcile once; never silently resend the user's intent.
                do {
                    let fresh = try await fetch()
                    try Task.checkCancellation()
                    guard self.generation == epoch else { throw CancellationError() }
                    self.observe(fresh)
                    publish(fresh)
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    guard self.generation == epoch else { throw CancellationError() }
                    self.snapshots.removeValue(forKey: guildId)
                }
                throw failure
            }
        }
        tails[guildId] = task
        return try await task.value
    }
}
