import Foundation

/// An implementation of ``InternalEventEmitter``.
/// Conforms to the RTE specification for EventEmitter behavior.
///
/// All `nosync_` methods must be called on the internal queue (enforced at runtime).
internal final class DefaultInternalEventEmitter<Event: Hashable & Sendable, Data: Sendable>: InternalEventEmitter, Sendable {
    private let mutableStateMutex: DispatchQueueMutex<MutableState>

    internal init(internalQueue: DispatchQueue) {
        mutableStateMutex = .init(dispatchQueue: internalQueue, initialValue: .init())
    }

    // MARK: - MutableState

    private struct MutableState {
        var allEventListeners: [ListenerRegistration<EventListener<Event, Data>>] = []
        var namedEventListeners: [Event: [ListenerRegistration<NamedEventListener<Data>>]] = [:]
    }

    // MARK: - EventEmitter conformance

    /// RTE3: Registers listener for all events
    internal func nosync_on(_ listener: @escaping EventListener<Event, Data>) {
        let registration = ListenerRegistration(listener: listener, once: false)
        mutableStateMutex.withoutSync { state in
            state.allEventListeners.append(registration)
        }
    }

    /// RTE3: Registers listener for all events with signal
    internal func nosync_on(signalledBy signal: SubscriptionController.Signal, _ listener: @escaping EventListener<Event, Data>) {
        let registration = ListenerRegistration(listener: listener, once: false)
        mutableStateMutex.withoutSync { state in
            state.allEventListeners.append(registration)
        }

        // Register this registration with the controller so it can remove it when nosync_off() is called
        signal.controller?.nosync_addRegistration(self, registrationId: registration.id)
    }

    /// RTE3: Registers listener for specific event
    internal func nosync_on(_ event: Event, _ listener: @escaping NamedEventListener<Data>) {
        let registration = ListenerRegistration(listener: listener, once: false)
        mutableStateMutex.withoutSync { state in
            state.namedEventListeners[event, default: []].append(registration)
        }
    }

    /// RTE3: Registers listener for specific event with signal
    internal func nosync_on(_ event: Event, signalledBy signal: SubscriptionController.Signal, _ listener: @escaping NamedEventListener<Data>) {
        let registration = ListenerRegistration(listener: listener, once: false)
        mutableStateMutex.withoutSync { state in
            state.namedEventListeners[event, default: []].append(registration)
        }

        // Register this registration with the controller
        signal.controller?.nosync_addRegistration(self, registrationId: registration.id)
    }

    /// RTE4: Registers one-time listener for all events
    internal func nosync_once(_ listener: @escaping EventListener<Event, Data>) {
        let registration = ListenerRegistration(listener: listener, once: true)
        mutableStateMutex.withoutSync { state in
            state.allEventListeners.append(registration)
        }
    }

    /// RTE4: Registers one-time listener for all events with signal
    internal func nosync_once(signalledBy signal: SubscriptionController.Signal, _ listener: @escaping EventListener<Event, Data>) {
        let registration = ListenerRegistration(listener: listener, once: true)
        mutableStateMutex.withoutSync { state in
            state.allEventListeners.append(registration)
        }

        // Register this registration with the controller
        signal.controller?.nosync_addRegistration(self, registrationId: registration.id)
    }

    /// RTE4: Registers one-time listener for specific event
    internal func nosync_once(_ event: Event, _ listener: @escaping NamedEventListener<Data>) {
        let registration = ListenerRegistration(listener: listener, once: true)
        mutableStateMutex.withoutSync { state in
            state.namedEventListeners[event, default: []].append(registration)
        }
    }

    /// RTE4: Registers one-time listener for specific event with signal
    internal func nosync_once(_ event: Event, signalledBy signal: SubscriptionController.Signal, _ listener: @escaping NamedEventListener<Data>) {
        let registration = ListenerRegistration(listener: listener, once: true)
        mutableStateMutex.withoutSync { state in
            state.namedEventListeners[event, default: []].append(registration)
        }

        // Register this registration with the controller
        signal.controller?.nosync_addRegistration(self, registrationId: registration.id)
    }

    /// RTE5: Removes all listeners
    internal func nosync_off() {
        mutableStateMutex.withoutSync { state in
            state.allEventListeners.removeAll()
            state.namedEventListeners.removeAll()
        }
    }

    /// RTE5: Removes all listeners for a specific event
    internal func nosync_off(_ event: Event) {
        mutableStateMutex.withoutSync { state in
            _ = state.namedEventListeners.removeValue(forKey: event)
        }
    }

    // MARK: - InternalEventEmitter conformance

    /// RTE6: Emits an event, calling registered listeners
    /// RTE6a: The set of listeners must not change during emit
    internal func nosync_emit(event: Event, data: Data) {
        // Take snapshots inside withoutSync to ensure RTE6a compliance
        let (allSnapshot, namedSnapshot) = mutableStateMutex.withoutSync { state -> ([ListenerRegistration<EventListener<Event, Data>>], [ListenerRegistration<NamedEventListener<Data>>]) in
            let allListeners = state.allEventListeners
            let namedListeners = state.namedEventListeners[event] ?? []
            return (allListeners, namedListeners)
        }

        // Collect all once-listener IDs that need to be removed
        var idsToRemove: [UUID] = []

        // Call all-event listeners from the snapshot (outside withoutSync to avoid exclusivity violation if a listener re-enters the emitter)
        for registration in allSnapshot {
            registration.listener(event, data)

            if registration.once {
                idsToRemove.append(registration.id)
            }
        }

        // Call named event listeners from the snapshot
        for registration in namedSnapshot {
            registration.listener(data)

            if registration.once {
                idsToRemove.append(registration.id)
            }
        }

        // Remove all once listeners in one pass
        for id in idsToRemove {
            nosync_removeRegistration(id: id)
        }
    }

    // MARK: - Registration removal (called internally and by SubscriptionController)

    internal func nosync_removeRegistration(id: UUID) {
        mutableStateMutex.withoutSync { state in
            // Remove from all-event listeners
            state.allEventListeners.removeAll { registration in
                registration.id == id
            }

            // Remove from named-event listeners
            for (event, listeners) in state.namedEventListeners {
                state.namedEventListeners[event] = listeners.filter { registration in
                    registration.id != id
                }
                if state.namedEventListeners[event]?.isEmpty == true {
                    _ = state.namedEventListeners.removeValue(forKey: event)
                }
            }
        }
    }

    // MARK: - Private Types

    private struct ListenerRegistration<Listener>: Identifiable {
        let id = UUID()
        let listener: Listener
        let once: Bool

        init(listener: Listener, once: Bool) {
            self.listener = listener
            self.once = once
        }
    }
}
