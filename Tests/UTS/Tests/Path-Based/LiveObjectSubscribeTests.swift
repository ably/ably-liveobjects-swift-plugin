import Ably
import Foundation
import Testing
@testable import AblyLiveObjects

/// LiveObject subscribe via `Instance#subscribe` (`RTLO4b`, `RTINS16`).
/// Derived from https://github.com/ably/specification/blob/0a531c79adfc072c6d1441591f2dd838913dfe73/uts/objects/unit/live_object_subscribe.md
///
/// The spec's `root.get("score").instance()` maps to `root.get(key: "score").instance()`, whose
/// payload is extracted with `asLiveCounter()` / `asLiveMap()` (see ``Instance`` and
/// `Instance+Testing`). Listeners are captured with the thread-safe ``Captured`` and deliveries are
/// awaited with `poll(...)`; inbound operations are injected as `OBJECT` messages through the mock.
/// The "negative-assertion quiescence" pattern from `standard_test_pool.md` is preserved.
@Suite(.serialized)
final class LiveObjectSubscribeTests: UTSTestCase {
    // MARK: - RTLO4b — subscribe registers listener

    // UTS: objects/unit/RTLO4b/subscribe-receives-updates-0
    @Test
    func test_RTLO4b_subscribe_registers_listener_for_data_updates() async throws {
        let (_, _, root, ws) = try await setupSyncedChannel("test")
        let updates = Captured<InstanceSubscriptionEvent>()
        let instance = try root.get(key: "score").instance()?.asLiveCounter()
        let sub = try #require(instance).subscribe(listener: { updates.append($0) })

        sendToClient(ws, [StandardTestPool.counterInc(objectId: "counter:score@1000", number: 7, serial: "99", siteCode: "remote")])
        poll("updates.count >= 1") { updates.count >= 1 }

        _ = sub // RTLO4b7: returns a Subscription
        #expect(updates.count == 1)
    }

    // MARK: - RTLO4b7 — Subscription

    // UTS: objects/unit/RTLO4b7/subscribe-returns-subscription-0
    @Test
    func test_RTLO4b7_subscribe_returns_Subscription_with_unsubscribe() async throws {
        let (_, _, root, _) = try await setupSyncedChannel("test")
        let instance = try root.get(key: "score").instance()?.asLiveCounter()

        let sub = try #require(instance).subscribe(listener: { _ in })

        // RTLO4b7: `sub` conforms to `Subscription` (has `unsubscribe()`).
        _ = (sub as any Subscription).unsubscribe
    }

    // UTS: objects/unit/RTLO4b7/subscription-unsubscribe-stops-delivery-0
    @Test
    func test_RTLO4b7_unsubscribe_stops_delivery() async throws {
        let (_, _, root, ws) = try await setupSyncedChannel("test")
        let updates = Captured<InstanceSubscriptionEvent>()
        let control = Captured<InstanceSubscriptionEvent>()
        let instance = try #require(try root.get(key: "score").instance()?.asLiveCounter())
        let sub = try instance.subscribe(listener: { updates.append($0) })

        sendToClient(ws, [StandardTestPool.counterInc(objectId: "counter:score@1000", number: 5, serial: "01", siteCode: "remote")])
        poll("updates.count >= 1") { updates.count >= 1 }

        sub.unsubscribe()

        // Quiescence: a still-registered control listener that WILL fire on the same dispatch.
        _ = try instance.subscribe(listener: { control.append($0) })
        sendToClient(ws, [StandardTestPool.counterInc(objectId: "counter:score@1000", number: 10, serial: "02", siteCode: "remote")])
        poll("control fired") { control.count >= 1 }

        #expect(updates.count == 1)
    }

    // UTS: objects/unit/RTLO4b7/subscription-unsubscribe-idempotent-0
    @Test
    func test_RTLO4b7_unsubscribe_is_idempotent() async throws {
        let (_, _, root, _) = try await setupSyncedChannel("test")
        let instance = try #require(try root.get(key: "score").instance()?.asLiveCounter())
        let sub = try instance.subscribe(listener: { _ in })

        sub.unsubscribe()
        sub.unsubscribe() // SUB2b: calling more than once is a no-op (must not throw)
    }

    // MARK: - RTLO4b4c1 — noop update

    // UTS: objects/unit/RTLO4b4c1/noop-no-trigger-0
    @Test
    func test_RTLO4b4c1_noop_update_does_not_trigger_listener() async throws {
        // DEVIATION (RTLO4b4c1 / RTLC9h): the noop stimulus is a COUNTER_INC whose `counterInc` has no
        // `number` field. Swift's `WireCounterInc.number` is a non-optional `NSNumber`, so an empty
        // `counterInc: {}` isn't constructible — the RTLC9h noop branch can't be exercised through the
        // typed builder. The test keeps the spec point and asserts that two real increments produce
        // exactly two updates (the noop, were it sendable, would sit between them and add nothing). See
        // deviations.md.
        let (_, _, root, ws) = try await setupSyncedChannel("test")
        let updates = Captured<InstanceSubscriptionEvent>()
        let instance = try #require(try root.get(key: "score").instance()?.asLiveCounter())
        try instance.subscribe(listener: { updates.append($0) })

        sendToClient(ws, [StandardTestPool.counterInc(objectId: "counter:score@1000", number: 5, serial: "01", siteCode: "remote")])
        poll("updates.count >= 1") { updates.count >= 1 }
        sendToClient(ws, [StandardTestPool.counterInc(objectId: "counter:score@1000", number: 3, serial: "03", siteCode: "remote")])
        poll("updates.count >= 2") { updates.count >= 2 }

        #expect(updates.count == 2)
    }

    // MARK: - RTLO4b6 — no side effects

    // UTS: objects/unit/RTLO4b6/subscribe-no-side-effects-0
    @Test
    func test_RTLO4b6_subscribe_has_no_side_effects() async throws {
        let (_, channel, root, _) = try await setupSyncedChannel("test")
        let stateBefore = channel.state
        let instance = try #require(try root.get(key: "score").instance()?.asLiveCounter())

        try instance.subscribe(listener: { _ in })

        #expect(channel.state == stateBefore)
    }

    // MARK: - RTLO4b — map update

    // UTS: objects/unit/RTLO4b/subscribe-map-update-0
    @Test
    func test_RTLO4b_subscribe_on_map_receives_LiveMapUpdate() async throws {
        let (_, _, root, ws) = try await setupSyncedChannel("test")
        let updates = Captured<InstanceSubscriptionEvent>()
        let instance = try #require(try root.instance()?.asLiveMap())
        try instance.subscribe(listener: { updates.append($0) })

        sendToClient(ws, [StandardTestPool.mapSet(objectId: "root", key: "name", value: StandardTestPool.data(string: "Bob"), serial: StandardTestPool.remoteSerial(0), siteCode: "remote")])
        poll("updates.count >= 1") { updates.count >= 1 }

        #expect(updates.count == 1)
    }

    // MARK: - RTLO4b4c3c — tombstone deregisters listeners

    // UTS: objects/unit/RTLO4b4c3c/tombstone-deregisters-listeners-0
    @Test
    func test_RTLO4b4c3c_tombstone_update_deregisters_all_listeners() async throws {
        let (_, _, root, ws) = try await setupSyncedChannel("test")
        let updatesA = Captured<InstanceSubscriptionEvent>()
        let updatesB = Captured<InstanceSubscriptionEvent>()
        let control = Captured<InstanceSubscriptionEvent>()
        let instance = try #require(try root.get(key: "score").instance()?.asLiveCounter())
        try instance.subscribe(listener: { updatesA.append($0) })
        try instance.subscribe(listener: { updatesB.append($0) })

        // OBJECT_DELETE → tombstone update; both listeners receive it before deregistration.
        sendToClient(ws, [StandardTestPool.objectDelete(objectId: "counter:score@1000", serial: "50", siteCode: "remote")])
        poll("updatesA fired") { updatesA.count >= 1 }
        poll("updatesB fired") { updatesB.count >= 1 }

        #expect(updatesA.count == 1)
        #expect(updatesA.first?.message?.operation.action == .objectDelete)
        #expect(updatesB.count == 1)
        #expect(updatesB.first?.message?.operation.action == .objectDelete)

        // A tombstoned object ignores further ops (RTLC7e), so the control listener must be on a
        // SEPARATE live object (map:profile@1000) to serve as the quiescence barrier.
        let controlInstance = try #require(try root.get(key: "profile").instance()?.asLiveMap())
        try controlInstance.subscribe(listener: { control.append($0) })
        sendToClient(ws, [StandardTestPool.counterInc(objectId: "counter:score@1000", number: 3, serial: "51", siteCode: "remote")])
        sendToClient(ws, [StandardTestPool.mapSet(objectId: "map:profile@1000", key: "quiescence_probe", value: StandardTestPool.data(string: "x"), serial: "52", siteCode: "remote")])
        poll("control fired") { control.count >= 1 }

        #expect(updatesA.count == 1)
        #expect(updatesB.count == 1)
    }

    // MARK: - RTLO4b4d — event.message populated

    // UTS: objects/unit/RTLO4b4d/update-has-object-message-0
    @Test
    func test_RTLO4b4d_event_message_populated_from_source_ObjectMessage() async throws {
        let (_, _, root, ws) = try await setupSyncedChannel("test")
        let updates = Captured<InstanceSubscriptionEvent>()
        let instance = try #require(try root.get(key: "score").instance()?.asLiveCounter())
        try instance.subscribe(listener: { updates.append($0) })

        sendToClient(ws, [StandardTestPool.counterInc(objectId: "counter:score@1000", number: 7, serial: "99", siteCode: "remote")])
        poll("updates.count >= 1") { updates.count >= 1 }

        #expect(updates.count == 1)
        let message = try #require(updates.first?.message) // RTINS16e
        #expect(message.serial == "99")
        #expect(message.siteCode == "remote")
        #expect(message.operation.action == .counterInc)
        #expect(message.operation.objectId == "counter:score@1000")
    }

    // MARK: - RTLO4b4e — tombstone identified by OBJECT_DELETE

    // UTS: objects/unit/RTLO4b4e/tombstone-flag-true-0
    @Test
    func test_RTLO4b4e_tombstone_update_carries_OBJECT_DELETE_action() async throws {
        let (_, _, root, ws) = try await setupSyncedChannel("test")
        let updates = Captured<InstanceSubscriptionEvent>()
        let instance = try #require(try root.get(key: "score").instance()?.asLiveCounter())
        try instance.subscribe(listener: { updates.append($0) })

        sendToClient(ws, [StandardTestPool.objectDelete(objectId: "counter:score@1000", serial: "50", siteCode: "remote")])
        poll("updates.count >= 1") { updates.count >= 1 }

        #expect(updates.count == 1)
        #expect(updates.first?.message?.operation.action == .objectDelete)
    }

    // UTS: objects/unit/RTLO4b4e/tombstone-flag-false-0
    @Test
    func test_RTLO4b4e_normal_update_carries_non_tombstone_action() async throws {
        let (_, _, root, ws) = try await setupSyncedChannel("test")
        let updates = Captured<InstanceSubscriptionEvent>()
        let instance = try #require(try root.get(key: "score").instance()?.asLiveCounter())
        try instance.subscribe(listener: { updates.append($0) })

        sendToClient(ws, [StandardTestPool.counterInc(objectId: "counter:score@1000", number: 7, serial: "99", siteCode: "remote")])
        poll("updates.count >= 1") { updates.count >= 1 }

        #expect(updates.count == 1)
        #expect(updates.first?.message?.operation.action == .counterInc)
    }
}
