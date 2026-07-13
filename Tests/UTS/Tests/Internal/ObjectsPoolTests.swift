import Ably
import Foundation
import Testing
@testable import AblyLiveObjects

/// The `ObjectsPool` data structure and the RTO4/RTO5 sync state machine (`RTO3`–`RTO9`).
/// Derived from https://github.com/ably/specification/blob/0a531c79adfc072c6d1441591f2dd838913dfe73/uts/objects/unit/objects_pool.md
///
/// The spec drives everything through a bare `pool` (`pool.processAttached` / `processObjectSync` /
/// `processObjectMessage`, `pool.syncState`, `RealtimeObject(pool:)`). In this SDK the pool is owned
/// by ``InternalDefaultRealtimeObjects``, which is where the sync state, buffered operations and
/// `appliedOnAckSerials` live; the spec verbs map to its `nosync_*` handlers (run on the internal
/// queue via `onQueue(_:)`) and the state is read via `testsOnly_*` accessors. The spec's direct pool
/// pre-seeding maps to `testsOnly_setLiveMap` / `testsOnly_setLiveCounter` (`pool[id] = obj`) and
/// `testsOnly_setData` (`pool[id].data = …`).
///
/// Each `objectStateMessage(…)` composition mirrors the spec's `build_object_state(objectId,
/// siteTimeserials, { map | counter, createOp })` — the same parameters, in the same shape, with the
/// map's `{ semantics, entries }` built via ``StandardTestPool/objectsMap(semantics:entries:clearTimeserial:)``.
/// The `channel` argument of the spec's `build_object_sync_message(channel, channelSerial, …)` (e.g.
/// `"test"`) has no counterpart here: ``InternalDefaultRealtimeObjects`` is already scoped to a single
/// channel, so `nosync_handleObjectSyncProtocolMessage` takes only the messages and the channelSerial.
@Suite(.serialized)
final class ObjectsPoolTests: UTSTestCase {

    // MARK: - RTO3 — initialization

    // UTS: objects/unit/RTO3/pool-init-root-0
    @Test
    func test_RTO3_pool_initialized_with_root_map() {
        let pool = makePool()

        #expect(pool.entries["root"]?.mapValue != nil)
        #expect(pool.root.testsOnly_data.isEmpty)
        #expect(pool.root.testsOnly_objectID == "root")
    }

    // MARK: - RTO4 — ATTACHED handling

    // UTS: objects/unit/RTO4/attached-has-objects-syncing-0
    @Test
    func test_RTO4_attached_with_has_objects_starts_syncing() {
        let realtimeObjects = makeRealtimeObjects()
        onQueue { realtimeObjects.nosync_onChannelAttached(hasObjects: true) }
        #expect(realtimeObjects.testsOnly_objectsSyncState == .syncing)
    }

    // UTS: objects/unit/RTO4b/attached-no-objects-synced-0
    @Test
    func test_RTO4b_attached_without_has_objects_clears_pool_and_syncs() {
        // DEVIATION (RTO4b2a): the emitted `DefaultLiveMapUpdate` carries no `objectMessage` field, so
        // "objectMessage IS null" is not expressible; we assert the removed-entry update instead.
        let realtimeObjects = makeRealtimeObjects()
        // Seed the pre-state directly (`pool["counter:abc@1000"] = …` / `pool["root"].data = …`).
        // These `testsOnly_` methods self-synchronize, so they run off the internal queue; both mutate
        // the RealtimeObjects' own pool (the copy from `testsOnly_objectsPool` shares the `root` class
        // instance, and `testsOnly_setLiveCounter` inserts into the live pool).
        realtimeObjects.testsOnly_setLiveCounter(makeCounter(objectID: "counter:abc@1000"))
        let pool = realtimeObjects.testsOnly_objectsPool
        pool.root.testsOnly_setData(StandardTestPool.internalMapEntries(["name": StandardTestPool.data(string: "Alice")]))

        let updates = Captured<DefaultLiveMapUpdate>()
        let coreSDK = makeCoreSDK()
        _ = try? pool.root.subscribe(listener: { update, _ in updates.append(update) }, coreSDK: coreSDK)
        onQueue {
            realtimeObjects.nosync_onChannelAttached(hasObjects: false)
        }
        flushCallbacks()

        #expect(realtimeObjects.testsOnly_objectsSyncState == .synced)
        let finalPool = realtimeObjects.testsOnly_objectsPool
        #expect(finalPool.entries["counter:abc@1000"] == nil)
        #expect(finalPool.entries["root"] != nil)
        #expect(finalPool.root.testsOnly_data.isEmpty)
        #expect(updates.count >= 1)
        #expect(updates.first?.update["name"] == .removed)
    }

    // UTS: objects/unit/RTO4d/attached-clears-buffer-0
    @Test
    func test_RTO4d_attached_clears_buffered_operations() {
        let realtimeObjects = makeRealtimeObjects()
        onQueue {
            realtimeObjects.nosync_onChannelAttached(hasObjects: true)
            realtimeObjects.nosync_handleObjectProtocolMessage(objectMessages: [
                StandardTestPool.counterInc(objectId: "counter:abc@1000", number: 5, serial: "01", siteCode: "site1"),
            ])
        }
        #expect(realtimeObjects.testsOnly_bufferedObjectOperationsCount == 1)

        onQueue { realtimeObjects.nosync_onChannelAttached(hasObjects: true) }
        #expect(realtimeObjects.testsOnly_bufferedObjectOperationsCount == 0)
    }

    // UTS: objects/unit/RTO4-RTO5/attached-during-syncing-resets-0
    @Test
    func test_RTO4_RTO5_attached_during_syncing_resets_sync() {
        let realtimeObjects = makeRealtimeObjects()
        onQueue {
            realtimeObjects.nosync_onChannelAttached(hasObjects: true)
            realtimeObjects.nosync_handleObjectSyncProtocolMessage(
                objectMessages: [
                    StandardTestPool.objectStateMessage(
                        objectId: "counter:old@1000",
                        siteTimeserials: ["aaa": "t:0"],
                        counter: WireObjectsCounter(count: NSNumber(value: 10)),
                    ),
                ],
                protocolMessageChannelSerial: "sync1:more",
            )
        }
        #expect(realtimeObjects.testsOnly_objectsSyncState == .syncing)

        onQueue {
            realtimeObjects.nosync_onChannelAttached(hasObjects: true)
            realtimeObjects.nosync_handleObjectSyncProtocolMessage(
                objectMessages: [
                    StandardTestPool.objectStateMessage(
                        objectId: "root",
                        siteTimeserials: ["aaa": "t:0"],
                        map: StandardTestPool.objectsMap(
                            semantics: .lww,
                            entries: StandardTestPool.mapEntries([:]),
                        ),
                        createOp: StandardTestPool.mapCreateOp(objectId: "root"),
                    ),
                    StandardTestPool.objectStateMessage(
                        objectId: "counter:new@1000",
                        siteTimeserials: ["aaa": "t:0"],
                        counter: WireObjectsCounter(count: NSNumber(value: 99)),
                    ),
                ],
                protocolMessageChannelSerial: "sync2:",
            )
        }

        #expect(realtimeObjects.testsOnly_objectsSyncState == .synced)
        #expect(realtimeObjects.testsOnly_objectsPool.entries["counter:old@1000"] == nil)
        #expect(realtimeObjects.testsOnly_objectsPool.entries["counter:new@1000"] != nil)
    }

    // MARK: - RTO5 — OBJECT_SYNC handling

    // UTS: objects/unit/RTO5/sync-complete-sequence-0
    @Test
    func test_RTO5_object_sync_complete_sequence() throws {
        let coreSDK = makeCoreSDK()
        let realtimeObjects = makeRealtimeObjects()
        onQueue {
            realtimeObjects.nosync_onChannelAttached(hasObjects: true)
            realtimeObjects.nosync_handleObjectSyncProtocolMessage(
                objectMessages: [
                    StandardTestPool.objectStateMessage(
                        objectId: "root",
                        siteTimeserials: ["aaa": "t:0"],
                        map: StandardTestPool.objectsMap(
                            semantics: .lww,
                            entries: StandardTestPool.mapEntries(["name": StandardTestPool.data(string: "Alice")]),
                        ),
                        createOp: StandardTestPool.mapCreateOp(objectId: "root"),
                    ),
                    StandardTestPool.objectStateMessage(
                        objectId: "counter:abc@1000",
                        siteTimeserials: ["aaa": "t:0"],
                        counter: WireObjectsCounter(count: NSNumber(value: 0)),
                        createOp: StandardTestPool.counterCreateOp(objectId: "counter:abc@1000", count: 42),
                    ),
                ],
                protocolMessageChannelSerial: "sync1:",
            )
        }

        #expect(realtimeObjects.testsOnly_objectsSyncState == .synced)
        let pool = realtimeObjects.testsOnly_objectsPool
        #expect(pool.entries["root"] != nil)
        #expect(pool.root.testsOnly_data["name"]?.data?.string == "Alice")
        let counter = try #require(pool.entries["counter:abc@1000"]?.counterValue)
        #expect(try counter.value(coreSDK: coreSDK) == 42)
    }

    // UTS: objects/unit/RTO5a2/new-sequence-discards-old-0
    @Test
    func test_RTO5a2_new_sequence_discards_previous() {
        let realtimeObjects = makeRealtimeObjects()
        onQueue {
            realtimeObjects.nosync_onChannelAttached(hasObjects: true)
            realtimeObjects.nosync_handleObjectSyncProtocolMessage(
                objectMessages: [
                    StandardTestPool.objectStateMessage(
                        objectId: "counter:old@1000",
                        siteTimeserials: ["aaa": "t:0"],
                        counter: WireObjectsCounter(count: NSNumber(value: 10)),
                    ),
                ],
                protocolMessageChannelSerial: "seq1:more",
            )
            realtimeObjects.nosync_handleObjectSyncProtocolMessage(
                objectMessages: [
                    StandardTestPool.objectStateMessage(
                        objectId: "root",
                        siteTimeserials: ["aaa": "t:0"],
                        map: StandardTestPool.objectsMap(
                            semantics: .lww,
                            entries: StandardTestPool.mapEntries([:]),
                        ),
                        createOp: StandardTestPool.mapCreateOp(objectId: "root"),
                    ),
                    StandardTestPool.objectStateMessage(
                        objectId: "counter:new@1000",
                        siteTimeserials: ["aaa": "t:0"],
                        counter: WireObjectsCounter(count: NSNumber(value: 99)),
                    ),
                ],
                protocolMessageChannelSerial: "seq2:",
            )
        }

        #expect(realtimeObjects.testsOnly_objectsSyncState == .synced)
        #expect(realtimeObjects.testsOnly_objectsPool.entries["counter:old@1000"] == nil)
        #expect(realtimeObjects.testsOnly_objectsPool.entries["counter:new@1000"] != nil)
    }

    // UTS: objects/unit/RTO5f2a/partial-map-merge-0
    @Test
    func test_RTO5f2a_partial_object_state_merge_for_maps() {
        let realtimeObjects = makeRealtimeObjects()
        onQueue {
            realtimeObjects.nosync_onChannelAttached(hasObjects: true)
            realtimeObjects.nosync_handleObjectSyncProtocolMessage(
                objectMessages: [
                    StandardTestPool.objectStateMessage(
                        objectId: "root",
                        siteTimeserials: ["aaa": "t:0"],
                        map: StandardTestPool.objectsMap(
                            semantics: .lww,
                            entries: StandardTestPool.mapEntries(["name": StandardTestPool.data(string: "Alice")]),
                        ),
                    ),
                ],
                protocolMessageChannelSerial: "sync1:more",
            )
            realtimeObjects.nosync_handleObjectSyncProtocolMessage(
                objectMessages: [
                    StandardTestPool.objectStateMessage(
                        objectId: "root",
                        siteTimeserials: ["aaa": "t:0"],
                        map: StandardTestPool.objectsMap(
                            semantics: .lww,
                            entries: StandardTestPool.mapEntries(["age": StandardTestPool.data(number: 30)]),
                        ),
                        createOp: StandardTestPool.mapCreateOp(objectId: "root"),
                    ),
                ],
                protocolMessageChannelSerial: "sync1:",
            )
        }

        let root = realtimeObjects.testsOnly_objectsPool.root
        #expect(root.testsOnly_data["name"]?.data?.string == "Alice")
        #expect(root.testsOnly_data["age"]?.data?.number == 30)
    }

    // UTS: objects/unit/RTO5c2/remove-absent-objects-0
    @Test
    func test_RTO5c2_sync_completion_removes_objects_not_in_sync() {
        let realtimeObjects = makeRealtimeObjects()
        // Seed the object to be removed directly (`pool["counter:old@1000"] = …`; the spec's data of
        // 99 isn't material — the test only asserts the object is removed).
        realtimeObjects.testsOnly_setLiveCounter(makeCounter(objectID: "counter:old@1000"))
        onQueue {
            realtimeObjects.nosync_onChannelAttached(hasObjects: true)
            realtimeObjects.nosync_handleObjectSyncProtocolMessage(
                objectMessages: [
                    StandardTestPool.objectStateMessage(
                        objectId: "root",
                        siteTimeserials: ["aaa": "t:0"],
                        map: StandardTestPool.objectsMap(
                            semantics: .lww,
                            entries: StandardTestPool.mapEntries([:]),
                        ),
                        createOp: StandardTestPool.mapCreateOp(objectId: "root"),
                    ),
                ],
                protocolMessageChannelSerial: "sync1:",
            )
        }

        #expect(realtimeObjects.testsOnly_objectsPool.entries["counter:old@1000"] == nil)
        #expect(realtimeObjects.testsOnly_objectsPool.entries["root"] != nil)
    }

    // UTS: objects/unit/RTO5d/null-object-skipped-0
    @Test
    func test_RTO5d_object_sync_with_null_object_field_is_skipped() {
        let realtimeObjects = makeRealtimeObjects()
        onQueue {
            realtimeObjects.nosync_onChannelAttached(hasObjects: true)
            realtimeObjects.nosync_handleObjectSyncProtocolMessage(
                objectMessages: [
                    ProtocolTypes.InboundObjectMessage(),
                    StandardTestPool.objectStateMessage(
                        objectId: "root",
                        siteTimeserials: ["aaa": "t:0"],
                        map: StandardTestPool.objectsMap(
                            semantics: .lww,
                            entries: StandardTestPool.mapEntries([:]),
                        ),
                        createOp: StandardTestPool.mapCreateOp(objectId: "root"),
                    ),
                ],
                protocolMessageChannelSerial: "sync1:",
            )
        }
        #expect(realtimeObjects.testsOnly_objectsSyncState == .synced)
    }

    // UTS: objects/unit/RTO5f3/unsupported-type-skipped-0
    @Test
    func test_RTO5f3_object_sync_with_unsupported_object_type_is_skipped() {
        let realtimeObjects = makeRealtimeObjects()
        onQueue {
            realtimeObjects.nosync_onChannelAttached(hasObjects: true)
            realtimeObjects.nosync_handleObjectSyncProtocolMessage(
                objectMessages: [
                    StandardTestPool.objectStateMessage(
                        objectId: "root",
                        siteTimeserials: ["aaa": "t:0"],
                        map: StandardTestPool.objectsMap(
                            semantics: .lww,
                            entries: StandardTestPool.mapEntries([:]),
                        ),
                        createOp: StandardTestPool.mapCreateOp(objectId: "root"),
                    ),
                    StandardTestPool.objectStateMessage(
                        objectId: "unknown:xyz@1000",
                        siteTimeserials: [:],
                    ),
                ],
                protocolMessageChannelSerial: "sync1:",
            )
        }

        #expect(realtimeObjects.testsOnly_objectsSyncState == .synced)
        #expect(realtimeObjects.testsOnly_objectsPool.entries["unknown:xyz@1000"] == nil)
    }

    // UTS: objects/unit/RTO5e/object-sync-transitions-syncing-0
    @Test
    func test_RTO5e_object_sync_transitions_to_syncing() {
        let realtimeObjects = makeRealtimeObjects()
        onQueue {
            realtimeObjects.nosync_handleObjectSyncProtocolMessage(
                objectMessages: [
                    StandardTestPool.objectStateMessage(
                        objectId: "root",
                        siteTimeserials: ["aaa": "t:0"],
                        map: StandardTestPool.objectsMap(
                            semantics: .lww,
                            entries: StandardTestPool.mapEntries([:]),
                        ),
                    ),
                ],
                protocolMessageChannelSerial: "sync1:more",
            )
        }
        #expect(realtimeObjects.testsOnly_objectsSyncState == .syncing)
    }

    // UTS: objects/unit/RTO5c7/sync-emits-updates-0
    @Test
    func test_RTO5c7_sync_completion_emits_updates_for_existing_objects() {
        let realtimeObjects = makeRealtimeObjects()
        // Seed the previous root value directly (`pool["root"].data = { name: "Old" }`); a sync then
        // replaces it with "New", emitting a LiveMapUpdate that marks "name" as updated.
        var pool = realtimeObjects.testsOnly_objectsPool
        _ = pool.root.testsOnly_applyMapSetOperation(
            key: "name",
            operationTimeserial: "01",
            operationData: StandardTestPool.data(string: "Old"),
            objectsPool: &pool,
        )

        let updates = Captured<DefaultLiveMapUpdate>()
        let coreSDK = makeCoreSDK()
        _ = try? pool.root.subscribe(listener: { update, _ in updates.append(update) }, coreSDK: coreSDK)
        onQueue {
            realtimeObjects.nosync_onChannelAttached(hasObjects: true)
            realtimeObjects.nosync_handleObjectSyncProtocolMessage(
                objectMessages: [
                    StandardTestPool.objectStateMessage(
                        objectId: "root",
                        siteTimeserials: ["aaa": "t:1"],
                        map: StandardTestPool.objectsMap(
                            semantics: .lww,
                            entries: StandardTestPool.mapEntries(["name": StandardTestPool.data(string: "New")]),
                        ),
                        createOp: StandardTestPool.mapCreateOp(objectId: "root"),
                    ),
                ],
                protocolMessageChannelSerial: "sync1:",
            )
        }
        flushCallbacks()

        #expect(updates.count >= 1)
        #expect(updates.first?.update["name"] == .updated)
    }

    // UTS: objects/unit/RTO5f2b/partial-counter-error-0
    @Test
    func test_RTO5f2b_partial_counter_state_is_rejected() throws {
        let coreSDK = makeCoreSDK()
        let realtimeObjects = makeRealtimeObjects()
        onQueue {
            realtimeObjects.nosync_onChannelAttached(hasObjects: true)
            realtimeObjects.nosync_handleObjectSyncProtocolMessage(
                objectMessages: [
                    StandardTestPool.objectStateMessage(
                        objectId: "counter:abc@1000",
                        siteTimeserials: ["aaa": "t:0"],
                        counter: WireObjectsCounter(count: NSNumber(value: 10)),
                    ),
                ],
                protocolMessageChannelSerial: "sync1:more",
            )
            realtimeObjects.nosync_handleObjectSyncProtocolMessage(
                objectMessages: [
                    StandardTestPool.objectStateMessage(
                        objectId: "root",
                        siteTimeserials: ["aaa": "t:0"],
                        map: StandardTestPool.objectsMap(
                            semantics: .lww,
                            entries: StandardTestPool.mapEntries([:]),
                        ),
                        createOp: StandardTestPool.mapCreateOp(objectId: "root"),
                    ),
                    StandardTestPool.objectStateMessage(
                        objectId: "counter:abc@1000",
                        siteTimeserials: ["aaa": "t:0"],
                        counter: WireObjectsCounter(count: NSNumber(value: 5)),
                    ),
                ],
                protocolMessageChannelSerial: "sync1:",
            )
        }

        let counter = try #require(realtimeObjects.testsOnly_objectsPool.entries["counter:abc@1000"]?.counterValue)
        #expect(try counter.value(coreSDK: coreSDK) == 10)
    }

    // UTS: objects/unit/RTO5c-RTLM23/sync-clear-timeserial-hides-create-entries-0
    @Test
    func test_RTO5c_RTLM23_sync_clear_timeserial_hides_create_entries() {
        let realtimeObjects = makeRealtimeObjects()
        onQueue {
            realtimeObjects.nosync_onChannelAttached(hasObjects: true)
            realtimeObjects.nosync_handleObjectSyncProtocolMessage(
                objectMessages: [
                    StandardTestPool.objectStateMessage(
                        objectId: "root",
                        siteTimeserials: ["aaa": "t:0"],
                        map: StandardTestPool.objectsMap(
                            semantics: .lww,
                            entries: [:],
                            clearTimeserial: "05",
                        ),
                        createOp: ProtocolTypes.ObjectOperation(
                            action: .known(.mapCreate),
                            objectId: "root",
                            mapCreate: ProtocolTypes.MapCreate(
                                semantics: .known(.lww),
                                entries: [
                                    "old_key": ProtocolTypes.ObjectsMapEntry(timeserial: "03", data: StandardTestPool.data(string: "old")),
                                    "new_key": ProtocolTypes.ObjectsMapEntry(timeserial: "07", data: StandardTestPool.data(string: "new")),
                                ],
                            ),
                        ),
                    ),
                ],
                protocolMessageChannelSerial: "sync1:",
            )
        }

        #expect(realtimeObjects.testsOnly_objectsSyncState == .synced)
        let root = realtimeObjects.testsOnly_objectsPool.root
        #expect(root.testsOnly_data["old_key"] == nil)
        #expect(root.testsOnly_data["new_key"]?.data?.string == "new")
    }

    // MARK: - RTO7 / RTO8 — buffering

    // UTS: objects/unit/RTO8a/buffer-during-syncing-0
    @Test
    func test_RTO8a_object_messages_buffered_during_syncing() {
        let realtimeObjects = makeRealtimeObjects()
        onQueue {
            realtimeObjects.nosync_onChannelAttached(hasObjects: true)
            realtimeObjects.nosync_handleObjectProtocolMessage(objectMessages: [
                StandardTestPool.counterInc(objectId: "counter:abc@1000", number: 5, serial: "01", siteCode: "site1"),
            ])
        }

        #expect(realtimeObjects.testsOnly_objectsSyncState == .syncing)
        #expect(realtimeObjects.testsOnly_bufferedObjectOperationsCount == 1)
        #expect(realtimeObjects.testsOnly_objectsPool.entries["counter:abc@1000"] == nil)
    }

    // UTS: objects/unit/RTO5c6/apply-buffered-on-sync-0
    @Test
    func test_RTO5c6_buffered_operations_applied_on_sync_completion() throws {
        let coreSDK = makeCoreSDK()
        let realtimeObjects = makeRealtimeObjects()
        onQueue {
            realtimeObjects.nosync_onChannelAttached(hasObjects: true)
            realtimeObjects.nosync_handleObjectProtocolMessage(objectMessages: [
                StandardTestPool.counterInc(objectId: "counter:abc@1000", number: 10, serial: "02", siteCode: "site1"),
            ])
            realtimeObjects.nosync_handleObjectSyncProtocolMessage(
                objectMessages: [
                    StandardTestPool.objectStateMessage(
                        objectId: "root",
                        siteTimeserials: ["aaa": "t:0"],
                        map: StandardTestPool.objectsMap(
                            semantics: .lww,
                            entries: StandardTestPool.mapEntries([:]),
                        ),
                        createOp: StandardTestPool.mapCreateOp(objectId: "root"),
                    ),
                    StandardTestPool.objectStateMessage(
                        objectId: "counter:abc@1000",
                        siteTimeserials: ["aaa": "t:0"],
                        counter: WireObjectsCounter(count: NSNumber(value: 0)),
                        createOp: StandardTestPool.counterCreateOp(objectId: "counter:abc@1000", count: 100),
                    ),
                ],
                protocolMessageChannelSerial: "sync1:",
            )
        }

        let counter = try #require(realtimeObjects.testsOnly_objectsPool.entries["counter:abc@1000"]?.counterValue)
        #expect(try counter.value(coreSDK: coreSDK) == 110)
        #expect(realtimeObjects.testsOnly_bufferedObjectOperationsCount == nil) // no longer syncing
    }

    // UTS: objects/unit/RTO5-RTO7/new-sync-keeps-buffer-0
    @Test
    func test_RTO5_RTO7_new_object_sync_sequence_keeps_buffer() throws {
        let coreSDK = makeCoreSDK()
        let realtimeObjects = makeRealtimeObjects()
        onQueue {
            realtimeObjects.nosync_onChannelAttached(hasObjects: true)
            realtimeObjects.nosync_handleObjectProtocolMessage(objectMessages: [
                StandardTestPool.counterInc(objectId: "counter:abc@1000", number: 5, serial: "01", siteCode: "site1"),
            ])
        }
        #expect(realtimeObjects.testsOnly_bufferedObjectOperationsCount == 1)

        onQueue {
            realtimeObjects.nosync_handleObjectSyncProtocolMessage(
                objectMessages: [
                    StandardTestPool.objectStateMessage(
                        objectId: "root",
                        siteTimeserials: ["aaa": "t:0"],
                        map: StandardTestPool.objectsMap(
                            semantics: .lww,
                            entries: StandardTestPool.mapEntries([:]),
                        ),
                        createOp: StandardTestPool.mapCreateOp(objectId: "root"),
                    ),
                    StandardTestPool.objectStateMessage(
                        objectId: "counter:abc@1000",
                        siteTimeserials: ["aaa": "t:0"],
                        counter: WireObjectsCounter(count: NSNumber(value: 0)),
                        createOp: StandardTestPool.counterCreateOp(objectId: "counter:abc@1000", count: 100),
                    ),
                ],
                protocolMessageChannelSerial: "seq2:",
            )
        }

        #expect(realtimeObjects.testsOnly_objectsSyncState == .synced)
        let counter = try #require(realtimeObjects.testsOnly_objectsPool.entries["counter:abc@1000"]?.counterValue)
        #expect(try counter.value(coreSDK: coreSDK) == 105)
    }

    // UTS: objects/unit/RTO7-RTO8/buffer-without-attached-0
    @Test
    func test_RTO7_RTO8_object_message_in_initialized_state() {
        // DEVIATION (RTO8a): the spec expects buffering while INITIALIZED. This SDK only buffers while
        // SYNCING — it relies on the invariant that OBJECT messages only arrive after ATTACHED (which
        // moves it to SYNCING), so in INITIALIZED it applies immediately (see the RTO8b comment in
        // `InternalDefaultRealtimeObjects`). We assert the SDK's actual behaviour: nothing is buffered
        // and the object is created directly. See deviations.md.
        let realtimeObjects = makeRealtimeObjects()
        #expect(realtimeObjects.testsOnly_objectsSyncState == .initialized)
        onQueue {
            realtimeObjects.nosync_handleObjectProtocolMessage(objectMessages: [
                StandardTestPool.counterInc(objectId: "counter:abc@1000", number: 5, serial: "01", siteCode: "site1"),
            ])
        }

        #expect(realtimeObjects.testsOnly_bufferedObjectOperationsCount == nil)
        #expect(realtimeObjects.testsOnly_objectsPool.entries["counter:abc@1000"] != nil)
    }

    // MARK: - RTO9 — OBJECT application

    // UTS: objects/unit/RTO9a1/null-operation-warning-0
    @Test
    func test_RTO9a1_null_operation_is_discarded() {
        let realtimeObjects = makeRealtimeObjects()
        onQueue {
            realtimeObjects.nosync_onChannelAttached(hasObjects: false) // → synced
            realtimeObjects.nosync_handleObjectProtocolMessage(objectMessages: [
                ProtocolTypes.InboundObjectMessage(serial: "01", siteCode: "site1"),
            ])
        }
        #expect(realtimeObjects.testsOnly_objectsPool.entries.count == 1) // only root
    }

    // UTS: objects/unit/RTO9a2b/unsupported-action-warning-0
    @Test
    func test_RTO9a2b_unsupported_action_is_discarded() throws {
        // DEVIATION (RTO9a2b): the spec asserts the pool still has only root (the unsupported-action
        // message is discarded without creating an object). This SDK creates the zero-value object
        // (RTO9a2a2) *before* the action check (RTO9a2b), so the object exists but the operation is
        // not applied (the counter stays zero-valued). We assert the observable "not applied"
        // behaviour instead of the pool size. See deviations.md.
        let coreSDK = makeCoreSDK()
        let realtimeObjects = makeRealtimeObjects()
        onQueue {
            realtimeObjects.nosync_onChannelAttached(hasObjects: false) // → synced
            realtimeObjects.nosync_handleObjectProtocolMessage(objectMessages: [
                ProtocolTypes.InboundObjectMessage(
                    operation: ProtocolTypes.ObjectOperation(action: .unknown(999), objectId: "counter:abc@1000"),
                    serial: "01",
                    siteCode: "site1",
                ),
            ])
        }
        let counter = try #require(realtimeObjects.testsOnly_objectsPool.entries["counter:abc@1000"]?.counterValue)
        #expect(try counter.value(coreSDK: coreSDK) == 0) // operation not applied
    }

    // UTS: objects/unit/RTO6/zero-value-from-prefix-0
    @Test
    func test_RTO6_zero_value_object_created_from_objectId_prefix() throws {
        let coreSDK = makeCoreSDK()
        let realtimeObjects = makeRealtimeObjects()
        onQueue {
            realtimeObjects.nosync_onChannelAttached(hasObjects: false) // → synced
            realtimeObjects.nosync_handleObjectProtocolMessage(objectMessages: [
                StandardTestPool.counterInc(objectId: "counter:new@2000", number: 5, serial: "01", siteCode: "site1"),
            ])
            realtimeObjects.nosync_handleObjectProtocolMessage(objectMessages: [
                StandardTestPool.mapSet(objectId: "map:new@2000", key: "key", value: StandardTestPool.data(string: "val"), serial: "02", siteCode: "site1"),
            ])
        }

        let pool = realtimeObjects.testsOnly_objectsPool
        let counter = try #require(pool.entries["counter:new@2000"]?.counterValue)
        #expect(try counter.value(coreSDK: coreSDK) == 5)
        let map = try #require(pool.entries["map:new@2000"]?.mapValue)
        #expect(map.testsOnly_data["key"]?.data?.string == "val")
    }

    // UTS: objects/unit/RTO5c9/clear-applied-on-ack-serials-0
    @Test
    func test_RTO5c9_sync_completion_clears_appliedOnAckSerials() async throws {
        let realtimeObjects = makeRealtimeObjects()
        let coreSDK = makeCoreSDK { _ in PublishResult(serials: ["serial-1"]) }
        onQueue {
            realtimeObjects.nosync_onChannelAttached(hasObjects: false)
            realtimeObjects.nosync_setSiteCode("site1")
        }
        // Populate appliedOnAckSerials via a LOCAL operation (RTO9a2a4).
        _ = try await realtimeObjects.createCounter(count: 42, coreSDK: coreSDK)
        #expect(!realtimeObjects.testsOnly_appliedOnAckSerials.isEmpty)

        onQueue {
            realtimeObjects.nosync_onChannelAttached(hasObjects: true)
            realtimeObjects.nosync_handleObjectSyncProtocolMessage(
                objectMessages: [
                    StandardTestPool.objectStateMessage(
                        objectId: "root",
                        siteTimeserials: ["aaa": "t:0"],
                        map: StandardTestPool.objectsMap(
                            semantics: .lww,
                            entries: StandardTestPool.mapEntries([:]),
                        ),
                        createOp: StandardTestPool.mapCreateOp(objectId: "root"),
                    ),
                ],
                protocolMessageChannelSerial: "sync1:",
            )
        }

        #expect(realtimeObjects.testsOnly_appliedOnAckSerials.isEmpty)
    }

    // UTS: objects/unit/RTO9a2a4/local-source-adds-serial-0
    @Test
    func test_RTO9a2a4_local_source_adds_serial_to_appliedOnAckSerials() async throws {
        // ADAPTATION: the spec calls the internal `applyObjectMessages(source: LOCAL)` primitive
        // directly. Here a LOCAL apply is produced through the public path — a local `createCounter`,
        // whose COUNTER_CREATE is published (ACK serial "local-serial-1") and applied on ACK.
        let realtimeObjects = makeRealtimeObjects()
        let coreSDK = makeCoreSDK { _ in PublishResult(serials: ["local-serial-1"]) }
        onQueue {
            realtimeObjects.nosync_onChannelAttached(hasObjects: false)
            realtimeObjects.nosync_setSiteCode("test-site")
        }

        let counter = try await realtimeObjects.createCounter(count: 5, coreSDK: coreSDK)

        #expect(realtimeObjects.testsOnly_appliedOnAckSerials.contains("local-serial-1"))
        #expect(try counter.value(coreSDK: coreSDK) == 5)
    }

    // UTS: objects/unit/RTO9a3/dedup-applied-on-ack-0
    @Test
    func test_RTO9a3_appliedOnAckSerials_deduplication() async throws {
        let realtimeObjects = makeRealtimeObjects()
        let serial = "echo-serial-1"
        let coreSDK = makeCoreSDK { _ in PublishResult(serials: [serial]) }
        onQueue {
            realtimeObjects.nosync_onChannelAttached(hasObjects: false)
            realtimeObjects.nosync_setSiteCode("site1")
        }
        // A LOCAL createCounter records `serial` in appliedOnAckSerials.
        let counter = try await realtimeObjects.createCounter(count: 10, coreSDK: coreSDK)
        #expect(realtimeObjects.testsOnly_appliedOnAckSerials.contains(serial))
        let objectId = counter.testsOnly_objectID // read off the internal queue

        // The echoed channel-sourced message with the same serial is discarded and the serial removed.
        onQueue {
            realtimeObjects.nosync_handleObjectProtocolMessage(objectMessages: [
                StandardTestPool.counterInc(objectId: objectId, number: 5, serial: serial, siteCode: "site1"),
            ])
        }

        #expect(try counter.value(coreSDK: coreSDK) == 10) // unchanged
        #expect(!realtimeObjects.testsOnly_appliedOnAckSerials.contains(serial))
    }

    // MARK: - RTO5c10 — post-sync parentReferences rebuild

    // These assert `parentReferences`, which is a `notImplemented()` skeleton (see `ParentReferencing`),
    // so they compile and trap at runtime like the `ParentReferencesTests` cases.

    // UTS: objects/unit/RTO5c10/sync-rebuilds-parent-refs-0
    @Test
    func test_RTO5c10_sync_rebuilds_parentReferences() {
        let realtimeObjects = makeRealtimeObjects()
        onQueue {
            realtimeObjects.nosync_onChannelAttached(hasObjects: true)
            realtimeObjects.nosync_handleObjectSyncProtocolMessage(
                objectMessages: [
                    StandardTestPool.objectStateMessage(
                        objectId: "root",
                        siteTimeserials: ["aaa": "t:0"],
                        map: StandardTestPool.objectsMap(
                            semantics: .lww,
                            entries: StandardTestPool.mapEntries([
                                "score": StandardTestPool.data(objectId: "counter:score@1000"),
                                "profile": StandardTestPool.data(objectId: "map:profile@1000"),
                                "name": StandardTestPool.data(string: "Alice"),
                            ]),
                        ),
                        createOp: StandardTestPool.mapCreateOp(objectId: "root"),
                    ),
                    StandardTestPool.objectStateMessage(
                        objectId: "counter:score@1000",
                        siteTimeserials: ["aaa": "t:0"],
                        counter: WireObjectsCounter(count: NSNumber(value: 0)),
                        createOp: StandardTestPool.counterCreateOp(objectId: "counter:score@1000", count: 100),
                    ),
                    StandardTestPool.objectStateMessage(
                        objectId: "map:profile@1000",
                        siteTimeserials: ["aaa": "t:0"],
                        map: StandardTestPool.objectsMap(
                            semantics: .lww,
                            entries: StandardTestPool.mapEntries(["nested_counter": StandardTestPool.data(objectId: "counter:nested@1000")]),
                        ),
                        createOp: StandardTestPool.mapCreateOp(objectId: "map:profile@1000"),
                    ),
                    StandardTestPool.objectStateMessage(
                        objectId: "counter:nested@1000",
                        siteTimeserials: ["aaa": "t:0"],
                        counter: WireObjectsCounter(count: NSNumber(value: 0)),
                        createOp: StandardTestPool.counterCreateOp(objectId: "counter:nested@1000", count: 5),
                    ),
                ],
                protocolMessageChannelSerial: "sync1:",
            )
        }

        let pool = realtimeObjects.testsOnly_objectsPool
        #expect(pool.root.parentReferences == [:])
        #expect(pool.entries["counter:score@1000"]?.counterValue?.parentReferences == ["root": ["score"]])
        #expect(pool.entries["map:profile@1000"]?.mapValue?.parentReferences == ["root": ["profile"]])
        #expect(pool.entries["counter:nested@1000"]?.counterValue?.parentReferences == ["map:profile@1000": ["nested_counter"]])
    }

    // UTS: objects/unit/RTO5c10/resync-rebuilds-parent-refs-0
    @Test
    func test_RTO5c10_resync_rebuilds_parentReferences_with_new_tree() {
        let realtimeObjects = makeRealtimeObjects()
        onQueue {
            realtimeObjects.nosync_onChannelAttached(hasObjects: true)
            realtimeObjects.nosync_handleObjectSyncProtocolMessage(
                objectMessages: [
                    StandardTestPool.objectStateMessage(
                        objectId: "root",
                        siteTimeserials: ["aaa": "t:0"],
                        map: StandardTestPool.objectsMap(
                            semantics: .lww,
                            entries: StandardTestPool.mapEntries(["counter_key": StandardTestPool.data(objectId: "counter:abc@1000")]),
                        ),
                        createOp: StandardTestPool.mapCreateOp(objectId: "root"),
                    ),
                    StandardTestPool.objectStateMessage(
                        objectId: "counter:abc@1000",
                        siteTimeserials: ["aaa": "t:0"],
                        counter: WireObjectsCounter(count: NSNumber(value: 0)),
                        createOp: StandardTestPool.counterCreateOp(objectId: "counter:abc@1000", count: 10),
                    ),
                ],
                protocolMessageChannelSerial: "sync1:",
            )
        }
        #expect(realtimeObjects.testsOnly_objectsPool.entries["counter:abc@1000"]?.counterValue?.parentReferences == ["root": ["counter_key"]])

        onQueue {
            realtimeObjects.nosync_onChannelAttached(hasObjects: true)
            realtimeObjects.nosync_handleObjectSyncProtocolMessage(
                objectMessages: [
                    StandardTestPool.objectStateMessage(
                        objectId: "root",
                        siteTimeserials: ["aaa": "t:1"],
                        map: StandardTestPool.objectsMap(
                            semantics: .lww,
                            entries: StandardTestPool.mapEntries(["wrapper": StandardTestPool.data(objectId: "map:wrapper@1000")]),
                        ),
                        createOp: StandardTestPool.mapCreateOp(objectId: "root"),
                    ),
                    StandardTestPool.objectStateMessage(
                        objectId: "map:wrapper@1000",
                        siteTimeserials: ["aaa": "t:1"],
                        map: StandardTestPool.objectsMap(
                            semantics: .lww,
                            entries: StandardTestPool.mapEntries(["moved_counter": StandardTestPool.data(objectId: "counter:abc@1000")]),
                        ),
                        createOp: StandardTestPool.mapCreateOp(objectId: "map:wrapper@1000"),
                    ),
                    StandardTestPool.objectStateMessage(
                        objectId: "counter:abc@1000",
                        siteTimeserials: ["aaa": "t:1"],
                        counter: WireObjectsCounter(count: NSNumber(value: 0)),
                        createOp: StandardTestPool.counterCreateOp(objectId: "counter:abc@1000", count: 20),
                    ),
                ],
                protocolMessageChannelSerial: "sync2:",
            )
        }

        let pool = realtimeObjects.testsOnly_objectsPool
        #expect(pool.root.parentReferences == [:])
        #expect(pool.entries["map:wrapper@1000"]?.mapValue?.parentReferences == ["root": ["wrapper"]])
        #expect(pool.entries["counter:abc@1000"]?.counterValue?.parentReferences == ["map:wrapper@1000": ["moved_counter"]])
    }

    // UTS: objects/unit/RTO5c10/empty-sync-parent-refs-0
    @Test
    func test_RTO5c10_empty_sync_leaves_root_with_empty_parentReferences() {
        let realtimeObjects = makeRealtimeObjects()
        onQueue {
            realtimeObjects.nosync_onChannelAttached(hasObjects: true)
            realtimeObjects.nosync_handleObjectSyncProtocolMessage(
                objectMessages: [
                    StandardTestPool.objectStateMessage(
                        objectId: "root",
                        siteTimeserials: ["aaa": "t:0"],
                        map: StandardTestPool.objectsMap(
                            semantics: .lww,
                            entries: StandardTestPool.mapEntries(["child": StandardTestPool.data(objectId: "counter:child@1000")]),
                        ),
                        createOp: StandardTestPool.mapCreateOp(objectId: "root"),
                    ),
                    StandardTestPool.objectStateMessage(
                        objectId: "counter:child@1000",
                        siteTimeserials: ["aaa": "t:0"],
                        counter: WireObjectsCounter(count: NSNumber(value: 0)),
                        createOp: StandardTestPool.counterCreateOp(objectId: "counter:child@1000", count: 1),
                    ),
                ],
                protocolMessageChannelSerial: "sync1:",
            )
        }
        #expect(realtimeObjects.testsOnly_objectsPool.entries["counter:child@1000"]?.counterValue?.parentReferences == ["root": ["child"]])

        onQueue { realtimeObjects.nosync_onChannelAttached(hasObjects: false) }

        let pool = realtimeObjects.testsOnly_objectsPool
        #expect(pool.entries["counter:child@1000"] == nil)
        #expect(pool.entries["root"] != nil)
        #expect(pool.root.testsOnly_data.isEmpty)
        #expect(pool.root.parentReferences == [:])
    }
}
