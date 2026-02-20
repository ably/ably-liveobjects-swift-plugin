import Foundation

internal typealias EventListener<Event, Data> = @Sendable (Event, Data) -> Void
internal typealias NamedEventListener<Event> = @Sendable (Event) -> Void

internal protocol EventEmitter<Event, Data>: AnyObject {
    associatedtype Event
    associatedtype Data
    associatedtype Signal

    func nosync_on(_ listener: @escaping EventListener<Event, Data>)
    func nosync_on(signalledBy signal: Signal, _ listener: @escaping EventListener<Event, Data>)

    func nosync_on(_ event: Event, _ listener: @escaping NamedEventListener<Data>)
    func nosync_on(_ event: Event, signalledBy signal: Signal, _ listener: @escaping NamedEventListener<Data>)

    func nosync_once(_ listener: @escaping EventListener<Event, Data>)
    func nosync_once(signalledBy signal: Signal, _ listener: @escaping EventListener<Event, Data>)

    func nosync_once(_ event: Event, _ listener: @escaping NamedEventListener<Data>)
    func nosync_once(_ event: Event, signalledBy signal: Signal, _ listener: @escaping NamedEventListener<Data>)

    func nosync_off()
    func nosync_off(_ event: Event)
}

// Note: We _have_ to do something other than the off(listener:) that the IDL gives, because closures don't have identity in Swift. I've gone for this approach, instead of the return value used in chat-js and LiveObjects, because it makes it easy to unsubscribe from _within_ the closure, which happens e.g. if you want to listen for one of various state changes and then unsubscribe. The "controller" and "signal" language was taken from the AbortController used in the Web's `fetch()` API.

/// A subscription controller's `signal` can be passed to `EventEmitter`'s `nosync_on` or `nosync_once` methods. If you call `nosync_off()` on the controller then the listener will no longer be called.
///
/// - Note: Subscription lifetime is independent of that of the controller. That is, if you relinquish all references to a controller then the listener will still be called. Only calling `nosync_off()` (on the controller or on the `EventEmitter`) will end the subscription.
internal protocol SubscriptionControllerProtocol {
    associatedtype Signal

    var signal: Signal { get }

    /// Cancels any subscriptions for which this controller's signal was used. The listener that was passed to `nosync_on` or `nosync_once` will not be called again.
    ///
    /// Calling this method will not affect any future subscriptions that use the same signal.
    func nosync_off()
}

/// The `SubscriptionControllerProtocol` implementation used by the SDK.
internal final class SubscriptionController: SubscriptionControllerProtocol, Sendable {
    internal init(internalQueue: DispatchQueue) {
        let signal = Signal()
        self.signal = signal
        self.registrations = DispatchQueueMutex(dispatchQueue: internalQueue, initialValue: [])
        signal.controller = self
    }

    internal final class Signal: Sendable {
        internal let id = UUID()
        // Store weak reference to the controller that owns this signal.
        // Safe because all access occurs on the internal queue.
        nonisolated(unsafe) internal weak var controller: SubscriptionController?
    }

    internal let signal: Signal

    // Store registrations that this controller manages
    private let registrations: DispatchQueueMutex<[Registration]>

    internal func nosync_off() {
        registrations.withoutSync { registrations in
            // Remove all registrations that this controller created
            for registration in registrations {
                registration.removeFromEmitter()
            }
            registrations.removeAll()
        }
    }

    internal func nosync_addRegistration(_ emitter: DefaultInternalEventEmitter<some Hashable & Sendable, some Sendable>, registrationId: UUID) {
        registrations.withoutSync { registrations in
            let registration = Registration(emitter: emitter, registrationId: registrationId)
            registrations.append(registration)

            // Clean up deallocated emitters periodically
            registrations.removeAll { registration in
                registration.isEmitterDeallocated
            }
        }
    }

    // MARK: - Private Types

    private struct Registration: @unchecked Sendable {
        private weak var emitter: (any AnyObject)?
        private let emitterRemoveMethod: @Sendable (UUID) -> Void
        private let registrationId: UUID

        init(emitter: DefaultInternalEventEmitter<some Hashable & Sendable, some Sendable>, registrationId: UUID) {
            self.emitter = emitter
            self.registrationId = registrationId
            // Capture the remove method to avoid protocol overhead
            emitterRemoveMethod = { [weak emitter] id in
                emitter?.nosync_removeRegistration(id: id)
            }
        }

        var isEmitterDeallocated: Bool {
            emitter == nil
        }

        func removeFromEmitter() {
            emitterRemoveMethod(registrationId)
        }
    }
}
