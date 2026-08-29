// NOTE: This file is adapted from the WIP ably-swift (taken from there at commit 98996f1).

/// An extension of ``EventEmitter`` for use inside the codebase. It represents an `EventEmitter` that can be instructed to emit an event.
internal protocol InternalEventEmitter<Event, Data>: EventEmitter {
    /// Emits an event, invoking the registered listeners on the internal queue.
    func nosync_emit(event: Event, data: Data)
}

// (Note: I wonder whether having a mock InternalEventEmitter might be useful sometimes, when all you care about is whether a given event was emitted without having to go through the palaver of getting this data back out using a callback.)
