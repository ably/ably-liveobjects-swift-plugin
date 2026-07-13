import Ably
import Foundation
import Testing
@testable import AblyLiveObjects

/// PathObject write operations (`RTPO15`–`RTPO18`, `RTPO3c2`).
/// Derived from https://github.com/ably/specification/blob/0a531c79adfc072c6d1441591f2dd838913dfe73/uts/objects/unit/path_object_mutations.md
///
/// Same binding conventions as `PathObjectTests` (chained navigation via `asLiveMap()`, typed
/// `value()` accessors). Mutations live on the typed refinements: `set`/`remove` on
/// ``LiveMapPathObject``, `increment`/`decrement` on ``LiveCounterPathObject``.
@Suite(.serialized)
final class PathObjectMutationsTests: UTSTestCase {
    // MARK: - RTPO15 — set

    // UTS: objects/unit/RTPO15/set-delegates-to-map-0
    @Test
    func test_RTPO15_set_delegates_to_map() async throws {
        let (_, _, root, _) = try await setupSyncedChannel("test")

        try await root.set(key: "name", value: "Bob")
        #expect(try root.get(key: "name").asPrimitive().stringValue == "Bob")
    }

    // UTS: objects/unit/RTPO15/set-nested-path-0
    @Test
    func test_RTPO15_set_on_nested_path() async throws {
        let (_, _, root, _) = try await setupSyncedChannel("test")

        try await root.get(key: "profile").asLiveMap().set(key: "email", value: "bob@example.com")
        #expect(try root.get(key: "profile").asLiveMap().get(key: "email").asPrimitive().stringValue == "bob@example.com")
    }

    // UTS: objects/unit/RTPO15d/set-non-map-throws-0
    @Test
    func test_RTPO15d_set_on_non_map_throws_92007() async throws {
        let (_, _, root, _) = try await setupSyncedChannel("test")
        // "score" is a counter, not a map (RTPO15e).
        await expectError(code: 92007) {
            try await root.get(key: "score").asLiveMap().set(key: "key", value: "value")
        }
    }

    // MARK: - RTPO16 — remove

    // UTS: objects/unit/RTPO16/remove-delegates-to-map-0
    @Test
    func test_RTPO16_remove_delegates_to_map() async throws {
        let (_, _, root, _) = try await setupSyncedChannel("test")

        try await root.remove(key: "name")
        #expect(try root.get(key: "name").asPrimitive().value() == nil)
    }

    // UTS: objects/unit/RTPO16d/remove-non-map-throws-0
    @Test
    func test_RTPO16d_remove_on_non_map_throws_92007() async throws {
        let (_, _, root, _) = try await setupSyncedChannel("test")
        await expectError(code: 92007) {
            try await root.get(key: "score").asLiveMap().remove(key: "key")
        }
    }

    // MARK: - RTPO17 — increment

    // UTS: objects/unit/RTPO17/increment-delegates-to-counter-0
    @Test
    func test_RTPO17_increment_delegates_to_counter() async throws {
        let (_, _, root, _) = try await setupSyncedChannel("test")

        try await root.get(key: "score").asLiveCounter().increment(amount: 25)
        #expect(try root.get(key: "score").asLiveCounter().value() == 125)
    }

    // UTS: objects/unit/RTPO17/increment-default-amount-0
    @Test
    func test_RTPO17_increment_defaults_to_1() async throws {
        let (_, _, root, _) = try await setupSyncedChannel("test")

        try await root.get(key: "score").asLiveCounter().increment() // RTPO17a1: defaults to 1
        #expect(try root.get(key: "score").asLiveCounter().value() == 101)
    }

    // UTS: objects/unit/RTPO17d/increment-non-counter-throws-0
    @Test
    func test_RTPO17d_increment_on_non_counter_throws_92007() async throws {
        let (_, _, root, _) = try await setupSyncedChannel("test")
        // root is a map, not a counter (RTPO17e).
        await expectError(code: 92007) {
            try await root.asLiveCounter().increment(amount: 5)
        }
    }

    // MARK: - RTPO18 — decrement

    // UTS: objects/unit/RTPO18/decrement-delegates-to-counter-0
    @Test
    func test_RTPO18_decrement_delegates_to_counter() async throws {
        let (_, _, root, _) = try await setupSyncedChannel("test")

        try await root.get(key: "score").asLiveCounter().decrement(amount: 10)
        #expect(try root.get(key: "score").asLiveCounter().value() == 90)
    }

    // UTS: objects/unit/RTPO18/decrement-default-amount-0
    @Test
    func test_RTPO18_decrement_defaults_to_1() async throws {
        let (_, _, root, _) = try await setupSyncedChannel("test")

        try await root.get(key: "score").asLiveCounter().decrement() // RTPO18a1: defaults to 1
        #expect(try root.get(key: "score").asLiveCounter().value() == 99)
    }

    // UTS: objects/unit/RTPO18d/decrement-non-counter-throws-0
    @Test
    func test_RTPO18d_decrement_on_non_counter_throws_92007() async throws {
        let (_, _, root, _) = try await setupSyncedChannel("test")
        await expectError(code: 92007) {
            try await root.asLiveCounter().decrement(amount: 5)
        }
    }

    // MARK: - RTPO3c2 — write on unresolvable path

    // UTS: objects/unit/RTPO3c2/set-unresolvable-throws-0
    @Test
    func test_RTPO3c2_set_on_unresolvable_path_throws_92005() async throws {
        let (_, _, root, _) = try await setupSyncedChannel("test")
        await expectError(code: 92005, statusCode: 400) {
            try await root.get(key: "nonexistent").asLiveMap().get(key: "deep").asLiveMap().set(key: "key", value: "value")
        }
    }

    // UTS: objects/unit/RTPO3c2/increment-unresolvable-throws-0
    @Test
    func test_RTPO3c2_increment_on_unresolvable_path_throws_92005() async throws {
        let (_, _, root, _) = try await setupSyncedChannel("test")
        await expectError(code: 92005, statusCode: 400) {
            try await root.get(key: "nonexistent").asLiveCounter().increment(amount: 5)
        }
    }
}

private extension PathObjectMutationsTests {
    /// Asserts `operation` throws an `ARTErrorInfo` with the given `code` (and optional `statusCode`)
    /// — the UTS `AWAIT op FAILS WITH error` / `ASSERT error.code == …` pattern.
    func expectError(code: Int, statusCode: Int? = nil, sourceLocation: SourceLocation = #_sourceLocation, _ operation: () async throws -> Void) async {
        do {
            try await operation()
            Issue.record("expected operation to throw ARTErrorInfo with code \(code)", sourceLocation: sourceLocation)
        } catch let error as ARTErrorInfo {
            #expect(error.code == code, sourceLocation: sourceLocation)
            if let statusCode {
                #expect(error.statusCode == statusCode, sourceLocation: sourceLocation)
            }
        } catch {
            Issue.record("expected ARTErrorInfo, got \(error)", sourceLocation: sourceLocation)
        }
    }
}
