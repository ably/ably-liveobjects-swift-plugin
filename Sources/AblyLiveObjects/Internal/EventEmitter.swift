import Foundation

public typealias MainActorEventListener<Event, Data> = @MainActor (Event, Data) -> Void
public typealias MainActorNamedEventListener<Event> = @MainActor (Event) -> Void

@MainActor
internal protocol EventEmitter<Event, Data>: AnyObject {
    associatedtype Event
    associatedtype Data
    associatedtype Signal

    func on(_ listener: @escaping MainActorEventListener<Event, Data>)
    func on(signalledBy signal: Signal, _ listener: @escaping MainActorEventListener<Event, Data>)

    func on(_ event: Event, _ listener: @escaping MainActorNamedEventListener<Data>)
    func on(_ event: Event, signalledBy signal: Signal, _ listener: @escaping MainActorNamedEventListener<Data>)

    func once(_ listener: @escaping MainActorEventListener<Event, Data>)
    func once(signalledBy signal: Signal, _ listener: @escaping MainActorEventListener<Event, Data>)

    func once(_ event: Event, _ listener: @escaping MainActorNamedEventListener<Data>)
    func once(_ event: Event, signalledBy signal: Signal, _ listener: @escaping MainActorNamedEventListener<Data>)

    func off()
    func off(_ event: Event)
}

// Note: We _have_ to do something other than the off(listener:) that the IDL gives, because closures don't have identity in Swift. I've gone for this approach, instead of the return value used in chat-js and LiveObjects, because it makes it easy to unsubscribe from _within_ the closure, which happens e.g. if you want to listen for one of various state changes and then unsubscribe. The "controller" and "signal" language was taken from the AbortController used in the Web's `fetch()` API.

/// A subscription controller's `signal` can be passed to `EventEmitter`'s `on` or `once` methods. If you call `off()` on the controller then the listener will no longer be called.
///
/// - Note: Subscription lifetime is independent of that of the controller. That is, if you relinquish all references to a controller then the listener will still be called. Only calling `off()` (on the controller or on the `EventEmitter`) will end the subscription.
@MainActor
public protocol SubscriptionControllerProtocol {
    associatedtype Signal

    var signal: Signal { get }

    /// Cancels any subscriptions for which this controller's signal was used. The listener that was passed to `on` or `once` will not be called again.
    ///
    /// Calling this method will not affect any future subscriptions that use the same signal.
    func off()
}

/// The `SubscriptionControllerProtocol` implementation used by the SDK.
@MainActor
public final class SubscriptionController: SubscriptionControllerProtocol {
    public init() {
        signal = Signal()
        signal.controller = self
    }

    public class Signal {
        internal let id = UUID()
        // Store weak reference to the controller that owns this signal
        internal weak var controller: SubscriptionController?
    }

    public let signal: Signal

    // Store registrations that this controller manages
    private var registrations: [Registration] = []

    public func off() {
        // Remove all registrations that this controller created
        for registration in registrations {
            registration.removeFromEmitter()
        }
        registrations.removeAll()
    }

    internal func addRegistration(_ emitter: DefaultInternalEventEmitter<some Hashable, some Any>, registrationId: UUID) {
        let registration = Registration(emitter: emitter, registrationId: registrationId)
        registrations.append(registration)

        // Clean up deallocated emitters periodically
        registrations.removeAll { registration in
            registration.isEmitterDeallocated
        }
    }

    // MARK: - Private Types

    private struct Registration {
        private weak var emitter: (any AnyObject)?
        private let emitterRemoveMethod: @MainActor (UUID) -> Void
        private let registrationId: UUID

        init(emitter: DefaultInternalEventEmitter<some Hashable, some Any>, registrationId: UUID) {
            self.emitter = emitter
            self.registrationId = registrationId
            // Capture the remove method to avoid protocol overhead
            emitterRemoveMethod = { @MainActor [weak emitter] id in
                emitter?.removeRegistration(id: id)
            }
        }

        var isEmitterDeallocated: Bool {
            emitter == nil
        }

        @MainActor
        func removeFromEmitter() {
            emitterRemoveMethod(registrationId)
        }
    }
}
