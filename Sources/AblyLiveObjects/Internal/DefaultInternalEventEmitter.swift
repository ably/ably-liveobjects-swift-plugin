// NOTE: This file is adapted from the WIP ably-swift (taken from there at commit 98996f1).

import Foundation

/// An implementation of ``InternalEventEmitter``.
/// Conforms to the RTE specification for EventEmitter behavior.
@MainActor
internal class DefaultInternalEventEmitter<Event: Hashable, Data>: InternalEventEmitter {
    // Storage for listener registrations
    private var allEventListeners: [ListenerRegistration<MainActorEventListener<Event, Data>>] = []
    private var namedEventListeners: [Event: [ListenerRegistration<MainActorNamedEventListener<Data>>]] = [:]

    // MARK: - EventEmitter conformance

    /// RTE3: Registers listener for all events
    internal func on(_ listener: @escaping MainActorEventListener<Event, Data>) {
        let registration = ListenerRegistration(listener: listener, once: false)
        allEventListeners.append(registration)
    }

    /// RTE3: Registers listener for all events with signal
    internal func on(signalledBy signal: SubscriptionController.Signal, _ listener: @escaping MainActorEventListener<Event, Data>) {
        let registration = ListenerRegistration(listener: listener, once: false)
        allEventListeners.append(registration)

        // Register this registration with the controller so it can remove it when off() is called
        signal.controller?.addRegistration(self, registrationId: registration.id)
    }

    /// RTE3: Registers listener for specific event
    internal func on(_ event: Event, _ listener: @escaping MainActorNamedEventListener<Data>) {
        let registration = ListenerRegistration(listener: listener, once: false)
        namedEventListeners[event, default: []].append(registration)
    }

    /// RTE3: Registers listener for specific event with signal
    internal func on(_ event: Event, signalledBy signal: SubscriptionController.Signal, _ listener: @escaping MainActorNamedEventListener<Data>) {
        let registration = ListenerRegistration(listener: listener, once: false)
        namedEventListeners[event, default: []].append(registration)

        // Register this registration with the controller
        signal.controller?.addRegistration(self, registrationId: registration.id)
    }

    /// RTE4: Registers one-time listener for all events
    internal func once(_ listener: @escaping MainActorEventListener<Event, Data>) {
        let registration = ListenerRegistration(listener: listener, once: true)
        allEventListeners.append(registration)
    }

    /// RTE4: Registers one-time listener for all events with signal
    internal func once(signalledBy signal: SubscriptionController.Signal, _ listener: @escaping MainActorEventListener<Event, Data>) {
        let registration = ListenerRegistration(listener: listener, once: true)
        allEventListeners.append(registration)

        // Register this registration with the controller
        signal.controller?.addRegistration(self, registrationId: registration.id)
    }

    /// RTE4: Registers one-time listener for specific event
    internal func once(_ event: Event, _ listener: @escaping MainActorNamedEventListener<Data>) {
        let registration = ListenerRegistration(listener: listener, once: true)
        namedEventListeners[event, default: []].append(registration)
    }

    /// RTE4: Registers one-time listener for specific event with signal
    internal func once(_ event: Event, signalledBy signal: SubscriptionController.Signal, _ listener: @escaping MainActorNamedEventListener<Data>) {
        let registration = ListenerRegistration(listener: listener, once: true)
        namedEventListeners[event, default: []].append(registration)

        // Register this registration with the controller
        signal.controller?.addRegistration(self, registrationId: registration.id)
    }

    /// RTE5: Removes all listeners
    internal func off() {
        allEventListeners.removeAll()
        namedEventListeners.removeAll()
    }

    /// RTE5: Removes all listeners for a specific event
    internal func off(_ event: Event) {
        namedEventListeners.removeValue(forKey: event)
    }

    // MARK: - InternalEventEmitter conformance

    /// RTE6: Emits an event, calling registered listeners
    /// RTE6a: The set of listeners must not change during emit
    internal func emit(event: Event, data: Data) {
        // Create snapshots to ensure RTE6a compliance - listeners called during emit don't affect this invocation
        let allEventListenersSnapshot = allEventListeners
        let namedEventListenersSnapshot = namedEventListeners[event] ?? []

        // Collect all listener IDs that need to be removed
        var idsToRemove: [UUID] = []

        // Call all-event listeners
        for registration in allEventListenersSnapshot {
            // Call listener per RTE6
            registration.listener(event, data)

            // Mark for removal if it was a once listener
            if registration.once {
                idsToRemove.append(registration.id)
            }
        }

        // Call named event listeners
        for registration in namedEventListenersSnapshot {
            // Call listener per RTE6
            registration.listener(data)

            // Mark for removal if it was a once listener
            if registration.once {
                idsToRemove.append(registration.id)
            }
        }

        // Remove all once listeners in one pass
        for id in idsToRemove {
            removeRegistration(id: id)
        }
    }

    // MARK: - Registration removal (called internally and by SubscriptionController)

    internal func removeRegistration(id: UUID) {
        // Remove from all-event listeners
        allEventListeners.removeAll { registration in
            registration.id == id
        }

        // Remove from named-event listeners
        for (event, listeners) in namedEventListeners {
            namedEventListeners[event] = listeners.filter { registration in
                registration.id != id
            }
            if namedEventListeners[event]?.isEmpty == true {
                namedEventListeners.removeValue(forKey: event)
            }
        }
    }

    // MARK: - Private Types

    private struct ListenerRegistration<Listener> {
        let id = UUID()
        let listener: Listener
        let once: Bool

        init(listener: Listener, once: Bool) {
            self.listener = listener
            self.once = once
        }
    }
}
