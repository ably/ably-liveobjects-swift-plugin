@testable import AblyLiveObjects
import Foundation
import Testing

struct SyncObjectsPoolTests {
    @Test
    func initCreatesEmptyPool() {
        let pool = SyncObjectsPool()

        #expect(pool.isEmpty)
    }

    // MARK: - accumulate: skip / reject

    @Test
    func accumulateSkipsMessageWithNoObjectState() {
        var pool = SyncObjectsPool()
        let message = TestFactories.inboundObjectMessage(object: nil)

        pool.accumulate(objectMessage: message, logger: TestLogger())

        #expect(pool.isEmpty)
    }

    // @spec RTO5f3
    @Test
    func accumulateSkipsUnsupportedObjectType() {
        var pool = SyncObjectsPool()
        // An ObjectState with neither map nor counter set.
        let message = TestFactories.inboundObjectMessage(
            object: TestFactories.objectState(objectId: "unknown:abc@1"),
        )

        pool.accumulate(objectMessage: message, logger: TestLogger())

        #expect(pool.isEmpty)
    }

    // MARK: - accumulate: store new (RTO5f1)

    // @spec RTO5f1
    @Test
    func accumulateStoresNewObjectMessage() {
        var pool = SyncObjectsPool()
        let timestamp = Date(timeIntervalSince1970: 1_000_000)
        let message = TestFactories.inboundObjectMessage(
            object: TestFactories.mapObjectState(objectId: "map:a@1"),
            serialTimestamp: timestamp,
        )

        pool.accumulate(objectMessage: message, logger: TestLogger())

        #expect(pool.count == 1)
        let entry = Array(pool).first
        #expect(entry?.state.objectId == "map:a@1")
        #expect(entry?.objectMessageSerialTimestamp == timestamp)
    }

    // MARK: - accumulate: partial map merge (RTO5f2a)

    // @spec RTO5f2a1
    @Test
    func accumulateReplacesMapEntryWhenTombstoneTrue() {
        var pool = SyncObjectsPool()
        let logger = TestLogger()

        let (key1, entry1) = TestFactories.stringMapEntry(key: "key1", value: "value1")
        let firstMessage = TestFactories.inboundObjectMessage(
            object: TestFactories.mapObjectState(
                objectId: "map:a@1",
                entries: [key1: entry1],
            ),
        )
        pool.accumulate(objectMessage: firstMessage, logger: logger)

        // Second message with tombstone=true should replace entirely.
        let (key2, entry2) = TestFactories.stringMapEntry(key: "key2", value: "value2")
        let tombstoneMessage = TestFactories.inboundObjectMessage(
            object: TestFactories.mapObjectState(
                objectId: "map:a@1",
                tombstone: true,
                entries: [key2: entry2],
            ),
        )
        pool.accumulate(objectMessage: tombstoneMessage, logger: logger)

        #expect(pool.count == 1)
        let entry = Array(pool).first
        #expect(entry?.state.tombstone == true)
        // Only the replacement entries should be present.
        #expect(entry?.state.map?.entries?["key2"] != nil)
        #expect(entry?.state.map?.entries?["key1"] == nil)
    }

    // @spec RTO5f2a2
    @Test
    func accumulateMergesMapEntries() {
        var pool = SyncObjectsPool()
        let logger = TestLogger()

        let (key1, entry1) = TestFactories.stringMapEntry(key: "key1", value: "value1")
        let firstMessage = TestFactories.inboundObjectMessage(
            object: TestFactories.mapObjectState(
                objectId: "map:a@1",
                entries: [key1: entry1],
            ),
        )
        pool.accumulate(objectMessage: firstMessage, logger: logger)

        let (key2, entry2) = TestFactories.stringMapEntry(key: "key2", value: "value2")
        let secondMessage = TestFactories.inboundObjectMessage(
            object: TestFactories.mapObjectState(
                objectId: "map:a@1",
                entries: [key2: entry2],
            ),
        )
        pool.accumulate(objectMessage: secondMessage, logger: logger)

        #expect(pool.count == 1)
        let entry = Array(pool).first
        #expect(entry?.state.map?.entries?["key1"] != nil)
        #expect(entry?.state.map?.entries?["key2"] != nil)
    }

    // @spec RTO5f2a2
    @Test
    func accumulateMergesMapEntriesFromMultipleMessages() {
        var pool = SyncObjectsPool()
        let logger = TestLogger()

        for i in 1 ... 3 {
            let (key, entry) = TestFactories.stringMapEntry(key: "key\(i)", value: "value\(i)")
            let message = TestFactories.inboundObjectMessage(
                object: TestFactories.mapObjectState(
                    objectId: "map:a@1",
                    entries: [key: entry],
                ),
            )
            pool.accumulate(objectMessage: message, logger: logger)
        }

        #expect(pool.count == 1)
        let entry = Array(pool).first
        #expect(entry?.state.map?.entries?.count == 3)
        for i in 1 ... 3 {
            #expect(entry?.state.map?.entries?["key\(i)"] != nil)
        }
    }

    // MARK: - accumulate: partial counter (RTO5f2b)

    // @spec RTO5f2b
    @Test
    func accumulateSkipsPartialCounter() {
        var pool = SyncObjectsPool()
        let logger = TestLogger()

        let firstMessage = TestFactories.inboundObjectMessage(
            object: TestFactories.counterObjectState(objectId: "counter:a@1", count: 10),
        )
        pool.accumulate(objectMessage: firstMessage, logger: logger)

        // A second counter message for the same objectId should be skipped.
        let secondMessage = TestFactories.inboundObjectMessage(
            object: TestFactories.counterObjectState(objectId: "counter:a@1", count: 20),
        )
        pool.accumulate(objectMessage: secondMessage, logger: logger)

        #expect(pool.count == 1)
        // The original entry should be preserved.
        let entry = Array(pool).first
        #expect(entry?.state.counter?.count == NSNumber(value: 10))
    }

    // MARK: - Iteration and serialTimestamp

    @Test
    func iterationYieldsAllEntries() {
        var pool = SyncObjectsPool()
        let logger = TestLogger()

        let objectIds = ["map:a@1", "counter:b@2", "map:c@3"]
        for objectId in objectIds {
            let message = if objectId.hasPrefix("map:") {
                TestFactories.inboundObjectMessage(
                    object: TestFactories.mapObjectState(objectId: objectId),
                )
            } else {
                TestFactories.inboundObjectMessage(
                    object: TestFactories.counterObjectState(objectId: objectId),
                )
            }
            pool.accumulate(objectMessage: message, logger: logger)
        }

        let iteratedObjectIds = Set(pool.map(\.state.objectId))

        #expect(iteratedObjectIds == Set(objectIds))
    }

    @Test
    func entryPreservesObjectMessageSerialTimestamp() {
        var pool = SyncObjectsPool()
        let timestamp = Date(timeIntervalSince1970: 1_000_000)
        let message = TestFactories.inboundObjectMessage(
            object: TestFactories.mapObjectState(),
            serialTimestamp: timestamp,
        )

        pool.accumulate(objectMessage: message, logger: TestLogger())

        let entry = Array(pool).first
        #expect(entry?.objectMessageSerialTimestamp == timestamp)
    }

    @Test
    func entryAllowsNilObjectMessageSerialTimestamp() {
        var pool = SyncObjectsPool()
        let message = TestFactories.inboundObjectMessage(
            object: TestFactories.mapObjectState(),
            serialTimestamp: nil,
        )

        pool.accumulate(objectMessage: message, logger: TestLogger())

        let entry = Array(pool).first
        #expect(entry?.objectMessageSerialTimestamp == nil)
    }
}
