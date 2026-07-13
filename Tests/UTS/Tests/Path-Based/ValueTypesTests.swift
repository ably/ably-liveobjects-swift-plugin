import Ably
import Foundation
import Testing
@testable import AblyLiveObjects

/// Value Types (`RTLCV1`–`RTLCV4`, `RTLMV1`–`RTLMV4`).
/// Derived from https://github.com/ably/specification/blob/0a531c79adfc072c6d1441591f2dd838913dfe73/uts/objects/unit/value_types.md
///
/// `LiveCounter` / `LiveMap` are immutable blueprints from the static `create()` factories. The
/// spec's `evaluate(vt)` has no public counterpart; consumption happens inside `set()`, so — as in
/// the ably-js translation — evaluation is exercised by publishing via `set()` and inspecting the
/// generated `OBJECT` wire operations (decoded into the internal ``WireObjectOperation``, which
/// retains the outbound-only `*WithObjectId` fields). The `create()`/`count`/`entries` assertions
/// use `@testable` internal access.
@Suite(.serialized)
final class ValueTypesTests: UTSTestCase {
    // MARK: - RTLCV3 — LiveCounter.create

    // UTS: objects/unit/RTLCV3/create-with-count-0
    @Test
    func test_RTLCV3_LiveCounter_create_with_initial_count() throws {
        let vt = LiveCounter.create(initialCount: 42)

        // RTLCV3b: returns a LiveCounter with the internal count.
        #expect(vt.count == 42)
        // RTLCV3d: the returned value is immutable (a Swift value type — immutable by construction).
    }

    // UTS: objects/unit/RTLCV3/create-default-zero-0
    @Test
    func test_RTLCV3_LiveCounter_create_defaults_to_0() throws {
        // If initialCount omitted, defaults to 0.
        let vt = LiveCounter.create()
        #expect(vt.count == 0)
    }

    // UTS: objects/unit/RTLCV3c/no-validation-at-create-0
    @Test
    func test_RTLCV3c_no_validation_at_creation_time() throws {
        // DEVIATION (RTLCV3c): spec passes a non-number (`LiveCounter.create("not_a_number")`) to show
        // creation performs no validation. Swift's `create(initialCount: Double)` rejects a String at
        // compile time, so the non-number input is not expressible. Only the (valid) construction is
        // exercised. See deviations.md.
        let vt = LiveCounter.create(initialCount: 0)
        #expect(vt.count == 0)
    }

    // MARK: - RTLCV4 — Consumption generates COUNTER_CREATE ObjectMessage

    // UTS: objects/unit/RTLCV4/evaluate-generates-message-0
    @Test
    func test_RTLCV4_consumption_generates_COUNTER_CREATE_ObjectMessage() async throws {
        let (_, _, root, ws) = try await setupSyncedChannel("test-RTLCV4-consume")

        try await root.asLiveMap().set(key: "name", value: .liveCounter(LiveCounter.create(initialCount: 42)))

        let operations = try sentObjectOperations(ws)
        let counterCreateOps = operations.filter { $0.action == .known(.counterCreate) }
        #expect(counterCreateOps.count == 1)

        let operation = try #require(counterCreateOps.first)
        #expect(operation.action == .known(.counterCreate))
        // objectId starts with "counter:" and contains "@" (RTLCV4f, RTO14).
        #expect(operation.objectId.hasPrefix("counter:"))
        #expect(operation.objectId.contains("@"))
        // counterCreateWithObjectId is set with a nonce (16+ chars) and an initialValue (RTLCV4g3/g4/d).
        let withObjectId = try #require(operation.counterCreateWithObjectId)
        #expect(withObjectId.nonce.count >= 16)
        #expect(!withObjectId.initialValue.isEmpty)
    }

    // UTS: objects/unit/RTLCV4g5/retains-local-counter-create-0
    @Test
    func test_RTLCV4g5_consumption_retains_local_CounterCreate() async throws {
        // DEVIATION (RTLCV4g5): the local CounterCreate (`derivedFrom`) is stripped from the wire
        // message, so — as in ably-js — we verify the retained count via the `initialValue` JSON
        // string in counterCreateWithObjectId, which encodes the CounterCreate payload. See deviations.md.
        let (_, _, root, ws) = try await setupSyncedChannel("test-RTLCV4g5")

        try await root.asLiveMap().set(key: "name", value: .liveCounter(LiveCounter.create(initialCount: 42)))

        let operations = try sentObjectOperations(ws)
        let operation = try #require(operations.first { $0.action == .known(.counterCreate) })
        let initialValue = try initialValueJSON(try #require(operation.counterCreateWithObjectId).initialValue)
        #expect((initialValue["count"] as? Double) == 42)
    }

    // UTS: objects/unit/RTLCV4a/evaluate-validates-count-0
    @Test
    func test_RTLCV4a_consumption_validates_count_type() throws {
        // DEVIATION (RTLCV4a): spec passes a non-number and expects evaluation to fail with 40003.
        // Swift's `create(initialCount: Double)` rejects non-numbers at compile time, so the runtime
        // 40003 assertion is not expressible. See deviations.md.
    }

    // UTS: objects/unit/RTLCV4/evaluate-zero-count-0
    @Test
    func test_RTLCV4_consumption_with_count_0_is_valid() async throws {
        let (_, _, root, ws) = try await setupSyncedChannel("test-RTLCV4-zero")

        try await root.asLiveMap().set(key: "name", value: .liveCounter(LiveCounter.create(initialCount: 0)))

        let operations = try sentObjectOperations(ws)
        let operation = try #require(operations.first { $0.action == .known(.counterCreate) })
        let initialValue = try initialValueJSON(try #require(operation.counterCreateWithObjectId).initialValue)
        #expect((initialValue["count"] as? Double) == 0)
    }

    // MARK: - RTLMV3 — LiveMap.create

    // UTS: objects/unit/RTLMV3/create-with-entries-0
    @Test
    func test_RTLMV3_LiveMap_create_with_entries() throws {
        let vt = LiveMap.create(entries: [
            "name": "Alice",
            "age": 30,
        ])

        // RTLMV3b: returns a LiveMap with internal entries.
        #expect(vt.entries?["name"]?.stringValue == "Alice")
        #expect(vt.entries?["age"]?.numberValue == 30)
        // RTLMV3d: the returned value is immutable (a Swift value type — immutable by construction).
    }

    // UTS: objects/unit/RTLMV3/create-no-entries-0
    @Test
    func test_RTLMV3_LiveMap_create_with_no_entries() throws {
        // If entries omitted, internal entries is nil.
        let vt = LiveMap.create()
        #expect(vt.entries == nil)
    }

    // MARK: - RTLMV4 — Consumption generates MAP_CREATE ObjectMessage

    // UTS: objects/unit/RTLMV4/evaluate-generates-message-0
    @Test
    func test_RTLMV4_consumption_generates_MAP_CREATE_ObjectMessage() async throws {
        let (_, _, root, ws) = try await setupSyncedChannel("test-RTLMV4-consume")

        try await root.asLiveMap().set(key: "name", value: .liveMap(LiveMap.create(entries: ["name": "Alice"])))

        let operations = try sentObjectOperations(ws)
        let mapCreateOps = operations.filter { $0.action == .known(.mapCreate) }
        #expect(mapCreateOps.count == 1)

        let operation = try #require(mapCreateOps.first)
        #expect(operation.action == .known(.mapCreate))
        #expect(operation.objectId.hasPrefix("map:"))
        let withObjectId = try #require(operation.mapCreateWithObjectId)
        #expect(withObjectId.nonce.count >= 16)
        #expect(!withObjectId.initialValue.isEmpty)
    }

    // UTS: objects/unit/RTLMV4j5/retains-local-map-create-0
    @Test
    func test_RTLMV4j5_consumption_retains_local_MapCreate() async throws {
        // DEVIATION (RTLMV4j5): the local MapCreate is stripped from the wire message, so — as in
        // ably-js — we verify it via the `initialValue` JSON string in mapCreateWithObjectId. See deviations.md.
        let (_, _, root, ws) = try await setupSyncedChannel("test-RTLMV4j5")

        try await root.asLiveMap().set(key: "name", value: .liveMap(LiveMap.create(entries: ["name": "Alice"])))

        let operations = try sentObjectOperations(ws)
        let operation = try #require(operations.first { $0.action == .known(.mapCreate) })
        let initialValue = try initialValueJSON(try #require(operation.mapCreateWithObjectId).initialValue)
        #expect((initialValue["semantics"] as? Int) == WireMapSemantics.lww)
        let entries = try #require(initialValue["entries"] as? [String: Any])
        let nameData = try #require((entries["name"] as? [String: Any])?["data"] as? [String: Any])
        #expect((nameData["string"] as? String) == "Alice")
    }

    // UTS: objects/unit/RTLMV4d/entry-value-types-0
    @Test
    func test_RTLMV4d_entry_value_type_mapping() async throws {
        let (_, _, root, ws) = try await setupSyncedChannel("test-RTLMV4d")

        try await root.asLiveMap().set(key: "name", value: .liveMap(LiveMap.create(entries: [
            "str": "hello",
            "num": 42,
            "bool": true,
            "json_arr": [1, 2, 3],
            "json_obj": ["key": "value"],
        ])))

        let operations = try sentObjectOperations(ws)
        let operation = try #require(operations.first { $0.action == .known(.mapCreate) })
        let initialValue = try initialValueJSON(try #require(operation.mapCreateWithObjectId).initialValue)
        let entries = try #require(initialValue["entries"] as? [String: Any])

        func data(_ key: String) throws -> [String: Any] {
            try #require((entries[key] as? [String: Any])?["data"] as? [String: Any])
        }
        #expect((try data("str")["string"] as? String) == "hello") // RTLMV4d4
        #expect((try data("num")["number"] as? Double) == 42) // RTLMV4d5
        #expect((try data("bool")["boolean"] as? Bool) == true) // RTLMV4d6
        // JSON values on the wire are JSON-stringified strings (RTLMV4d3).
        let jsonArr = try JSONSerialization.jsonObject(with: Data((try data("json_arr")["json"] as? String ?? "").utf8)) as? [Any]
        #expect(jsonArr?.count == 3)
        let jsonObj = try JSONSerialization.jsonObject(with: Data((try data("json_obj")["json"] as? String ?? "").utf8)) as? [String: Any]
        #expect((jsonObj?["key"] as? String) == "value")
    }

    // UTS: objects/unit/RTLMV4d1/nested-value-types-0
    @Test
    func test_RTLMV4d1_nested_value_types_produce_depth_first_ObjectMessages() async throws {
        let (_, _, root, ws) = try await setupSyncedChannel("test-RTLMV4d1")

        let innerCounter = LiveCounter.create(initialCount: 10)
        let innerMap = LiveMap.create(entries: ["nested_count": .liveCounter(innerCounter)])
        let outer = LiveMap.create(entries: ["child": .liveMap(innerMap)])

        try await root.asLiveMap().set(key: "name", value: .liveMap(outer))

        let operations = try sentObjectOperations(ws)
        // Only the CREATE operations (there is also a MAP_SET linking `name`).
        let createOps = operations.filter { $0.action == .known(.counterCreate) || $0.action == .known(.mapCreate) }
        // Depth-first: inner counter, inner map, outer map (RTLMV4k).
        #expect(createOps.count == 3)
        #expect(createOps[0].action == .known(.counterCreate))
        #expect(createOps[0].objectId.hasPrefix("counter:"))
        #expect(createOps[1].action == .known(.mapCreate))
        #expect(createOps[1].objectId.hasPrefix("map:"))
        #expect(createOps[2].action == .known(.mapCreate))
        #expect(createOps[2].objectId.hasPrefix("map:"))

        let innerCounterId = createOps[0].objectId
        let innerMapId = createOps[1].objectId

        // Inner map's entries reference the inner counter; outer map's entries reference the inner map.
        func initialValueEntries(_ operation: WireObjectOperation) throws -> [String: Any] {
            let json = try initialValueJSON(try #require(operation.mapCreateWithObjectId).initialValue)
            return try #require(json["entries"] as? [String: Any])
        }
        let innerMapEntries = try initialValueEntries(createOps[1])
        let nestedCountData = try #require((innerMapEntries["nested_count"] as? [String: Any])?["data"] as? [String: Any])
        #expect((nestedCountData["objectId"] as? String) == innerCounterId)

        let outerMapEntries = try initialValueEntries(createOps[2])
        let childData = try #require((outerMapEntries["child"] as? [String: Any])?["data"] as? [String: Any])
        #expect((childData["objectId"] as? String) == innerMapId)
    }

    // UTS: objects/unit/RTLMV4a/evaluate-validates-entries-0
    @Test
    func test_RTLMV4a_consumption_validates_entries_type() throws {
        // DEVIATION (RTLMV4a): spec passes `LiveMap.create(null)` expecting 40003. Swift's
        // `create(entries: [String: LiveMapValue])` rejects null at compile time. Not expressible. See deviations.md.
    }

    // UTS: objects/unit/RTLMV4b/evaluate-validates-keys-0
    @Test
    func test_RTLMV4b_consumption_validates_key_types() throws {
        // DEVIATION (RTLMV4b): spec passes a non-String key (`{ 123: "value" }`) expecting 40003.
        // Swift dictionary keys are typed `String`; a non-String key cannot be constructed. Not
        // expressible. See deviations.md.
    }

    // UTS: objects/unit/RTLMV4c/evaluate-validates-values-0
    @Test
    func test_RTLMV4c_consumption_validates_value_types() throws {
        // DEVIATION (RTLMV4c): spec passes an unsupported value (a function) expecting 40013. Swift's
        // `LiveMapValue` union only constructs from supported types, so an unsupported value is
        // rejected at compile time. Not expressible. See deviations.md.
    }

    // UTS: objects/unit/RTLMV4e2/empty-entries-0
    @Test
    func test_RTLMV4e2_empty_entries_produces_MapCreate_with_empty_entries() async throws {
        let (_, _, root, ws) = try await setupSyncedChannel("test-RTLMV4e2")

        try await root.asLiveMap().set(key: "name", value: .liveMap(LiveMap.create()))

        let operations = try sentObjectOperations(ws)
        let operation = try #require(operations.first { $0.action == .known(.mapCreate) })
        let initialValue = try initialValueJSON(try #require(operation.mapCreateWithObjectId).initialValue)
        let entries = try #require(initialValue["entries"] as? [String: Any])
        #expect(entries.isEmpty)
    }

    // UTS: objects/unit/RTLMV4d/map-set-all-types-table-0
    @Test
    func test_RTLMV4d_table_driven_value_type_mapping() async throws {
        // Table-driven (like ably-js's `scenarios` loop): every supported value type maps to the
        // correct `data.*` field on the generated MapCreate entry.
        let scenarios: [(input: LiveMapValue, field: String)] = [
            ("hello", "string"),
            (42, "number"),
            (3.14, "number"),
            (0, "number"),
            (-1, "number"),
            (true, "boolean"),
            (false, "boolean"),
            ([1, "a"], "json"),
            (["k": "v"], "json"),
            (.primitive(.data(Data([1, 2, 3]))), "bytes"),
        ]

        for (index, scenario) in scenarios.enumerated() {
            let (_, _, root, ws) = try await setupSyncedChannel("test-RTLMV4d-table-\(index)")
            try await root.asLiveMap().set(key: "test_key", value: .liveMap(LiveMap.create(entries: ["test_key": scenario.input])))

            let operations = try sentObjectOperations(ws)
            let operation = try #require(operations.first { $0.action == .known(.mapCreate) })
            let initialValue = try initialValueJSON(try #require(operation.mapCreateWithObjectId).initialValue)
            let entries = try #require(initialValue["entries"] as? [String: Any])
            let data = try #require((entries["test_key"] as? [String: Any])?["data"] as? [String: Any])
            #expect(data[scenario.field] != nil, "expected \(scenario.field) field for scenario \(index)")
        }
    }
}

private extension ValueTypesTests {
    /// Parses the `initialValue` JSON string (the wire encoding of a `CounterCreate` / `MapCreate`).
    func initialValueJSON(_ initialValue: String, sourceLocation: SourceLocation = #_sourceLocation) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: Data(initialValue.utf8)) as? [String: Any], sourceLocation: sourceLocation)
    }
}
