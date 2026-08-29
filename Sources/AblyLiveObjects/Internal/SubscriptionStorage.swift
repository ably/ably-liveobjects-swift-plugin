import Foundation

/// Handles subscription bookkeeping, providing methods for subscribing and emitting events.
internal final class SubscriptionStorage<EventName: Hashable & Sendable, Update: Sendable>: Sendable {
    /// The `EventEmitter` that backs this `SubscriptionStorage`.
    ///
    /// We wrap the `EventEmitter` implementation ported from ably-swift (in this implementation, listeners are called synchronously on the internal queue and unsubscribing is done via a `SubscriptionController`) to match the current public API of this plugin, in which:
    ///
    /// - listeners are dispatched asynchronously to the ably-cocoa callbacks queue
    /// - unsubscribing is done via the `SubscribeResponse` that is both returned from `subscribe()` and passed as an argument to the listener
    private let emitter: DefaultInternalEventEmitter<EventName, EmitData>
    private let internalQueue: DispatchQueue

    /// Bundles the update data together with the queue on which the user's callback should be dispatched.
    private struct EmitData: Sendable {
        var update: Update
        var queue: DispatchQueue
    }

    internal init(internalQueue: DispatchQueue) {
        self.internalQueue = internalQueue
        emitter = DefaultInternalEventEmitter(internalQueue: internalQueue)
    }

    // MARK: - Subscriptions

    @discardableResult
    internal func nosync_subscribe(
        listener: @escaping LiveObjectUpdateCallback<Update>,
        eventName: EventName,
    ) -> any AblyLiveObjects.SubscribeResponse {
        let controller = SubscriptionController(internalQueue: internalQueue)
        let subscribeResponse = SubscribeResponse(controller: controller, internalQueue: internalQueue)

        emitter.nosync_on(eventName, signalledBy: controller.signal) { emitData in
            emitData.queue.async {
                listener(emitData.update, subscribeResponse)
            }
        }

        return subscribeResponse
    }

    internal func nosync_unsubscribeAll() {
        emitter.nosync_off()
    }

    internal func nosync_emit(_ update: Update, eventName: EventName, on queue: DispatchQueue) {
        emitter.nosync_emit(event: eventName, data: EmitData(update: update, queue: queue))
    }

    private struct SubscribeResponse: AblyLiveObjects.SubscribeResponse {
        let controller: SubscriptionController
        let internalQueue: DispatchQueue

        func unsubscribe() {
            internalQueue.ably_syncNoDeadlock {
                controller.nosync_off()
            }
        }
    }
}

// MARK: - Convenience extension for Void updates

internal extension SubscriptionStorage where Update == Void {
    /// Convenience method for emitting events when there's no update data to pass.
    func nosync_emit(eventName: EventName, on queue: DispatchQueue) {
        nosync_emit((), eventName: eventName, on: queue)
    }
}
