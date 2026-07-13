import Ably
import Foundation
import Testing
@testable import AblyLiveObjects

/// Construction of the user-facing `ObjectMessage` / `ObjectOperation` from their internal
/// (`ProtocolTypes`) counterparts (`PAOM3`, `PAOOP3`).
/// Derived from https://github.com/ably/specification/blob/0a531c79adfc072c6d1441591f2dd838913dfe73/uts/objects/unit/public_object_message.md
///
/// The spec's `PublicObjectMessage.fromObjectMessage(source, channel)` /
/// `PublicObjectOperation.fromObjectOperation(op)` map to
/// ``ObjectMessage/fromInternalObjectMessage(_:channelName:)`` / ``ObjectOperation/fromInternalObjectOperation(_:)``
/// (the SDK's public value types are named `ObjectMessage` / `ObjectOperation`; the `channel` object
/// is represented by its name). The conversion is a skeleton in this target, so every case traps via
/// `notImplemented()` at runtime; the goal here is a faithful translation that compiles and will pass
/// once the conversion is implemented.
@Suite(.serialized)
struct PublicObjectMessageTests {
    // MARK: - PAOM3 — ObjectMessage construction

    // UTS: objects/unit/PAOM3/construction-all-fields-0
    @Test
    func test_PAOM3_construction_copies_all_fields() {
        let source = ProtocolTypes.InboundObjectMessage(
            id: "msg-id-1",
            clientId: "client-1",
            connectionId: "conn-1",
            extras: ["key": "value"],
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            operation: ProtocolTypes.ObjectOperation(
                action: .known(.mapSet),
                objectId: "map:abc@1000",
                mapSet: ProtocolTypes.MapSet(key: "name", value: StandardTestPool.data(string: "Alice")),
            ),
            serial: "01",
            siteCode: "site1",
            serialTimestamp: Date(timeIntervalSince1970: 1_700_000_001),
        )

        let publicMsg = ObjectMessage.fromInternalObjectMessage(source, channelName: "test-channel")

        #expect(publicMsg.id == "msg-id-1")
        #expect(publicMsg.clientId == "client-1")
        #expect(publicMsg.connectionId == "conn-1")
        #expect(publicMsg.timestamp == Date(timeIntervalSince1970: 1_700_000_000))
        #expect(publicMsg.channel == "test-channel")
        #expect(publicMsg.serial == "01")
        #expect(publicMsg.serialTimestamp == Date(timeIntervalSince1970: 1_700_000_001))
        #expect(publicMsg.siteCode == "site1")
        #expect(publicMsg.extras == ["key": "value"])
        #expect(publicMsg.operation.action == .mapSet)
        #expect(publicMsg.operation.objectId == "map:abc@1000")
        #expect(publicMsg.operation.mapSet?.key == "name")
    }

    // UTS: objects/unit/PAOM3/construction-optional-fields-missing-0
    @Test
    func test_PAOM3_construction_with_optional_fields_missing() {
        let source = ProtocolTypes.InboundObjectMessage(
            operation: ProtocolTypes.ObjectOperation(
                action: .known(.counterInc),
                objectId: "counter:abc@1000",
                counterInc: WireCounterInc(number: NSNumber(value: 5)),
            ),
        )

        let publicMsg = ObjectMessage.fromInternalObjectMessage(source, channelName: "my-channel")

        #expect(publicMsg.id == nil)
        #expect(publicMsg.clientId == nil)
        #expect(publicMsg.connectionId == nil)
        #expect(publicMsg.timestamp == nil)
        #expect(publicMsg.channel == "my-channel")
        #expect(publicMsg.serial == nil)
        #expect(publicMsg.serialTimestamp == nil)
        #expect(publicMsg.siteCode == nil)
        #expect(publicMsg.extras == nil)
        #expect(publicMsg.operation.action == .counterInc)
    }

    // UTS: objects/unit/PAOM3/channel-from-channel-name-0
    @Test
    func test_PAOM3_channel_is_set_from_channel_name() {
        let source = ProtocolTypes.InboundObjectMessage(
            operation: ProtocolTypes.ObjectOperation(action: .known(.objectDelete), objectId: "counter:abc@1000", objectDelete: WireObjectDelete()),
        )

        let publicMsg = ObjectMessage.fromInternalObjectMessage(source, channelName: "different-channel-name")

        #expect(publicMsg.channel == "different-channel-name")
    }

    // MARK: - PAOOP3 — ObjectOperation construction (direct copies)

    // UTS: objects/unit/PAOOP3/map-set-copies-fields-0
    @Test
    func test_PAOOP3_map_set_copies_fields_omits_others() {
        let source = ProtocolTypes.ObjectOperation(
            action: .known(.mapSet),
            objectId: "map:abc@1000",
            mapSet: ProtocolTypes.MapSet(key: "color", value: StandardTestPool.data(string: "blue")),
        )

        let publicOp = ObjectOperation.fromInternalObjectOperation(source)

        #expect(publicOp.action == .mapSet)
        #expect(publicOp.objectId == "map:abc@1000")
        #expect(publicOp.mapSet?.key == "color")
        #expect(publicOp.mapSet?.value.string == "blue")
        #expect(publicOp.mapCreate == nil)
        #expect(publicOp.mapRemove == nil)
        #expect(publicOp.counterCreate == nil)
        #expect(publicOp.counterInc == nil)
        #expect(publicOp.objectDelete == nil)
        #expect(publicOp.mapClear == nil)
    }

    // UTS: objects/unit/PAOOP3/map-remove-copies-fields-0
    @Test
    func test_PAOOP3_map_remove_copies_fields_omits_others() {
        let source = ProtocolTypes.ObjectOperation(
            action: .known(.mapRemove),
            objectId: "map:abc@1000",
            mapRemove: WireMapRemove(key: "old-key"),
        )

        let publicOp = ObjectOperation.fromInternalObjectOperation(source)

        #expect(publicOp.action == .mapRemove)
        #expect(publicOp.objectId == "map:abc@1000")
        #expect(publicOp.mapRemove?.key == "old-key")
        #expect(publicOp.mapCreate == nil)
        #expect(publicOp.mapSet == nil)
        #expect(publicOp.counterCreate == nil)
        #expect(publicOp.counterInc == nil)
        #expect(publicOp.objectDelete == nil)
        #expect(publicOp.mapClear == nil)
    }

    // UTS: objects/unit/PAOOP3/counter-inc-copies-fields-0
    @Test
    func test_PAOOP3_counter_inc_copies_fields_omits_others() {
        let source = ProtocolTypes.ObjectOperation(
            action: .known(.counterInc),
            objectId: "counter:abc@1000",
            counterInc: WireCounterInc(number: NSNumber(value: 42)),
        )

        let publicOp = ObjectOperation.fromInternalObjectOperation(source)

        #expect(publicOp.action == .counterInc)
        #expect(publicOp.objectId == "counter:abc@1000")
        #expect(publicOp.counterInc?.number == 42)
        #expect(publicOp.mapCreate == nil)
        #expect(publicOp.mapSet == nil)
        #expect(publicOp.mapRemove == nil)
        #expect(publicOp.counterCreate == nil)
        #expect(publicOp.objectDelete == nil)
        #expect(publicOp.mapClear == nil)
    }

    // UTS: objects/unit/PAOOP3/object-delete-copies-fields-0
    @Test
    func test_PAOOP3_object_delete_copies_fields_omits_others() {
        let source = ProtocolTypes.ObjectOperation(
            action: .known(.objectDelete),
            objectId: "counter:abc@1000",
            objectDelete: WireObjectDelete(),
        )

        let publicOp = ObjectOperation.fromInternalObjectOperation(source)

        #expect(publicOp.action == .objectDelete)
        #expect(publicOp.objectId == "counter:abc@1000")
        #expect(publicOp.objectDelete != nil)
        #expect(publicOp.mapCreate == nil)
        #expect(publicOp.mapSet == nil)
        #expect(publicOp.mapRemove == nil)
        #expect(publicOp.counterCreate == nil)
        #expect(publicOp.counterInc == nil)
        #expect(publicOp.mapClear == nil)
    }

    // UTS: objects/unit/PAOOP3/map-clear-copies-fields-0
    @Test
    func test_PAOOP3_map_clear_copies_fields_omits_others() {
        let source = ProtocolTypes.ObjectOperation(
            action: .known(.mapClear),
            objectId: "map:abc@1000",
            mapClear: WireMapClear(),
        )

        let publicOp = ObjectOperation.fromInternalObjectOperation(source)

        #expect(publicOp.action == .mapClear)
        #expect(publicOp.objectId == "map:abc@1000")
        #expect(publicOp.mapClear != nil)
        #expect(publicOp.mapCreate == nil)
        #expect(publicOp.mapSet == nil)
        #expect(publicOp.mapRemove == nil)
        #expect(publicOp.counterCreate == nil)
        #expect(publicOp.counterInc == nil)
        #expect(publicOp.objectDelete == nil)
    }

    // MARK: - PAOOP3b / PAOOP3c — create-payload resolution

    // UTS: objects/unit/PAOOP3/map-create-direct-0
    @Test
    func test_PAOOP3b1_map_create_direct() {
        let source = ProtocolTypes.ObjectOperation(
            action: .known(.mapCreate),
            objectId: "map:new@2000",
            mapCreate: ProtocolTypes.MapCreate(
                semantics: .known(.lww),
                entries: ["key1": ProtocolTypes.ObjectsMapEntry(data: StandardTestPool.data(string: "val1"))],
            ),
        )

        let publicOp = ObjectOperation.fromInternalObjectOperation(source)

        #expect(publicOp.action == .mapCreate)
        #expect(publicOp.objectId == "map:new@2000")
        #expect(publicOp.mapCreate?.semantics == .lww)
        #expect(publicOp.mapCreate?.entries["key1"]?.data?.string == "val1")
        #expect(publicOp.counterCreate == nil)
    }

    // UTS: objects/unit/PAOOP3/map-create-from-with-object-id-0
    @Test
    func test_PAOOP3b2_map_create_resolved_from_withObjectId() {
        let source = ProtocolTypes.ObjectOperation(
            action: .known(.mapCreate),
            objectId: "map:derived@3000",
            mapCreateWithObjectId: ProtocolTypes.MapCreateWithObjectId(
                initialValue: #"{"map":{"semantics":0,"entries":{}}}"#,
                nonce: "nonce-1",
                derivedFrom: ProtocolTypes.MapCreate(
                    semantics: .known(.lww),
                    entries: ["x": ProtocolTypes.ObjectsMapEntry(data: StandardTestPool.data(number: 10))],
                ),
            ),
        )

        let publicOp = ObjectOperation.fromInternalObjectOperation(source)

        #expect(publicOp.action == .mapCreate)
        #expect(publicOp.objectId == "map:derived@3000")
        #expect(publicOp.mapCreate?.semantics == .lww)
        #expect(publicOp.mapCreate?.entries["x"]?.data?.number == 10)
        #expect(publicOp.counterCreate == nil)
    }

    // UTS: objects/unit/PAOOP3/counter-create-from-with-object-id-0
    @Test
    func test_PAOOP3c2_counter_create_resolved_from_withObjectId() {
        let source = ProtocolTypes.ObjectOperation(
            action: .known(.counterCreate),
            objectId: "counter:derived@3000",
            counterCreateWithObjectId: ProtocolTypes.CounterCreateWithObjectId(
                initialValue: #"{"counter":{"count":100}}"#,
                nonce: "nonce-2",
                derivedFrom: WireCounterCreate(count: NSNumber(value: 100)),
            ),
        )

        let publicOp = ObjectOperation.fromInternalObjectOperation(source)

        #expect(publicOp.action == .counterCreate)
        #expect(publicOp.objectId == "counter:derived@3000")
        #expect(publicOp.counterCreate?.count == 100)
        #expect(publicOp.mapCreate == nil)
    }

    // UTS: objects/unit/PAOOP3/create-payloads-omitted-0
    @Test
    func test_PAOOP3b3_c3_create_payloads_omitted_when_absent() {
        let source = ProtocolTypes.ObjectOperation(
            action: .known(.mapSet),
            objectId: "map:abc@1000",
            mapSet: ProtocolTypes.MapSet(key: "k", value: StandardTestPool.data(string: "v")),
        )

        let publicOp = ObjectOperation.fromInternalObjectOperation(source)

        #expect(publicOp.mapCreate == nil)
        #expect(publicOp.counterCreate == nil)
    }

    // UTS: objects/unit/PAOOP3/only-relevant-field-per-action-0
    @Test
    func test_PAOOP3_only_relevant_field_present_per_action() {
        let source = ProtocolTypes.ObjectOperation(
            action: .known(.counterCreate),
            objectId: "counter:new@2000",
            counterCreate: WireCounterCreate(count: NSNumber(value: 50)),
        )

        let publicOp = ObjectOperation.fromInternalObjectOperation(source)

        #expect(publicOp.action == .counterCreate)
        #expect(publicOp.objectId == "counter:new@2000")
        #expect(publicOp.counterCreate?.count == 50)
        #expect(publicOp.mapCreate == nil)
        #expect(publicOp.mapSet == nil)
        #expect(publicOp.mapRemove == nil)
        #expect(publicOp.counterInc == nil)
        #expect(publicOp.objectDelete == nil)
        #expect(publicOp.mapClear == nil)
    }
}
