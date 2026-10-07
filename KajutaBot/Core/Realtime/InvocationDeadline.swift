import Foundation

/// Returns at the deadline even if a third-party invocation ignores cancellation.
/// The connection/session generation must additionally reject late results.
@MainActor
func withInvocationDeadline<Value: Sendable>(
    _ operation: @escaping @MainActor () async throws -> Value
) async throws -> Value {
    let gate = InvocationDeadline<Value>()
    return try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { continuation in
            gate.start(continuation, operation: operation)
        }
    } onCancel: {
        Task { @MainActor in gate.finish(.failure(CancellationError())) }
    }
}

@MainActor
private final class InvocationDeadline<Value: Sendable> {
    private var continuation: CheckedContinuation<Value, Error>?
    private var result: Result<Value, Error>?
    private var operationTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?

    func start(_ continuation: CheckedContinuation<Value, Error>,
               operation: @escaping @MainActor () async throws -> Value) {
        if let result { continuation.resume(with: result); return }
        self.continuation = continuation
        operationTask = Task { [weak self] in
            do {
                try Task.checkCancellation()
                self?.finish(.success(try await operation()))
            }
            catch { self?.finish(.failure(error)) }
        }
        timeoutTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(10))
                self?.finish(.failure(URLError(.timedOut)))
            } catch { /* The operation or cancellation already completed the gate. */ }
        }
    }

    func finish(_ result: Result<Value, Error>) {
        guard self.result == nil else { return }
        self.result = result
        continuation?.resume(with: result)
        continuation = nil
        operationTask?.cancel()
        timeoutTask?.cancel()
        operationTask = nil
        timeoutTask = nil
    }
}
