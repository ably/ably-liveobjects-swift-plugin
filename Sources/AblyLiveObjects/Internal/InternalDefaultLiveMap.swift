internal import _AblyPluginSupportPrivate
import Ably

/// Protocol for accessing objects from the ObjectsPool. This is used by a LiveMap when it needs to return an object given an object ID.
internal protocol LiveMapObjectPoolDelegate: AnyObject, Sendable {
    /// Fetches an object from the pool by its ID
    func getObjectFromPool(id: String) -> ObjectsPool.Entry?
}

/// This provides the implementation behind ``PublicDefaultLiveMap``, via internal versions of the ``LiveMap`` API.
internal final class InternalDefaultLiveMap: Sendable {
    // Used for synchronizing access to all of this instance's mutable state. This is a temporary solution just to allow us to implement `Sendable`, and we'll revisit it in https://github.com/ably/ably-liveobjects-swift-plugin/issues/3.
    private let mutex = NSLock()

    private nonisolated(unsafe) var mutableState: MutableState

    internal var testsOnly_data: [String: InternalObjectsMapEntry] {
        mutex.withLock {
            mutableState.data
        }
    }

    internal var testsOnly_semantics: WireEnum<ObjectsMapSemantics>? {
        mutex.withLock {
            mutableState.semantics
        }
    }

    internal var testsOnly_siteTimeserials: [String: String] {
        mutex.withLock {
            mutableState.liveObjectMutableState.siteTimeserials
        }
    }

    internal var testsOnly_createOperationIsMerged: Bool {
        mutex.withLock {
            mutableState.liveObjectMutableState.createOperationIsMerged
        }
    }

    private let logger: Logger
    private let userCallbackQueue: DispatchQueue
    private let clock: SimpleClock

    // MARK: - Initialization

    internal convenience init(
        testsOnly_data data: [String: InternalObjectsMapEntry],
        objectID: String,
        testsOnly_semantics semantics: WireEnum<ObjectsMapSemantics>? = nil,
        logger: Logger,
        userCallbackQueue: DispatchQueue,
        clock: SimpleClock,
    ) {
        self.init(
            data: data,
            objectID: objectID,
            semantics: semantics,
            logger: logger,
            userCallbackQueue: userCallbackQueue,
            clock: clock,
        )
    }

    private init(
        data: [String: InternalObjectsMapEntry],
        objectID: String,
        semantics: WireEnum<ObjectsMapSemantics>?,
        logger: Logger,
        userCallbackQueue: DispatchQueue,
        clock: SimpleClock,
    ) {
        mutableState = .init(liveObjectMutableState: .init(objectID: objectID), data: data, semantics: semantics)
        self.logger = logger
        self.userCallbackQueue = userCallbackQueue
        self.clock = clock
    }

    /// Creates a "zero-value LiveMap", per RTLM4.
    ///
    /// - Parameters:
    ///   - objectID: The value to use for the RTLO3a `objectID` property.
    ///   - semantics: The value to use for the "private `semantics` field" of RTO5c1b1b.
    internal static func createZeroValued(
        objectID: String,
        semantics: WireEnum<ObjectsMapSemantics>? = nil,
        logger: Logger,
        userCallbackQueue: DispatchQueue,
        clock: SimpleClock,
    ) -> Self {
        .init(
            data: [:],
            objectID: objectID,
            semantics: semantics,
            logger: logger,
            userCallbackQueue: userCallbackQueue,
            clock: clock,
        )
    }

    // MARK: - Data access

    internal var objectID: String {
        mutex.withLock {
            mutableState.liveObjectMutableState.objectID
        }
    }

    // MARK: - Internal methods that back LiveMap conformance

    /// Returns the value associated with a given key, following RTLM5d specification.
    internal func get(key: String, coreSDK: CoreSDK, delegate: LiveMapObjectPoolDelegate) throws(ARTErrorInfo) -> InternalLiveMapValue? {
        try mutex.ablyLiveObjects_withLockWithTypedThrow { () throws(ARTErrorInfo) in
            try mutableState.get(key: key, coreSDK: coreSDK, delegate: delegate)
        }
    }

    internal func size(coreSDK: CoreSDK, delegate: LiveMapObjectPoolDelegate) throws(ARTErrorInfo) -> Int {
        try mutex.ablyLiveObjects_withLockWithTypedThrow { () throws(ARTErrorInfo) in
            try mutableState.size(coreSDK: coreSDK, delegate: delegate)
        }
    }

    internal func entries(coreSDK: CoreSDK, delegate: LiveMapObjectPoolDelegate) throws(ARTErrorInfo) -> [(key: String, value: InternalLiveMapValue)] {
        try mutex.ablyLiveObjects_withLockWithTypedThrow { () throws(ARTErrorInfo) in
            try mutableState.entries(coreSDK: coreSDK, delegate: delegate)
        }
    }

    internal func keys(coreSDK: CoreSDK, delegate: LiveMapObjectPoolDelegate) throws(ARTErrorInfo) -> [String] {
        // RTLM12b: Identical to LiveMap#entries, except that it returns only the keys from the internal data map
        try entries(coreSDK: coreSDK, delegate: delegate).map(\.key)
    }

    internal func values(coreSDK: CoreSDK, delegate: LiveMapObjectPoolDelegate) throws(ARTErrorInfo) -> [InternalLiveMapValue] {
        // RTLM13b: Identical to LiveMap#entries, except that it returns only the values from the internal data map
        try entries(coreSDK: coreSDK, delegate: delegate).map(\.value)
    }

    internal func set(key: String, value: InternalLiveMapValue, coreSDK: CoreSDK) async throws(ARTErrorInfo) {
        do throws(InternalError) {
            // RTLM20c
            do {
                try coreSDK.validateChannelState(notIn: [.detached, .failed, .suspended], operationDescription: "LiveMap.set")
            } catch {
                throw error.toInternalError()
            }

            let objectMessage = OutboundObjectMessage(
                operation: .init(
                    // RTLM20e2
                    action: .known(.mapSet),
                    // RTLM20e3
                    objectId: objectID,
                    mapOp: .init(
                        // RTLM20e4
                        key: key,
                        // RTLM20e5
                        data: value.toObjectData,
                    ),
                ),
            )

            try await coreSDK.publish(objectMessages: [objectMessage])
        } catch {
            throw error.toARTErrorInfo()
        }
    }

    internal func remove(key: String, coreSDK: CoreSDK) async throws(ARTErrorInfo) {
        do throws(InternalError) {
            // RTLM21c
            do {
                try coreSDK.validateChannelState(notIn: [.detached, .failed, .suspended], operationDescription: "LiveMap.remove")
            } catch {
                throw error.toInternalError()
            }

            let objectMessage = OutboundObjectMessage(
                operation: .init(
                    // RTLM21e2
                    action: .known(.mapRemove),
                    // RTLM21e3
                    objectId: objectID,
                    mapOp: .init(
                        // RTLM21e4
                        key: key,
                    ),
                ),
            )

            // RTLM21f
            try await coreSDK.publish(objectMessages: [objectMessage])
        } catch {
            throw error.toARTErrorInfo()
        }
    }

    @discardableResult
    internal func subscribe(listener: @escaping LiveObjectUpdateCallback<DefaultLiveMapUpdate>, coreSDK: CoreSDK) throws(ARTErrorInfo) -> any SubscribeResponse {
        try mutex.ablyLiveObjects_withLockWithTypedThrow { () throws(ARTErrorInfo) in
            // swiftlint:disable:next trailing_closure
            try mutableState.liveObjectMutableState.subscribe(listener: listener, coreSDK: coreSDK, updateSelfLater: { [weak self] action in
                guard let self else {
                    return
                }

                mutex.withLock {
                    action(&mutableState.liveObjectMutableState)
                }
            })
        }
    }

    internal func unsubscribeAll() {
        mutex.withLock {
            mutableState.liveObjectMutableState.unsubscribeAll()
        }
    }

    @discardableResult
    internal func on(event: LiveObjectLifecycleEvent, callback: @escaping LiveObjectLifecycleEventCallback) -> any OnLiveObjectLifecycleEventResponse {
        mutex.withLock {
            mutableState.liveObjectMutableState.on(event: event, callback: callback) { [weak self] action in
                guard let self else {
                    return
                }

                mutex.withLock {
                    action(&mutableState.liveObjectMutableState)
                }
            }
        }
    }

    internal func offAll() {
        mutex.withLock {
            mutableState.liveObjectMutableState.offAll()
        }
    }

    // MARK: - Emitting update from external sources

    /// Emit an event from this `LiveMap`.
    ///
    /// This is used to instruct this map to emit updates during an `OBJECT_SYNC`.
    internal func emit(_ update: LiveObjectUpdate<DefaultLiveMapUpdate>) {
        mutex.withLock {
            mutableState.liveObjectMutableState.emit(update, on: userCallbackQueue)
        }
    }

    // MARK: - Data manipulation

    /// Replaces the internal data of this map with the provided ObjectState, per RTLM6.
    ///
    /// - Parameters:
    ///   - objectsPool: The pool into which should be inserted any objects created by a `MAP_SET` operation.
    ///   - objectMessageSerialTimestamp: The `serialTimestamp` of the containing `ObjectMessage`. Used if we need to tombstone this map.
    internal func replaceData(
        using state: ObjectState,
        objectMessageSerialTimestamp: Date?,
        objectsPool: inout ObjectsPool,
    ) -> LiveObjectUpdate<DefaultLiveMapUpdate> {
        mutex.withLock {
            mutableState.replaceData(
                using: state,
                objectMessageSerialTimestamp: objectMessageSerialTimestamp,
                objectsPool: &objectsPool,
                logger: logger,
                clock: clock,
                userCallbackQueue: userCallbackQueue,
            )
        }
    }

    /// Merges the initial value from an ObjectOperation into this LiveMap, per RTLM17.
    internal func mergeInitialValue(from operation: ObjectOperation, objectsPool: inout ObjectsPool) -> LiveObjectUpdate<DefaultLiveMapUpdate> {
        mutex.withLock {
            mutableState.mergeInitialValue(
                from: operation,
                objectsPool: &objectsPool,
                logger: logger,
                userCallbackQueue: userCallbackQueue,
                clock: clock,
            )
        }
    }

    /// Test-only method to apply a MAP_CREATE operation, per RTLM16.
    internal func testsOnly_applyMapCreateOperation(_ operation: ObjectOperation, objectsPool: inout ObjectsPool) -> LiveObjectUpdate<DefaultLiveMapUpdate> {
        mutex.withLock {
            mutableState.applyMapCreateOperation(
                operation,
                objectsPool: &objectsPool,
                logger: logger,
                userCallbackQueue: userCallbackQueue,
                clock: clock,
            )
        }
    }

    /// Attempts to apply an operation from an inbound `ObjectMessage`, per RTLM15.
    internal func apply(
        _ operation: ObjectOperation,
        objectMessageSerial: String?,
        objectMessageSiteCode: String?,
        objectMessageSerialTimestamp: Date?,
        objectsPool: inout ObjectsPool,
    ) {
        mutex.withLock {
            mutableState.apply(
                operation,
                objectMessageSerial: objectMessageSerial,
                objectMessageSiteCode: objectMessageSiteCode,
                objectMessageSerialTimestamp: objectMessageSerialTimestamp,
                objectsPool: &objectsPool,
                logger: logger,
                userCallbackQueue: userCallbackQueue,
                clock: clock,
            )
        }
    }

    /// Applies a `MAP_SET` operation to a key, per RTLM7.
    ///
    /// This is currently exposed just so that the tests can test RTLM7 without having to go through a convoluted replaceData(…) call, but I _think_ that it's going to be used in further contexts when we introduce the handling of incoming object operations in a future spec PR.
    internal func testsOnly_applyMapSetOperation(
        key: String,
        operationTimeserial: String?,
        operationData: ObjectData,
        objectsPool: inout ObjectsPool,
    ) -> LiveObjectUpdate<DefaultLiveMapUpdate> {
        mutex.withLock {
            mutableState.applyMapSetOperation(
                key: key,
                operationTimeserial: operationTimeserial,
                operationData: operationData,
                objectsPool: &objectsPool,
                logger: logger,
                userCallbackQueue: userCallbackQueue,
                clock: clock,
            )
        }
    }

    /// Applies a `MAP_REMOVE` operation to a key, per RTLM8.
    ///
    /// This is currently exposed just so that the tests can test RTLM8 without having to go through a convoluted replaceData(…) call, but I _think_ that it's going to be used in further contexts when we introduce the handling of incoming object operations in a future spec PR.
    internal func testsOnly_applyMapRemoveOperation(key: String, operationTimeserial: String?, operationSerialTimestamp: Date?) -> LiveObjectUpdate<DefaultLiveMapUpdate> {
        mutex.withLock {
            mutableState.applyMapRemoveOperation(
                key: key,
                operationTimeserial: operationTimeserial,
                operationSerialTimestamp: operationSerialTimestamp,
                logger: logger,
                clock: clock,
            )
        }
    }

    /// Resets the map's data, per RTO4b2. This is to be used when an `ATTACHED` ProtocolMessage indicates that the only object in a channel is an empty root map.
    internal func resetData() {
        mutex.withLock {
            mutableState.resetData(userCallbackQueue: userCallbackQueue)
        }
    }

    /// Releases entries that were tombstoned more than `gracePeriod` ago, per RTLM19.
    internal func releaseTombstonedEntries(gracePeriod: TimeInterval, clock: SimpleClock) {
        mutex.withLock {
            mutableState.releaseTombstonedEntries(gracePeriod: gracePeriod, logger: logger, clock: clock)
        }
    }

    // MARK: - LiveObject

    /// Returns the object's RTLO3d `isTombstone` property.
    internal var isTombstone: Bool {
        mutex.withLock {
            mutableState.liveObjectMutableState.isTombstone
        }
    }

    /// Returns the object's RTLO3e `tombstonedAt` property.
    internal var tombstonedAt: Date? {
        mutex.withLock {
            mutableState.liveObjectMutableState.tombstonedAt
        }
    }

    // MARK: - Mutable state and the operations that affect it

    private struct MutableState: InternalLiveObject {
        /// The mutable state common to all LiveObjects.
        internal var liveObjectMutableState: LiveObjectMutableState<DefaultLiveMapUpdate>

        /// The internal data that this map holds, per RTLM3.
        internal var data: [String: InternalObjectsMapEntry]

        /// The "private `semantics` field" of RTO5c1b1b.
        internal var semantics: WireEnum<ObjectsMapSemantics>?

        /// Replaces the internal data of this map with the provided ObjectState, per RTLM6.
        ///
        /// - Parameters:
        ///   - objectsPool: The pool into which should be inserted any objects created by a `MAP_SET` operation.
        ///   - objectMessageSerialTimestamp: The `serialTimestamp` of the containing `ObjectMessage`. Used if we need to tombstone this map.
        internal mutating func replaceData(
            using state: ObjectState,
            objectMessageSerialTimestamp: Date?,
            objectsPool: inout ObjectsPool,
            logger: Logger,
            clock: SimpleClock,
            userCallbackQueue: DispatchQueue,
        ) -> LiveObjectUpdate<DefaultLiveMapUpdate> {
            // RTLM6a: Replace the private siteTimeserials with the value from ObjectState.siteTimeserials
            liveObjectMutableState.siteTimeserials = state.siteTimeserials

            // RTLM6e, RTLM6e1: No-op if we're already tombstone
            if liveObjectMutableState.isTombstone {
                return .noop
            }

            // RTLM6f: Tombstone if state indicates tombstoned
            if state.tombstone {
                let dataBeforeTombstoning = data

                tombstone(
                    objectMessageSerialTimestamp: objectMessageSerialTimestamp,
                    logger: logger,
                    clock: clock,
                    userCallbackQueue: userCallbackQueue,
                )

                // RTLM6f1
                return .update(.init(update: dataBeforeTombstoning.mapValues { _ in .removed }))
            }

            // RTLM6b: Set the private flag createOperationIsMerged to false
            liveObjectMutableState.createOperationIsMerged = false

            // RTLM6c: Set data to ObjectState.map.entries, or to an empty map if it does not exist
            data = state.map?.entries?.mapValues { entry in
                // Set tombstonedAt for tombstoned entries
                let tombstonedAt: Date?
                if entry.tombstone == true {
                    // RTLM6c1a
                    if let serialTimestamp = entry.serialTimestamp {
                        tombstonedAt = serialTimestamp
                    } else {
                        // RTLM6c1b
                        logger.log("serialTimestamp not found in ObjectsMapEntry, using local clock for tombstone timestamp", level: .debug)
                        // RTLM6cb1
                        tombstonedAt = clock.now
                    }
                } else {
                    tombstonedAt = nil
                }

                return .init(objectsMapEntry: entry, tombstonedAt: tombstonedAt)
            } ?? [:]

            // RTLM6d: If ObjectState.createOp is present, merge the initial value into the LiveMap as described in RTLM17
            return if let createOp = state.createOp {
                mergeInitialValue(
                    from: createOp,
                    objectsPool: &objectsPool,
                    logger: logger,
                    userCallbackQueue: userCallbackQueue,
                    clock: clock,
                )
            } else {
                // TODO: I assume this is what to do, clarify in https://github.com/ably/specification/pull/346/files#r2201363446
                .noop
            }
        }

        /// Merges the initial value from an ObjectOperation into this LiveMap, per RTLM17.
        internal mutating func mergeInitialValue(
            from operation: ObjectOperation,
            objectsPool: inout ObjectsPool,
            logger: Logger,
            userCallbackQueue: DispatchQueue,
            clock: SimpleClock,
        ) -> LiveObjectUpdate<DefaultLiveMapUpdate> {
            // RTLM17a: For each key–ObjectsMapEntry pair in ObjectOperation.map.entries
            let perKeyUpdates: [LiveObjectUpdate<DefaultLiveMapUpdate>] = if let entries = operation.map?.entries {
                entries.map { key, entry in
                    if entry.tombstone == true {
                        // RTLM17a2: If ObjectsMapEntry.tombstone is true, apply the MAP_REMOVE operation
                        // as described in RTLM8, passing in the current key as ObjectsMapOp, ObjectsMapEntry.timeserial as the operation's serial, and ObjectsMapEntry.serialTimestamp as the operation's serial timestamp
                        applyMapRemoveOperation(
                            key: key,
                            operationTimeserial: entry.timeserial,
                            operationSerialTimestamp: entry.serialTimestamp,
                            logger: logger,
                            clock: clock,
                        )
                    } else {
                        // RTLM17a1: If ObjectsMapEntry.tombstone is false, apply the MAP_SET operation
                        // as described in RTLM7, passing in ObjectsMapEntry.data and the current key as ObjectsMapOp, and ObjectsMapEntry.timeserial as the operation's serial
                        applyMapSetOperation(
                            key: key,
                            operationTimeserial: entry.timeserial,
                            operationData: entry.data,
                            objectsPool: &objectsPool,
                            logger: logger,
                            userCallbackQueue: userCallbackQueue,
                            clock: clock,
                        )
                    }
                }
            } else {
                []
            }

            // RTLM17b: Set the private flag createOperationIsMerged to true
            liveObjectMutableState.createOperationIsMerged = true

            // RTLM17c: Merge the updates, skipping no-ops
            // I don't love having to use uniqueKeysWithValues, when I shouldn't have to. I should be able to reason _statically_ that there are no overlapping keys. The problem that we're trying to use LiveMapUpdate throughout instead of something more communicative. But I don't know what's to come in the spec so I don't want to mess with this internal interface.
            let filteredPerKeyUpdates = perKeyUpdates.compactMap { update -> LiveMapUpdate? in
                switch update {
                case .noop:
                    nil
                case let .update(update):
                    update
                }
            }
            let filteredPerKeyUpdateKeyValuePairs = filteredPerKeyUpdates.reduce(into: []) { result, element in
                result.append(contentsOf: Array(element.update))
            }
            let update = Dictionary(uniqueKeysWithValues: filteredPerKeyUpdateKeyValuePairs)
            return .update(DefaultLiveMapUpdate(update: update))
        }

        /// Attempts to apply an operation from an inbound `ObjectMessage`, per RTLM15.
        internal mutating func apply(
            _ operation: ObjectOperation,
            objectMessageSerial: String?,
            objectMessageSiteCode: String?,
            objectMessageSerialTimestamp: Date?,
            objectsPool: inout ObjectsPool,
            logger: Logger,
            userCallbackQueue: DispatchQueue,
            clock: SimpleClock,
        ) {
            guard let applicableOperation = liveObjectMutableState.canApplyOperation(objectMessageSerial: objectMessageSerial, objectMessageSiteCode: objectMessageSiteCode, logger: logger) else {
                // RTLM15b
                logger.log("Operation \(operation) (serial: \(String(describing: objectMessageSerial)), siteCode: \(String(describing: objectMessageSiteCode))) should not be applied; discarding", level: .debug)
                return
            }

            // RTLM15c
            liveObjectMutableState.siteTimeserials[applicableOperation.objectMessageSiteCode] = applicableOperation.objectMessageSerial

            // RTLM15e
            // TODO: are we still meant to update siteTimeserials? https://github.com/ably/specification/pull/350/files#r2218718854
            if liveObjectMutableState.isTombstone {
                return
            }

            switch operation.action {
            case .known(.mapCreate):
                // RTLM15d1
                let update = applyMapCreateOperation(
                    operation,
                    objectsPool: &objectsPool,
                    logger: logger,
                    userCallbackQueue: userCallbackQueue,
                    clock: clock,
                )
                // RTLM15d1a
                liveObjectMutableState.emit(update, on: userCallbackQueue)
            case .known(.mapSet):
                guard let mapOp = operation.mapOp else {
                    logger.log("Could not apply MAP_SET since operation.mapOp is missing", level: .warn)
                    return
                }
                guard let data = mapOp.data else {
                    logger.log("Could not apply MAP_SET since operation.data is missing", level: .warn)
                    return
                }

                // RTLM15d2
                let update = applyMapSetOperation(
                    key: mapOp.key,
                    operationTimeserial: applicableOperation.objectMessageSerial,
                    operationData: data,
                    objectsPool: &objectsPool,
                    logger: logger,
                    userCallbackQueue: userCallbackQueue,
                    clock: clock,
                )
                // RTLM15d2a
                liveObjectMutableState.emit(update, on: userCallbackQueue)
            case .known(.mapRemove):
                guard let mapOp = operation.mapOp else {
                    return
                }

                // RTLM15d3
                let update = applyMapRemoveOperation(
                    key: mapOp.key,
                    operationTimeserial: applicableOperation.objectMessageSerial,
                    operationSerialTimestamp: objectMessageSerialTimestamp,
                    logger: logger,
                    clock: clock,
                )
                // RTLM15d3a
                liveObjectMutableState.emit(update, on: userCallbackQueue)
            case .known(.objectDelete):
                let dataBeforeApplyingOperation = data

                // RTLM15d5
                applyObjectDeleteOperation(
                    objectMessageSerialTimestamp: objectMessageSerialTimestamp,
                    logger: logger,
                    clock: clock,
                    userCallbackQueue: userCallbackQueue,
                )

                // RTLM15d5a
                liveObjectMutableState.emit(.update(.init(update: dataBeforeApplyingOperation.mapValues { _ in .removed })), on: userCallbackQueue)
            default:
                // RTLM15d4
                logger.log("Operation \(operation) has unsupported action for LiveMap; discarding", level: .warn)
            }
        }

        /// Applies a `MAP_SET` operation to a key, per RTLM7.
        internal mutating func applyMapSetOperation(
            key: String,
            operationTimeserial: String?,
            operationData: ObjectData?,
            objectsPool: inout ObjectsPool,
            logger: Logger,
            userCallbackQueue: DispatchQueue,
            clock: SimpleClock,
        ) -> LiveObjectUpdate<DefaultLiveMapUpdate> {
            // RTLM7a: If an entry exists in the private data for the specified key
            if let existingEntry = data[key] {
                // RTLM7a1: If the operation cannot be applied as per RTLM9, discard the operation
                if !Self.canApplyMapOperation(entryTimeserial: existingEntry.timeserial, operationTimeserial: operationTimeserial) {
                    return .noop
                }
                // RTLM7a2: Otherwise, apply the operation
                // RTLM7a2a: Set ObjectsMapEntry.data to the ObjectData from the operation
                // RTLM7a2b: Set ObjectsMapEntry.timeserial to the operation's serial
                // RTLM7a2c: Set ObjectsMapEntry.tombstone to false (same as RTLM7a2d: Set ObjectsMapEntry.tombstonedAt to nil)
                var updatedEntry = existingEntry
                updatedEntry.data = operationData
                updatedEntry.timeserial = operationTimeserial
                updatedEntry.tombstonedAt = nil
                data[key] = updatedEntry
            } else {
                // RTLM7b: If an entry does not exist in the private data for the specified key
                // RTLM7b1: Create a new entry in data for the specified key with the provided ObjectData and the operation's serial
                // RTLM7b2: Set ObjectsMapEntry.tombstone for the new entry to false (same as RTLM7b3: Set tombstonedAt to nil)
                data[key] = InternalObjectsMapEntry(tombstonedAt: nil, timeserial: operationTimeserial, data: operationData)
            }

            // RTLM7c: If the operation has a non-empty ObjectData.objectId attribute
            if let objectId = operationData?.objectId, !objectId.isEmpty {
                // RTLM7c1: Create a zero-value LiveObject in the internal ObjectsPool per RTO6
                _ = objectsPool.createZeroValueObject(forObjectID: objectId, logger: logger, userCallbackQueue: userCallbackQueue, clock: clock)
            }

            // RTLM7f
            return .update(DefaultLiveMapUpdate(update: [key: .updated]))
        }

        /// Applies a `MAP_REMOVE` operation to a key, per RTLM8.
        internal mutating func applyMapRemoveOperation(key: String, operationTimeserial: String?, operationSerialTimestamp: Date?, logger: Logger, clock: SimpleClock) -> LiveObjectUpdate<DefaultLiveMapUpdate> {
            // (Note that, where the spec tells us to set ObjectsMapEntry.data to nil, we actually set it to an empty ObjectData, which is equivalent, since it contains no data)

            // Calculate the tombstonedAt for the new or updated entry per RTLM8f
            let tombstonedAt: Date?
            if let operationSerialTimestamp {
                // RTLM8f1
                tombstonedAt = operationSerialTimestamp
            } else {
                // RTLM8f2
                logger.log("serialTimestamp not provided for MAP_REMOVE, using local clock for tombstone timestamp", level: .debug)
                // RTLM8f2a
                tombstonedAt = clock.now
            }

            // RTLM8a: If an entry exists in the private data for the specified key
            if let existingEntry = data[key] {
                // RTLM8a1: If the operation cannot be applied as per RTLM9, discard the operation
                if !Self.canApplyMapOperation(entryTimeserial: existingEntry.timeserial, operationTimeserial: operationTimeserial) {
                    return .noop
                }
                // RTLM8a2: Otherwise, apply the operation
                // RTLM8a2a: Set ObjectsMapEntry.data to undefined/null
                // RTLM8a2b: Set ObjectsMapEntry.timeserial to the operation's serial
                // RTLM8a2c: Set ObjectsMapEntry.tombstone to true (equivalent to next point)
                // RTLM8a2d: Set ObjectsMapEntry.tombstonedAt per RTLM8a2d
                var updatedEntry = existingEntry
                updatedEntry.data = nil
                updatedEntry.timeserial = operationTimeserial
                updatedEntry.tombstonedAt = tombstonedAt
                data[key] = updatedEntry
            } else {
                // RTLM8b: If an entry does not exist in the private data for the specified key
                // RTLM8b1: Create a new entry in data for the specified key, with ObjectsMapEntry.data set to undefined/null and the operation's serial
                // RTLM8b2: Set ObjectsMapEntry.tombstone for the new entry to true
                // RTLM8b3: Set ObjectsMapEntry.tombstonedAt per RTLM8f
                data[key] = InternalObjectsMapEntry(tombstonedAt: tombstonedAt, timeserial: operationTimeserial, data: nil)
            }

            return .update(DefaultLiveMapUpdate(update: [key: .removed]))
        }

        /// Determines whether a map operation can be applied to a map entry, per RTLM9.
        private static func canApplyMapOperation(entryTimeserial: String?, operationTimeserial: String?) -> Bool {
            // I am going to treat "exists" and "is non-empty" as equivalent here, because the spec mentions "null or empty" in some places and is vague in others.
            func normalize(timeserial: String?) -> String? {
                // swiftlint:disable:next empty_string
                timeserial == "" ? nil : timeserial
            }

            let (
                normalizedEntryTimeserial,
                normalizedOperationTimeserial
            ) = (
                normalize(timeserial: entryTimeserial),
                normalize(timeserial: operationTimeserial),
            )

            return switch (normalizedEntryTimeserial, normalizedOperationTimeserial) {
            case let (.some(normalizedEntryTimeserial), .some(normalizedOperationTimeserial)):
                // RTLM9a: For a LiveMap using LWW (Last-Write-Wins) CRDT semantics, the operation must
                // only be applied if its serial is strictly greater ("after") than the entry's serial
                // when compared lexicographically
                // RTLM9e: If both serials exist, compare them lexicographically and allow operation
                // to be applied only if the operation's serial is greater than the entry's serial
                normalizedOperationTimeserial > normalizedEntryTimeserial
            case (nil, .some):
                // RTLM9d: If only the operation serial exists, it is considered greater than the missing
                // entry serial, so the operation can be applied
                true
            case (.some, nil):
                // RTLM9c: If only the entry serial exists, the missing operation serial is considered lower
                // than the existing entry serial, so the operation must not be applied
                false
            case (nil, nil):
                // RTLM9b: If both the entry serial and the operation serial are null or empty strings,
                // they are treated as the "earliest possible" serials and considered "equal",
                // so the operation must not be applied
                false
            }
        }

        /// Applies a `MAP_CREATE` operation, per RTLM16.
        internal mutating func applyMapCreateOperation(
            _ operation: ObjectOperation,
            objectsPool: inout ObjectsPool,
            logger: Logger,
            userCallbackQueue: DispatchQueue,
            clock: SimpleClock,
        ) -> LiveObjectUpdate<DefaultLiveMapUpdate> {
            if liveObjectMutableState.createOperationIsMerged {
                // RTLM16b
                logger.log("Not applying MAP_CREATE because a MAP_CREATE has already been applied", level: .warn)
                return .noop
            }

            // TODO: RTLM16c `semantics` comparison; outstanding question in https://github.com/ably/specification/pull/343/files#r2192784482

            // RTLM16d, RTLM16f
            return mergeInitialValue(
                from: operation,
                objectsPool: &objectsPool,
                logger: logger,
                userCallbackQueue: userCallbackQueue,
                clock: clock,
            )
        }

        /// Resets the map's data and emits a `removed` event for the existing keys, per RTO4b2 and RTO4b2a. This is to be used when an `ATTACHED` ProtocolMessage indicates that the only object in a channel is an empty root map.
        internal mutating func resetData(userCallbackQueue: DispatchQueue) {
            // RTO4b2
            let previousData = data
            data = [:]

            // RTO4b2a
            let mapUpdate = DefaultLiveMapUpdate(update: previousData.mapValues { _ in .removed })
            liveObjectMutableState.emit(.update(mapUpdate), on: userCallbackQueue)
        }

        /// Needed for ``InternalLiveObject`` conformance.
        mutating func resetDataToZeroValued() {
            // RTLM4
            data = [:]
        }

        /// Releases entries that were tombstoned more than `gracePeriod` ago, per RTLM19.
        internal mutating func releaseTombstonedEntries(
            gracePeriod: TimeInterval,
            logger: Logger,
            clock: SimpleClock,
        ) {
            let now = clock.now

            // RTLM19a, RTLM19a1
            data = data.filter { key, entry in
                let shouldRelease = {
                    guard let tombstonedAt = entry.tombstonedAt else {
                        return false
                    }

                    return now.timeIntervalSince(tombstonedAt) >= gracePeriod
                }()

                if shouldRelease {
                    logger.log("Releasing tombstoned entry \(entry) for key \(key)", level: .debug)
                }
                return !shouldRelease
            }
        }

        /// Returns the value associated with a given key, following RTLM5d specification.
        internal func get(key: String, coreSDK: CoreSDK, delegate: LiveMapObjectPoolDelegate) throws(ARTErrorInfo) -> InternalLiveMapValue? {
            // RTLM5c: If the channel is in the DETACHED or FAILED state, the library should indicate an error with code 90001
            try coreSDK.validateChannelState(notIn: [.detached, .failed], operationDescription: "LiveMap.get")

            // RTLM5e - Return nil if self is tombstone
            if liveObjectMutableState.isTombstone {
                return nil
            }

            // RTLM5d1: If no ObjectsMapEntry exists at the key, return undefined/null
            guard let entry = data[key] else {
                return nil
            }

            // RTLM5d2: If a ObjectsMapEntry exists at the key, convert it using the shared logic
            return convertEntryToLiveMapValue(entry, delegate: delegate)
        }

        internal func size(coreSDK: CoreSDK, delegate: LiveMapObjectPoolDelegate) throws(ARTErrorInfo) -> Int {
            // RTLM10c: If the channel is in the DETACHED or FAILED state, the library should throw an ErrorInfo error with statusCode 400 and code 90001
            try coreSDK.validateChannelState(notIn: [.detached, .failed], operationDescription: "LiveMap.size")

            // RTLM10d: Returns the number of non-tombstoned entries (per RTLM14) in the internal data map
            return data.values.count { entry in
                !Self.isEntryTombstoned(entry, delegate: delegate)
            }
        }

        internal func entries(coreSDK: CoreSDK, delegate: LiveMapObjectPoolDelegate) throws(ARTErrorInfo) -> [(key: String, value: InternalLiveMapValue)] {
            // RTLM11c: If the channel is in the DETACHED or FAILED state, the library should throw an ErrorInfo error with statusCode 400 and code 90001
            try coreSDK.validateChannelState(notIn: [.detached, .failed], operationDescription: "LiveMap.entries")

            // RTLM11d: Returns key-value pairs from the internal data map
            // RTLM11d1: Pairs with tombstoned entries (per RTLM14) are not returned
            var result: [(key: String, value: InternalLiveMapValue)] = []

            for (key, entry) in data where !Self.isEntryTombstoned(entry, delegate: delegate) {
                // Convert entry to LiveMapValue using the same logic as get(key:)
                if let value = convertEntryToLiveMapValue(entry, delegate: delegate) {
                    result.append((key: key, value: value))
                }
            }

            return result
        }

        // MARK: - Helper Methods

        /// Returns whether a map entry should be considered tombstoned, per the check described in RTLM14.
        private static func isEntryTombstoned(_ entry: InternalObjectsMapEntry, delegate: LiveMapObjectPoolDelegate) -> Bool {
            // RTLM14a
            if entry.tombstone {
                return true
            }

            // RTLM14c
            if let objectId = entry.data?.objectId {
                if let poolEntry = delegate.getObjectFromPool(id: objectId), poolEntry.isTombstone {
                    return true
                }
            }

            // RTLM14b
            return false
        }

        /// Converts an InternalObjectsMapEntry to LiveMapValue using the same logic as get(key:)
        /// This is used by entries to ensure consistent value conversion
        private func convertEntryToLiveMapValue(_ entry: InternalObjectsMapEntry, delegate: LiveMapObjectPoolDelegate) -> InternalLiveMapValue? {
            // RTLM5d2a: If ObjectsMapEntry.tombstone is true, return undefined/null
            if entry.tombstone == true {
                return nil
            }

            // Handle primitive values in the order specified by RTLM5d2b through RTLM5d2e

            // RTLM5d2b: If ObjectsMapEntry.data.boolean exists, return it
            if let boolean = entry.data?.boolean {
                return .bool(boolean)
            }

            // RTLM5d2c: If ObjectsMapEntry.data.bytes exists, return it
            if let bytes = entry.data?.bytes {
                return .data(bytes)
            }

            // RTLM5d2d: If ObjectsMapEntry.data.number exists, return it
            if let number = entry.data?.number {
                return .number(number.doubleValue)
            }

            // RTLM5d2e: If ObjectsMapEntry.data.string exists, return it
            if let string = entry.data?.string {
                return .string(string)
            }

            // TODO: Needs specification (see https://github.com/ably/ably-liveobjects-swift-plugin/issues/46)
            if let json = entry.data?.json {
                switch json {
                case let .array(array):
                    return .jsonArray(array)
                case let .object(object):
                    return .jsonObject(object)
                }
            }

            // RTLM5d2f: If ObjectsMapEntry.data.objectId exists, get the object stored at that objectId from the internal ObjectsPool
            if let objectId = entry.data?.objectId {
                // RTLM5d2f1: If an object with id objectId does not exist, return undefined/null
                guard let poolEntry = delegate.getObjectFromPool(id: objectId) else {
                    return nil
                }

                // RTLM5d2f3: If referenced object is tombstoned, return nil
                if poolEntry.isTombstone {
                    return nil
                }

                // RTLM5d2f2: Return referenced object
                switch poolEntry {
                case let .map(map):
                    return .liveMap(map)
                case let .counter(counter):
                    return .liveCounter(counter)
                }
            }

            // RTLM5d2g: Otherwise, return undefined/null
            return nil
        }
    }
}
