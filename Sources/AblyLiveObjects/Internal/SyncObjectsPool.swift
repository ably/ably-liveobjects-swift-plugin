import Foundation

/// The RTO5b collection of objects gathered during an `OBJECT_SYNC` sequence, ready to be applied to the `ObjectsPool`.
///
/// Internally stores `InboundObjectMessage` values keyed by `objectId`. The `accumulate` method implements the RTO5f
/// merge logic for partial object sync.
internal struct SyncObjectsPool: Sequence {
    /// A computed view of a stored `InboundObjectMessage`, yielded during iteration.
    ///
    /// Preserves backward compatibility with the consumption side in `ObjectsPool.nosync_applySyncObjectsPool`.
    internal struct Entry {
        /// Guaranteed to have either `.map` or `.counter` populated.
        internal var state: ObjectState
        /// The `serialTimestamp` of the `ObjectMessage` that generated this entry.
        internal var objectMessageSerialTimestamp: Date?
    }

    private var objectMessages: [String: InboundObjectMessage]

    /// Creates an empty pool.
    internal init() {
        objectMessages = [:]
    }

    /// Accumulates an `ObjectMessage` into the pool per RTO5f.
    internal mutating func accumulate(
        objectMessage: InboundObjectMessage,
        logger: Logger,
    ) {
        guard let object = objectMessage.object else {
            return
        }

        let objectId = object.objectId

        // RTO5f3: Reject unsupported object types before pool lookup. This provides the guarantee documented on Entry.state.
        guard object.map != nil || object.counter != nil else {
            logger.log("Skipping unsupported object type during sync for objectId \(objectId)", level: .warn)
            return
        }

        if let existing = objectMessages[objectId] {
            // RTO5f2: An entry already exists for this objectId (partial object state).
            if object.map != nil {
                // RTO5f2a: Incoming message has a map.
                if object.tombstone {
                    // RTO5f2a1: Incoming tombstone is true — replace the entire entry.
                    objectMessages[objectId] = objectMessage
                } else {
                    // RTO5f2a2: Merge map entries into the existing message.
                    var merged = existing
                    if let incomingEntries = object.map?.entries {
                        var mergedObject = merged.object!
                        var mergedMap = mergedObject.map!
                        var mergedEntries = mergedMap.entries ?? [:]
                        mergedEntries.merge(incomingEntries) { _, new in new }
                        mergedMap.entries = mergedEntries
                        mergedObject.map = mergedMap
                        merged.object = mergedObject
                    }
                    objectMessages[objectId] = merged
                }
            } else {
                // RTO5f2b: Incoming message has a counter — log error, skip.
                logger.log("Received partial counter sync for objectId \(objectId); skipping", level: .error)
            }
        } else {
            // RTO5f1: No entry exists for this objectId — store the message.
            objectMessages[objectId] = objectMessage
        }
    }

    internal var count: Int { objectMessages.count }
    internal var isEmpty: Bool { objectMessages.isEmpty }

    // MARK: - Sequence conformance

    internal struct Iterator: IteratorProtocol {
        private var underlying: Dictionary<String, InboundObjectMessage>.Values.Iterator

        fileprivate init(_ underlying: Dictionary<String, InboundObjectMessage>.Values.Iterator) {
            self.underlying = underlying
        }

        internal mutating func next() -> Entry? {
            guard let message = underlying.next() else {
                return nil
            }

            // We only store messages whose `object` is non-nil (see `accumulate`).
            return Entry(
                state: message.object!,
                objectMessageSerialTimestamp: message.serialTimestamp,
            )
        }
    }

    internal func makeIterator() -> Iterator {
        Iterator(objectMessages.values.makeIterator())
    }
}
