import Ably
import Foundation
import Testing
@testable import AblyLiveObjects

/// Instance — identity-bound references (`RTINS1`–`RTINS16`).
/// Derived from https://github.com/ably/specification/blob/0a531c79adfc072c6d1441591f2dd838913dfe73/uts/objects/unit/instance.md
///
/// Swift models `Instance` as an enum (`.liveMap`/`.liveCounter`/`.primitive`) whose payloads carry
/// the type-specific members (`id`, `value`, `get`, `set`, `subscribe`, …). The spec's loosely-typed
/// `instance.value()` / `instance.get()` therefore map to extracting the payload via the
/// `asLiveMap()` / `asLiveCounter()` / `asPrimitive()`.
@Suite(.serialized)
final class InstanceTests: UTSTestCase {
    // MARK: - RTINS3 — id

    // UTS: objects/unit/RTINS3/id-returns-objectid-0
    @Test
    func test_RTINS3_id_returns_objectId() async throws {
        let (_, _, root, _) = try await setupSyncedChannel("test")

        #expect(try root.get(key: "score").instance()?.id() == "counter:score@1000") // RTINS3a
        #expect(try root.get(key: "profile").instance()?.id() == "map:profile@1000")
    }

    // MARK: - RTINS4 — value

    // UTS: objects/unit/RTINS4/value-counter-0
    @Test
    func test_RTINS4_value_returns_counter_number_or_null_for_map() async throws {
        let (_, _, root, _) = try await setupSyncedChannel("test")

        #expect(try root.get(key: "score").instance()?.asLiveCounter().value == 100) // RTINS4b
        // RTINS4d: a map has no numeric value. Swift exposes no `value` on `LiveMapInstance`, so
        // "value == null" is represented as the instance being a map.
        #expect(try root.instance()?.type == .liveMap)
    }

    // MARK: - RTINS5 — get

    // UTS: objects/unit/RTINS5/get-wraps-entry-0
    @Test
    func test_RTINS5_get_returns_Instance_wrapping_entry_value() async throws {
        let (_, _, root, _) = try await setupSyncedChannel("test")
        let rootInstance = try root.instance()?.asLiveMap()

        let nameInstance = try rootInstance?.get(key: "name")
        #expect(try nameInstance?.asPrimitive().stringValue == "Alice") // RTINS5c

        let scoreInstance = try rootInstance?.get(key: "score")
        #expect(scoreInstance?.id() == "counter:score@1000")

        #expect(try rootInstance?.get(key: "nonexistent") == nil)
    }

    // MARK: - RTINS6 — entries

    // UTS: objects/unit/RTINS6/entries-yields-instances-0
    @Test
    func test_RTINS6_entries_returns_array_of_key_instance_pairs() async throws {
        let (_, _, root, _) = try await setupSyncedChannel("test")
        let rootInstance = try root.instance()?.asLiveMap()

        var entries: [String: Instance] = [:]
        for (key, instance) in try #require(try rootInstance?.entries()) {
            entries[key] = instance
        }
        #expect(entries.count == 7) // RTINS6b
        #expect(try entries["name"]?.asPrimitive().stringValue == "Alice")
    }

    // MARK: - RTINS9 — size

    // UTS: objects/unit/RTINS9/size-0
    @Test
    func test_RTINS9_size_returns_non_tombstoned_count() async throws {
        let (_, _, root, _) = try await setupSyncedChannel("test")

        #expect(try root.instance()?.asLiveMap().size == 7) // RTINS9b
        // RTINS9c: a counter has no size. Swift exposes no `size` on `LiveCounterInstance`, so
        // "size == null" is represented as the instance being a counter.
        #expect(try root.get(key: "score").instance()?.type == .liveCounter)
    }

    // MARK: - RTINS10 — compact

    // UTS: objects/unit/RTINS10/compact-0
    @Test
    func test_RTINS10_compact_recursively_compacts() async throws {
        // DEVIATION (RTINS10): only `compactJson()` is exposed publicly (not `compact()`), so this
        // asserts on the JSON form. See deviations.md.
        let (_, _, root, _) = try await setupSyncedChannel("test")

        let result = try root.instance()?.compactJson().objectValue
        #expect(result?["name"]?.stringValue == "Alice")
        #expect(result?["score"]?.numberValue == 100)
        #expect(result?["profile"]?.objectValue?["email"]?.stringValue == "alice@example.com")
    }

    // MARK: - RTINS12 — set

    // UTS: objects/unit/RTINS12/set-delegates-0
    @Test
    func test_RTINS12_set_delegates_to_map() async throws {
        let (_, _, root, _) = try await setupSyncedChannel("test")
        try await root.instance()?.asLiveMap().set(key: "name", value: "Bob")
        #expect(try root.get(key: "name").asPrimitive().stringValue == "Bob")
    }

    // UTS: objects/unit/RTINS12d/set-non-map-throws-0
    @Test
    func test_RTINS12d_set_on_non_map_throws_92007() throws {
        // DEVIATION (RTINS12d): `set` exists only on `LiveMapInstance`, so it cannot be *called* on a
        // counter payload — the "throws 92007" path is compile-time-unreachable. See deviations.md.
    }

    // MARK: - RTINS13 — remove

    // UTS: objects/unit/RTINS13/remove-delegates-0
    @Test
    func test_RTINS13_remove_delegates_to_map() async throws {
        let (_, _, root, _) = try await setupSyncedChannel("test")
        try await root.instance()?.asLiveMap().remove(key: "name")
        #expect(try root.get(key: "name").asPrimitive().value() == nil)
    }

    // MARK: - RTINS14 — increment

    // UTS: objects/unit/RTINS14/increment-delegates-0
    @Test
    func test_RTINS14_increment_delegates_to_counter() async throws {
        let (_, _, root, _) = try await setupSyncedChannel("test")
        try await root.get(key: "score").instance()?.asLiveCounter().increment(amount: 25)
        #expect(try root.get(key: "score").asLiveCounter().value() == 125)
    }

    // UTS: objects/unit/RTINS14a/increment-default-0
    @Test
    func test_RTINS14a_increment_defaults_to_1() async throws {
        let (_, _, root, _) = try await setupSyncedChannel("test")
        try await root.get(key: "score").instance()?.asLiveCounter().increment()
        #expect(try root.get(key: "score").asLiveCounter().value() == 101)
    }

    // UTS: objects/unit/RTINS14d/increment-non-counter-throws-0
    @Test
    func test_RTINS14d_increment_on_non_counter_throws_92007() throws {
        // DEVIATION (RTINS14d): `increment` exists only on `LiveCounterInstance`, so it cannot be
        // called on a map payload — the "throws 92007" path is compile-time-unreachable. See deviations.md.
    }

    // MARK: - RTINS15 — decrement

    // UTS: objects/unit/RTINS15/decrement-delegates-0
    @Test
    func test_RTINS15_decrement_delegates_to_counter() async throws {
        let (_, _, root, _) = try await setupSyncedChannel("test")
        try await root.get(key: "score").instance()?.asLiveCounter().decrement(amount: 10)
        #expect(try root.get(key: "score").asLiveCounter().value() == 90)
    }

    // UTS: objects/unit/RTINS15a/decrement-default-0
    @Test
    func test_RTINS15a_decrement_defaults_to_1() async throws {
        let (_, _, root, _) = try await setupSyncedChannel("test")
        try await root.get(key: "score").instance()?.asLiveCounter().decrement()
        #expect(try root.get(key: "score").asLiveCounter().value() == 99)
    }

    // UTS: objects/unit/RTINS15d/decrement-non-counter-throws-0 — covered by the RTINS14d deviation
    // (decrement, like increment, exists only on `LiveCounterInstance`). See deviations.md.

    // MARK: - RTINS16 — subscribe

    // UTS: objects/unit/RTINS16/subscribe-receives-events-0
    @Test
    func test_RTINS16_subscribe_receives_events() async throws {
        let (_, _, root, ws) = try await setupSyncedChannel("test")
        let counter = try root.get(key: "score").instance()?.asLiveCounter()
        let events = Captured<InstanceSubscriptionEvent>()
        let sub = try counter?.subscribe(listener: { events.append($0) })

        sendToClient(ws, [StandardTestPool.counterInc(objectId: "counter:score@1000", number: 7, serial: "99", siteCode: "remote")])
        poll("events.count >= 1") { events.count >= 1 }

        _ = sub // RTINS16f
        #expect(events.count == 1)
        #expect(events.first?.object.id() == "counter:score@1000") // RTINS16e1
    }

    // UTS: objects/unit/RTINS16c/subscribe-primitive-throws-0
    @Test
    func test_RTINS16c_subscribe_on_primitive_throws_92007() throws {
        // DEVIATION (RTINS16c): `subscribe` exists only on the `LiveMapInstance` / `LiveCounterInstance`
        // payloads, not `PrimitiveInstance`, so it cannot be called on a primitive — the "throws 92007"
        // path is compile-time-unreachable. See deviations.md.
    }

    // UTS: objects/unit/RTINS16e2/subscription-event-message-0
    @Test
    func test_RTINS16e2_event_contains_public_object_message() async throws {
        let (_, _, root, ws) = try await setupSyncedChannel("test")
        let rootInstance = try root.instance()?.asLiveMap()
        let events = Captured<InstanceSubscriptionEvent>()
        _ = try rootInstance?.subscribe(listener: { events.append($0) })

        sendToClient(ws, [StandardTestPool.mapSet(objectId: "root", key: "name", value: StandardTestPool.data(string: "Bob"), serial: StandardTestPool.remoteSerial(0), siteCode: "remote")])
        poll("events.count >= 1") { events.count >= 1 }

        let event = try #require(events.first)
        #expect(event.object.id() == "root") // RTINS16e1
        let message = try #require(event.message) // RTINS16e2
        #expect(message.channel == "test")
        #expect(message.operation.action == .mapSet)
        #expect(message.operation.objectId == "root")
        #expect(message.operation.mapSet?.key == "name")
    }

    // UTS: objects/unit/RTINS16f/subscribe-returns-subscription-0
    @Test
    func test_RTINS16f_unsubscribe_deregisters() async throws {
        let (_, _, root, ws) = try await setupSyncedChannel("test")
        let counter = try root.get(key: "score").instance()?.asLiveCounter()
        let events = Captured<InstanceSubscriptionEvent>()
        let sub = try counter?.subscribe(listener: { events.append($0) })
        sub?.unsubscribe()

        // Quiescence control: a second, still-subscribed listener on the same counter instance.
        let control = Captured<InstanceSubscriptionEvent>()
        _ = try counter?.subscribe(listener: { control.append($0) })

        sendToClient(ws, [StandardTestPool.counterInc(objectId: "counter:score@1000", number: 7, serial: "99", siteCode: "remote")])
        poll("control fired") { control.count >= 1 }

        #expect(events.count == 0)
    }

    // UTS: objects/unit/RTINS16g/subscription-follows-identity-0
    @Test
    func test_RTINS16g_subscription_follows_identity_not_path() async throws {
        let (_, _, root, ws) = try await setupSyncedChannel("test")
        let counter = try root.get(key: "score").instance()?.asLiveCounter()
        let events = Captured<InstanceSubscriptionEvent>()
        _ = try counter?.subscribe(listener: { events.append($0) })

        // Repoint "score" to a new object, then mutate the ORIGINAL counter:score@1000.
        sendToClient(ws, [StandardTestPool.mapSet(objectId: "root", key: "score", value: StandardTestPool.data(objectId: "counter:new@2000"), serial: StandardTestPool.remoteSerial(0), siteCode: "remote")])
        sendToClient(ws, [StandardTestPool.counterInc(objectId: "counter:score@1000", number: 10, serial: "100", siteCode: "remote")])
        poll("events.count >= 1") { events.count >= 1 }

        #expect(events.count >= 1)
        // Identity-based: the event carries the original object regardless of the "score" repoint.
        #expect(events.first?.object.id() == "counter:score@1000")
    }

    // UTS: objects/unit/RTINS16h/subscribe-no-side-effects-0
    @Test
    func test_RTINS16h_subscribe_has_no_side_effects() async throws {
        let (_, channel, root, _) = try await setupSyncedChannel("test")
        let counter = try root.get(key: "score").instance()?.asLiveCounter()
        let stateBefore = channel.state

        _ = try counter?.subscribe(listener: { _ in })

        #expect(channel.state == stateBefore)
    }
}
