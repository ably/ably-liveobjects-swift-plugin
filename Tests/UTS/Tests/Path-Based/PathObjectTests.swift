import Ably
import Foundation
import Testing
@testable import AblyLiveObjects

/// PathObject read operations (`RTPO1`–`RTPO14`).
/// Derived from https://github.com/ably/specification/blob/0a531c79adfc072c6d1441591f2dd838913dfe73/uts/objects/unit/path_object.md
///
/// Binding conventions (the spec's loosely-typed API maps onto Swift's type-refined one):
/// - Chained navigation: the spec's `root.get("a").get("b")` becomes
///   `root.get(key: "a").asLiveMap().get(key: "b")` (`get`/`at` live on `LiveMapPathObject`, and
///   return the loosely-typed `any PathObject`).
/// - `value()`: the spec's single `value()` maps to the type-refined accessor —
///   `asLiveCounter().value()` (`Double?`) for counters and `asPrimitive().value()` (`Primitive?`)
///   for primitives; a map / unresolvable path yields `nil` from `asPrimitive().value()`.
/// - `path` is a property (per review), not `path()`.
@Suite(.serialized)
final class PathObjectTests: UTSTestCase {
    // MARK: - RTPO4 — path

    // UTS: objects/unit/RTPO4/path-string-representation-0
    @Test
    func test_RTPO4_path_returns_dot_delimited_string() async throws {
        let (_, _, root, _) = try await setupSyncedChannel("test")

        #expect(root.path == "") // RTPO4c: empty path (root)
        #expect(root.get(key: "profile").path == "profile")
        #expect(root.get(key: "profile").asLiveMap().get(key: "email").path == "profile.email")
    }

    // UTS: objects/unit/RTPO4b/path-escapes-dots-0
    @Test
    func test_RTPO4b_path_escapes_dots_in_segments() async throws {
        let (_, _, root, _) = try await setupSyncedChannel("test")

        // Dots within a segment are escaped with a backslash.
        let po = root.get(key: "a.b").asLiveMap().get(key: "c")
        #expect(po.path == #"a\.b.c"#)
    }

    // MARK: - RTPO5 — get

    // UTS: objects/unit/RTPO5/get-appends-key-0
    @Test
    func test_RTPO5_get_returns_new_PathObject_with_appended_key() async throws {
        let (_, _, root, _) = try await setupSyncedChannel("test")

        let child = root.get(key: "profile")
        let grandchild = child.asLiveMap().get(key: "email")
        #expect(child.path == "profile")
        #expect(grandchild.path == "profile.email")
        // RTPO5d: purely navigational (child is a distinct object from root).
    }

    // UTS: objects/unit/RTPO5b/get-non-string-throws-0
    @Test
    func test_RTPO5b_get_throws_on_non_string_key() throws {
        // DEVIATION (RTPO5b): spec passes a non-String key expecting 40003. Swift's `get(key: String)`
        // rejects a non-String at compile time. Not expressible. See deviations.md.
    }

    // MARK: - RTPO6 — at

    // UTS: objects/unit/RTPO6/at-parses-path-0
    @Test
    func test_RTPO6_at_parses_dot_delimited_path() async throws {
        let (_, _, root, _) = try await setupSyncedChannel("test")

        let po = root.at(path: "profile.email")
        #expect(po.path == "profile.email")
        #expect(try po.asPrimitive().stringValue == "alice@example.com")
    }

    // UTS: objects/unit/RTPO6/at-escaped-dots-0
    @Test
    func test_RTPO6_at_respects_escaped_dots() async throws {
        let (_, _, root, _) = try await setupSyncedChannel("test")

        let po = root.at(path: #"a\.b.c"#)
        #expect(po.path == #"a\.b.c"#)
    }

    // UTS: objects/unit/RTPO6b/at-non-string-throws-0
    @Test
    func test_RTPO6b_at_throws_for_non_string_input() throws {
        // DEVIATION (RTPO6b): spec passes a non-String path expecting 40003. Swift's `at(path: String)`
        // rejects a non-String at compile time. Not expressible. See deviations.md.
    }

    // MARK: - RTPO7 — value

    // UTS: objects/unit/RTPO7/value-counter-0
    @Test
    func test_RTPO7_value_returns_counter_numeric_value() async throws {
        let (_, _, root, _) = try await setupSyncedChannel("test")
        #expect(try root.get(key: "score").asLiveCounter().value() == 100) // RTPO7c
    }

    // UTS: objects/unit/RTPO7/value-primitive-0
    @Test
    func test_RTPO7_value_returns_primitive_value() async throws {
        let (_, _, root, _) = try await setupSyncedChannel("test")
        #expect(try root.get(key: "name").asPrimitive().stringValue == "Alice") // RTPO7d
        #expect(try root.get(key: "age").asPrimitive().numberValue == 30)
        #expect(try root.get(key: "active").asPrimitive().boolValue == true)
    }

    // UTS: objects/unit/RTPO7/value-bytes-0
    @Test
    func test_RTPO7_value_returns_bytes_for_binary_entry() async throws {
        let (_, _, root, _) = try await setupSyncedChannel("test")
        #expect(try root.get(key: "avatar").asPrimitive().dataValue == Data([1, 2, 3])) // RTPO7d (binary)
    }

    // UTS: objects/unit/RTPO7d/value-livemap-null-0
    @Test
    func test_RTPO7d_value_returns_null_for_InternalLiveMap() async throws {
        let (_, _, root, _) = try await setupSyncedChannel("test")
        #expect(try root.get(key: "profile").asPrimitive().value() == nil) // RTPO7e
    }

    // UTS: objects/unit/RTPO7e/value-unresolvable-null-0
    @Test
    func test_RTPO7e_value_returns_null_on_resolution_failure() async throws {
        let (_, _, root, _) = try await setupSyncedChannel("test")
        #expect(try root.get(key: "nonexistent").asLiveMap().get(key: "deep").asPrimitive().value() == nil) // RTPO7f / RTPO3c1
    }

    // MARK: - RTPO8 — instance

    // UTS: objects/unit/RTPO8/instance-live-object-0
    @Test
    func test_RTPO8_instance_returns_Instance_for_LiveObject() async throws {
        let (_, _, root, _) = try await setupSyncedChannel("test")

        let counterInstance = try root.get(key: "score").instance()
        #expect(counterInstance?.id() == "counter:score@1000") // RTPO8c

        let mapInstance = try root.get(key: "profile").instance()
        #expect(mapInstance?.id() == "map:profile@1000")
    }

    // UTS: objects/unit/RTPO8c/instance-primitive-null-0
    @Test
    func test_RTPO8c_instance_returns_null_for_primitive() async throws {
        let (_, _, root, _) = try await setupSyncedChannel("test")
        #expect(try root.get(key: "name").instance() == nil) // RTPO8d
    }

    // MARK: - RTPO9 — entries

    // UTS: objects/unit/RTPO9/entries-yields-pairs-0
    @Test
    func test_RTPO9_entries_returns_array_of_key_pathObject_pairs() async throws {
        let (_, _, root, _) = try await setupSyncedChannel("test")

        var entries: [String: String] = [:]
        for (key, pathObject) in try root.entries() {
            entries[key] = pathObject.path
        }
        #expect(entries["name"] == "name")
        #expect(entries["profile"] == "profile")
        #expect(entries.count == 7)
    }

    // UTS: objects/unit/RTPO9d/entries-non-map-empty-0
    @Test
    func test_RTPO9d_entries_returns_empty_array_for_non_map() async throws {
        let (_, _, root, _) = try await setupSyncedChannel("test")
        #expect(try root.get(key: "score").asLiveMap().entries().isEmpty)
    }

    // MARK: - RTPO10 — keys

    // UTS: objects/unit/RTPO10/keys-returns-array-0
    @Test
    func test_RTPO10_keys_returns_array_of_key_strings() async throws {
        let (_, _, root, _) = try await setupSyncedChannel("test")

        let keys = try root.keys()
        #expect(keys.count == 7)
        #expect(keys.contains("name"))
        #expect(keys.contains("profile"))
        #expect(keys.contains("score"))
    }

    // UTS: objects/unit/RTPO10d/keys-non-map-empty-0
    @Test
    func test_RTPO10d_keys_returns_empty_array_for_non_map() async throws {
        let (_, _, root, _) = try await setupSyncedChannel("test")
        #expect(try root.get(key: "score").asLiveMap().keys().isEmpty)
    }

    // MARK: - RTPO11 — values

    // UTS: objects/unit/RTPO11/values-returns-array-0
    @Test
    func test_RTPO11_values_returns_array_of_pathObjects() async throws {
        let (_, _, root, _) = try await setupSyncedChannel("test")

        let values = try root.values()
        #expect(values.count == 7)
        let paths = Set(values.map(\.path))
        #expect(paths.contains("name"))
        #expect(paths.contains("profile"))
        #expect(paths.contains("score"))
    }

    // UTS: objects/unit/RTPO11d/values-non-map-empty-0
    @Test
    func test_RTPO11d_values_returns_empty_array_for_non_map() async throws {
        let (_, _, root, _) = try await setupSyncedChannel("test")
        #expect(try root.get(key: "score").asLiveMap().values().isEmpty)
    }

    // MARK: - RTPO12 — size

    // UTS: objects/unit/RTPO12/size-count-0
    @Test
    func test_RTPO12_size_returns_non_tombstoned_count() async throws {
        let (_, _, root, _) = try await setupSyncedChannel("test")
        #expect(try root.size() == 7)
        #expect(try root.get(key: "profile").asLiveMap().size() == 3)
    }

    // UTS: objects/unit/RTPO12c/size-non-map-null-0
    @Test
    func test_RTPO12c_size_returns_null_for_non_map() async throws {
        let (_, _, root, _) = try await setupSyncedChannel("test")
        #expect(try root.get(key: "score").asLiveMap().size() == nil)
        #expect(try root.get(key: "name").asLiveMap().size() == nil)
    }

    // MARK: - RTPO13 — compact (DEVIATION: asserted via compactJson)

    // UTS: objects/unit/RTPO13/compact-recursive-0
    @Test
    func test_RTPO13_compact_recursively_compacts_map_tree() async throws {
        // DEVIATION (RTPO13): only `compactJson()` is exposed publicly, so this asserts on the JSON
        // form (binary appears as base64, not raw bytes). See deviations.md.
        let (_, _, root, _) = try await setupSyncedChannel("test")

        let result = try root.compactJson()?.objectValue
        #expect(result?["name"]?.stringValue == "Alice") // RTPO13c4
        #expect(result?["age"]?.numberValue == 30)
        #expect(result?["active"]?.boolValue == true)
        #expect(result?["score"]?.numberValue == 100) // RTPO13c3 (counter -> number)
        #expect(result?["profile"]?.objectValue?["email"]?.stringValue == "alice@example.com") // RTPO13c2 (nested map)
        #expect(result?["profile"]?.objectValue?["nested_counter"]?.numberValue == 5)
        #expect(result?["profile"]?.objectValue?["prefs"]?.objectValue?["theme"]?.stringValue == "dark")
    }

    // UTS: objects/unit/RTPO13c/compact-counter-0
    @Test
    func test_RTPO13c_compact_returns_number_for_counter() async throws {
        // DEVIATION (RTPO13): asserted via compactJson(). See deviations.md.
        let (_, _, root, _) = try await setupSyncedChannel("test")
        #expect(try root.get(key: "score").compactJson()?.numberValue == 100) // RTPO13d
    }

    // UTS: objects/unit/RTPO14/compact-json-bytes-0
    @Test
    func test_RTPO14_compactJson_encodes_bytes_as_base64_string() async throws {
        let (_, _, root, _) = try await setupSyncedChannel("test")
        let result = try root.compactJson()?.objectValue
        #expect(result?["avatar"]?.stringValue == "AQID") // RTPO14b1 (base64 of [1,2,3])
    }

    // UTS: objects/unit/RTPO14/compact-json-0
    @Test
    func test_RTPO14_compactJson_encodes_cycles_as_objectId() async throws {
        let (_, _, root, ws) = try await setupSyncedChannel("test")

        // Introduce a cycle: prefs.back_ref -> profile.
        ws.activeConnection?.sendToClient(.object(channel: "test", state: [
            StandardTestPool.mapSet(
                objectId: "map:prefs@1000",
                key: "back_ref",
                value: StandardTestPool.data(objectId: "map:profile@1000"),
                serial: StandardTestPool.remoteSerial(0),
                siteCode: "remote",
            ),
        ]))

        let result = try root.get(key: "profile").compactJson()?.objectValue
        // RTPO14b2: cycles are encoded as { "objectId": ... }.
        let backRef = result?["prefs"]?.objectValue?["back_ref"]?.objectValue
        #expect(backRef?["objectId"]?.stringValue == "map:profile@1000")
    }

    // MARK: - RTPO3 — path resolution

    // UTS: objects/unit/RTPO3/path-resolution-walk-0
    @Test
    func test_RTPO3_path_resolution_walks_through_maps() async throws {
        let (_, _, root, _) = try await setupSyncedChannel("test")

        #expect(try root.asPrimitive().value() == nil) // RTPO3b: empty path resolves to root (a map)
        #expect(try root.get(key: "profile").asLiveMap().get(key: "prefs").asLiveMap().get(key: "theme").asPrimitive().stringValue == "dark")
    }

    // UTS: objects/unit/RTPO3a1/intermediate-not-map-0
    @Test
    func test_RTPO3a1_resolution_fails_if_intermediate_not_map() async throws {
        let (_, _, root, _) = try await setupSyncedChannel("test")
        // "score" is a counter, so navigating through it fails to resolve -> null.
        #expect(try root.get(key: "score").asLiveMap().get(key: "something").asPrimitive().value() == nil)
    }

    // UTS: objects/unit/RTPO3c1/read-null-on-failure-0
    @Test
    func test_RTPO3c1_read_operation_returns_null_on_resolution_failure() async throws {
        let (_, _, root, _) = try await setupSyncedChannel("test")
        #expect(try root.get(key: "nonexistent").asPrimitive().value() == nil)
        #expect(try root.get(key: "nonexistent").instance() == nil)
        #expect(try root.get(key: "nonexistent").asLiveMap().size() == nil)
        #expect(try root.get(key: "nonexistent").compactJson() == nil)
    }
}
