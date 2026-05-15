import Foundation
internal import _AblyPluginSupportPrivate

/// State shared between the scheduled block and the cancellation handler in ``PluginAPIProtocol.sleep(seconds:for:)``.
///
/// Tracks the continuation and the scheduler handle, and guards against the fire-vs-cancel race so that the continuation is resumed exactly once.
private final class SleepState: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?
    private var handle: (any SchedulerHandle)?
    private var resumed = false
    private var cancelled = false

    /// Stores the continuation. If the awaiting Task was already cancelled before the continuation was registered, immediately resumes the continuation with a `CancellationError`.
    internal func setContinuation(_ continuation: CheckedContinuation<Void, Error>) {
        lock.lock()
        if cancelled {
            lock.unlock()
            continuation.resume(throwing: CancellationError())
            return
        }
        self.continuation = continuation
        lock.unlock()
    }

    /// Stores the scheduler handle. If the awaiting Task was already cancelled (or, theoretically, the timer has already fired) by this point, cancels the handle instead.
    internal func setHandle(_ handle: any SchedulerHandle) {
        lock.lock()
        if resumed || cancelled {
            lock.unlock()
            handle.cancel()
            return
        }
        self.handle = handle
        lock.unlock()
    }

    /// Called when the scheduled delay expires.
    internal func fire() {
        lock.lock()
        if resumed || cancelled {
            lock.unlock()
            return
        }
        resumed = true
        let continuation = continuation
        self.continuation = nil
        handle = nil
        lock.unlock()
        continuation?.resume()
    }

    /// Called when the awaiting Task is cancelled.
    internal func cancel() {
        lock.lock()
        if resumed || cancelled {
            lock.unlock()
            return
        }
        cancelled = true
        let continuation = continuation
        let handle = handle
        self.continuation = nil
        self.handle = nil
        lock.unlock()
        handle?.cancel()
        continuation?.resume(throwing: CancellationError())
    }
}

internal extension PluginAPIProtocol {
    /// Suspends the current Task for `seconds` seconds via the SDK's injected scheduler.
    ///
    /// Equivalent in spirit to `Task.sleep(nanoseconds:)`, but routed through `-[APPluginAPI scheduleForClient:after:queue:block:]` so that the wait participates in fake-time control when ably-cocoa's `ARTTimeProvider` is overridden by a test.
    ///
    /// Throws `CancellationError` if the awaiting Task is cancelled while waiting.
    func sleep(seconds: TimeInterval, for client: RealtimeClient) async throws {
        let state = SleepState()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                state.setContinuation(continuation)
                let handle = schedule(for: client, after: seconds, queue: .global(qos: .default)) {
                    state.fire()
                }
                state.setHandle(handle)
            }
        } onCancel: {
            state.cancel()
        }
    }
}
