import Ably
import Foundation
import Testing
@testable import AblyLiveObjects

/// PathObject subscriptions (`RTPO19`, `RTO24`, `RTO25`).
/// Derived from https://github.com/ably/specification/blob/0a531c79adfc072c6d1441591f2dd838913dfe73/uts/objects/unit/path_object_subscribe.md
///
/// Listeners are captured with the thread-safe ``Captured`` (the callback is `@Sendable`), and
/// deliveries are awaited with `poll(...)`. Inbound operations are injected as `OBJECT` messages
/// through the mock. The "negative-assertion quiescence" pattern from `standard_test_pool.md` is
/// preserved: a control listener that *does* fire is awaited before asserting a count is unchanged.
@Suite(.serialized)
final class PathObjectSubscribeTests: UTSTestCase {
    // MARK: - RTPO19 — basic subscribe / event delivery

    // UTS: objects/unit/RTPO19/subscribe-receives-events-0
    @Test
    func test_RTPO19_subscribe_returns_Subscription_and_receives_events() async throws {
        let (_, _, root, ws) = try await setupSyncedChannel("test")
        let events = Captured<PathObjectSubscriptionEvent>()
        let sub = try root.get(key: "score").subscribe(listener: { events.append($0) })

        sendToClient(ws, [StandardTestPool.counterInc(objectId: "counter:score@1000", number: 7, serial: "99", siteCode: "remote")])
        poll("events.count >= 1") { events.count >= 1 }

        _ = sub // RTPO19d: returns a Subscription
        #expect(events.count == 1)
        let event = try #require(events.first)
        #expect(event.object.path == "score") // RTPO19e1
        let message = try #require(event.message) // RTPO19e2
        #expect(message.serial == "99")
        #expect(message.siteCode == "remote")
        #expect(message.operation.action == .counterInc)
        #expect(message.channel == "test")
    }

    // UTS: objects/unit/RTPO19b/subscribe-precondition-detached-0
    @Test
    func test_RTPO19b_subscribe_precondition_detached_throws_90001() async throws {
        let (_, channel, root, _) = try await setupSyncedChannel("test")

        // RTO25b: on a DETACHED (or FAILED) channel the access API throws 90001. (The mock doesn't
        // model DETACH responses; this documents the precondition — the setup traps at get() first.)
        channel.detach()
        awaitChannelState(channel, .detached)

        expectError(code: 90001, statusCode: 400) {
            _ = try root.subscribe(listener: { _ in })
        }
    }

    // UTS: objects/unit/RTPO19c1a/subscribe-non-positive-depth-throws-0
    @Test
    func test_RTPO19c1a_subscribe_non_positive_depth_throws_40003() async throws {
        let (_, _, root, _) = try await setupSyncedChannel("test")
        expectError(code: 40003) {
            _ = try root.subscribe(options: PathObjectSubscriptionOptions(depth: 0), listener: { _ in })
        }
    }

    // UTS: objects/unit/RTPO19c1a/subscribe-negative-depth-throws-0
    @Test
    func test_RTPO19c1a_subscribe_negative_depth_throws_40003() async throws {
        let (_, _, root, _) = try await setupSyncedChannel("test")
        expectError(code: 40003) {
            _ = try root.subscribe(options: PathObjectSubscriptionOptions(depth: -1), listener: { _ in })
        }
    }

    // MARK: - RTPO19c1 — depth filtering

    // UTS: objects/unit/RTPO19c1/subscribe-depth-1-self-only-0
    @Test
    func test_RTPO19c1_depth_1_receives_self_only() async throws {
        let (_, _, root, ws) = try await setupSyncedChannel("test")
        let events = Captured<PathObjectSubscriptionEvent>()
        _ = try root.subscribe(options: PathObjectSubscriptionOptions(depth: 1), listener: { events.append($0) })
        // Quiescence control: unlimited-depth root listener that covers the out-of-scope child path.
        let control = Captured<PathObjectSubscriptionEvent>()
        _ = try root.subscribe(listener: { control.append($0) })

        sendToClient(ws, [StandardTestPool.mapSet(objectId: "root", key: "name", value: StandardTestPool.data(string: "Bob"), serial: StandardTestPool.remoteSerial(0), siteCode: "remote")])
        poll("events.count >= 1") { events.count >= 1 }

        let controlBefore = control.count
        sendToClient(ws, [StandardTestPool.counterInc(objectId: "counter:score@1000", number: 7, serial: "100", siteCode: "remote")])
        poll("control fired") { control.count > controlBefore }

        #expect(events.count == 1) // depth 1: the out-of-scope child update did not fire
    }

    // UTS: objects/unit/RTPO19c1/subscribe-depth-2-children-0
    @Test
    func test_RTPO19c1_depth_2_receives_self_and_children() async throws {
        let (_, _, root, ws) = try await setupSyncedChannel("test")
        let events = Captured<PathObjectSubscriptionEvent>()
        _ = try root.subscribe(options: PathObjectSubscriptionOptions(depth: 2), listener: { events.append($0) })
        let control = Captured<PathObjectSubscriptionEvent>()
        _ = try root.subscribe(listener: { control.append($0) })

        // Self event (root map update) — covered at depth 2.
        sendToClient(ws, [StandardTestPool.mapSet(objectId: "root", key: "name", value: StandardTestPool.data(string: "Bob"), serial: StandardTestPool.remoteSerial(0), siteCode: "remote")])
        poll("events.count >= 1") { events.count >= 1 }

        // Child event (root["score"]) — relativeDepth 2 <= 2, covered.
        sendToClient(ws, [StandardTestPool.counterInc(objectId: "counter:score@1000", number: 7, serial: "100", siteCode: "remote")])
        poll("events.count >= 2") { events.count >= 2 }

        // Grandchild event (root["profile"]["nested_counter"]) — relativeDepth 3 > 2, NOT covered.
        let controlBefore = control.count
        sendToClient(ws, [StandardTestPool.counterInc(objectId: "counter:nested@1000", number: 1, serial: "101", siteCode: "remote")])
        poll("control fired") { control.count > controlBefore }

        #expect(events.count == 2)
    }

    // UTS: objects/unit/RTPO19c1/subscribe-unlimited-depth-0
    @Test
    func test_RTPO19c1_no_depth_receives_all_descendants() async throws {
        let (_, _, root, ws) = try await setupSyncedChannel("test")
        let events = Captured<PathObjectSubscriptionEvent>()
        _ = try root.subscribe(listener: { events.append($0) })

        sendToClient(ws, [StandardTestPool.mapSet(objectId: "root", key: "name", value: StandardTestPool.data(string: "Bob"), serial: StandardTestPool.remoteSerial(0), siteCode: "remote")])
        poll("events.count >= 1") { events.count >= 1 }
        sendToClient(ws, [StandardTestPool.counterInc(objectId: "counter:score@1000", number: 7, serial: "100", siteCode: "remote")])
        poll("events.count >= 2") { events.count >= 2 }
        sendToClient(ws, [StandardTestPool.mapSet(objectId: "map:prefs@1000", key: "theme", value: StandardTestPool.data(string: "light"), serial: StandardTestPool.remoteSerial(1), siteCode: "remote")])
        poll("events.count >= 3") { events.count >= 3 }

        #expect(events.count >= 3)
    }

    // MARK: - RTPO19d — unsubscribe

    // UTS: objects/unit/RTPO19d/subscribe-returns-subscription-0
    @Test
    func test_RTPO19d_unsubscribe_deregisters_listener() async throws {
        let (_, _, root, ws) = try await setupSyncedChannel("test")
        let events = Captured<PathObjectSubscriptionEvent>()
        let sub = try root.get(key: "score").subscribe(listener: { events.append($0) })
        // Quiescence control: a separate, still-subscribed listener that WILL fire.
        let control = Captured<PathObjectSubscriptionEvent>()
        _ = try root.get(key: "score").subscribe(listener: { control.append($0) })

        sub.unsubscribe()
        sendToClient(ws, [StandardTestPool.counterInc(objectId: "counter:score@1000", number: 7, serial: "99", siteCode: "remote")])
        poll("control fired") { control.count >= 1 }

        #expect(events.count == 0)
    }

    // MARK: - RTPO19e — event contents

    // UTS: objects/unit/RTPO19e1/event-path-object-correct-0
    @Test
    func test_RTPO19e1_event_provides_correct_PathObject() async throws {
        let (_, _, root, ws) = try await setupSyncedChannel("test")
        let events = Captured<PathObjectSubscriptionEvent>()
        _ = try root.subscribe(listener: { events.append($0) })

        sendToClient(ws, [StandardTestPool.counterInc(objectId: "counter:score@1000", number: 7, serial: "99", siteCode: "remote")])
        poll("events.count >= 1") { events.count >= 1 }

        let event = try #require(events.first)
        #expect(event.object.path == "score")
        #expect(try event.object.asLiveCounter().value() == 107)
    }

    // UTS: objects/unit/RTPO19e2/event-message-delivery-0
    @Test
    func test_RTPO19e2_event_delivers_public_object_message() async throws {
        let (_, _, root, ws) = try await setupSyncedChannel("test")
        let events = Captured<PathObjectSubscriptionEvent>()
        _ = try root.get(key: "score").subscribe(listener: { events.append($0) })

        sendToClient(ws, [StandardTestPool.counterInc(objectId: "counter:score@1000", number: 42, serial: "serial-1", siteCode: "site-a")])
        poll("events.count >= 1") { events.count >= 1 }

        let message = try #require(events.first?.message)
        #expect(message.channel == "test")
        #expect(message.serial == "serial-1")
        #expect(message.siteCode == "site-a")
        #expect(message.operation.action == .counterInc)
        #expect(message.operation.objectId == "counter:score@1000")
        #expect(message.operation.counterInc?.number == 42)
    }

    // UTS: objects/unit/RTPO19e2/event-message-omitted-no-operation-0
    @Test
    func test_RTPO19e2_event_omits_message_when_no_operation() async throws {
        let (_, _, root, ws) = try await setupSyncedChannel("test")
        let events = Captured<PathObjectSubscriptionEvent>()
        _ = try root.subscribe(listener: { events.append($0) })

        // A sync-triggered update (replaceData, RTLC6) has no `operation`, so its event has no message.
        ws.activeConnection?.sendToClient(.objectSync(channel: "test", channelSerial: "sync2:", state: [
            StandardTestPool.objectStateMessage(
                objectId: "counter:score@1000",
                siteTimeserials: ["aaa": "t:1"],
                counter: WireObjectsCounter(count: NSNumber(value: 0)),
                createOp: StandardTestPool.counterCreateOp(objectId: "counter:score@1000", count: 200),
            ),
        ]))
        poll("events.count >= 1") { events.count >= 1 }

        for event in events.all {
            #expect(event.message == nil)
        }
    }

    // MARK: - RTPO19f — follows path not identity

    // UTS: objects/unit/RTPO19f/subscribe-follows-path-0
    @Test
    func test_RTPO19f_subscribe_follows_path_not_identity() async throws {
        let (_, _, root, ws) = try await setupSyncedChannel("test")
        let events = Captured<PathObjectSubscriptionEvent>()
        _ = try root.get(key: "score").subscribe(listener: { events.append($0) })

        // Replace the counter at "score" with a new object, then mutate the new one.
        sendToClient(ws, [StandardTestPool.mapSet(objectId: "root", key: "score", value: StandardTestPool.data(objectId: "counter:new@2000"), serial: StandardTestPool.remoteSerial(0), siteCode: "remote")])
        sendToClient(ws, [StandardTestPool.counterInc(objectId: "counter:new@2000", number: 10, serial: "100", siteCode: "remote")])
        poll("events.count >= 1") { events.count >= 1 }

        // Subscription follows the path, so it delivers events for the new object at "score".
        #expect(events.all.contains { $0.object.path == "score" })
    }

    // MARK: - RTPO19g — no side effects

    // UTS: objects/unit/RTPO19g/subscribe-no-side-effects-0
    @Test
    func test_RTPO19g_subscribe_has_no_side_effects() async throws {
        let (_, channel, root, _) = try await setupSyncedChannel("test")
        let stateBefore = channel.state

        _ = try root.get(key: "score").subscribe(listener: { _ in })

        #expect(channel.state == stateBefore)
    }

    // MARK: - RTPO19 — primitive path, MAP_CLEAR, bubbling

    // UTS: objects/unit/RTPO19/subscribe-primitive-path-0
    @Test
    func test_RTPO19_subscribe_on_primitive_path_receives_change_events() async throws {
        let (_, _, root, ws) = try await setupSyncedChannel("test")
        let events = Captured<PathObjectSubscriptionEvent>()
        _ = try root.get(key: "name").subscribe(listener: { events.append($0) })

        sendToClient(ws, [StandardTestPool.mapSet(objectId: "root", key: "name", value: StandardTestPool.data(string: "Bob"), serial: StandardTestPool.remoteSerial(0), siteCode: "remote")])
        poll("events.count >= 1") { events.count >= 1 }

        #expect(events.count == 1)
        #expect(events.first?.object.path == "name")
    }

    // UTS: objects/unit/RTPO19/map-clear-triggers-child-events-0
    @Test
    func test_RTPO19_map_clear_triggers_child_events() async throws {
        let (_, _, root, ws) = try await setupSyncedChannel("test")
        let events = Captured<PathObjectSubscriptionEvent>()
        _ = try root.subscribe(listener: { events.append($0) })

        sendToClient(ws, [StandardTestPool.mapClear(objectId: "root", serial: "99", siteCode: "remote")])
        poll("events.count >= 1") { events.count >= 1 }

        #expect(events.count >= 1)
    }

    // UTS: objects/unit/RTPO19/child-events-bubble-0
    @Test
    func test_RTPO19_child_events_bubble_up_to_parent() async throws {
        let (_, _, root, ws) = try await setupSyncedChannel("test")
        let events = Captured<PathObjectSubscriptionEvent>()
        _ = try root.get(key: "profile").subscribe(listener: { events.append($0) })

        sendToClient(ws, [StandardTestPool.mapSet(objectId: "map:profile@1000", key: "email", value: StandardTestPool.data(string: "bob@example.com"), serial: StandardTestPool.remoteSerial(0), siteCode: "remote")])
        poll("events.count >= 1") { events.count >= 1 }
        sendToClient(ws, [StandardTestPool.counterInc(objectId: "counter:nested@1000", number: 3, serial: "100", siteCode: "remote")])
        poll("events.count >= 2") { events.count >= 2 }

        #expect(events.count >= 2)
    }

    // MARK: - RTO24 — dispatch rules

    // UTS: objects/unit/RTO24c1/depth-filtering-formula-0
    @Test
    func test_RTO24c1_depth_filtering_formula() async throws {
        let (_, _, root, ws) = try await setupSyncedChannel("test")

        // Seed a grandchild under profile.prefs so the grandchild stimulus can be a single-candidate
        // COUNTER_INC (RTO6 zero-value-creates counter:deep@3000). Sent before subscribing.
        sendToClient(ws, [StandardTestPool.mapSet(objectId: "map:prefs@1000", key: "deep", value: StandardTestPool.data(objectId: "counter:deep@3000"), serial: "50", siteCode: "remote")])

        let events = Captured<PathObjectSubscriptionEvent>()
        _ = try root.get(key: "profile").subscribe(options: PathObjectSubscriptionOptions(depth: 2), listener: { events.append($0) })
        let control = Captured<PathObjectSubscriptionEvent>()
        _ = try root.subscribe(listener: { control.append($0) })

        // Self (["profile"], relativeDepth 1) — covered.
        sendToClient(ws, [StandardTestPool.mapSet(objectId: "map:profile@1000", key: "email", value: StandardTestPool.data(string: "bob@example.com"), serial: StandardTestPool.remoteSerial(0), siteCode: "remote")])
        poll("events.count >= 1") { events.count >= 1 }
        // Child (["profile","nested_counter"], relativeDepth 2) — covered.
        sendToClient(ws, [StandardTestPool.counterInc(objectId: "counter:nested@1000", number: 3, serial: "100", siteCode: "remote")])
        poll("events.count >= 2") { events.count >= 2 }
        // Grandchild (["profile","prefs","deep"], relativeDepth 3) — NOT covered.
        let controlBefore = control.count
        sendToClient(ws, [StandardTestPool.counterInc(objectId: "counter:deep@3000", number: 1, serial: "101", siteCode: "remote")])
        poll("control fired") { control.count > controlBefore }

        #expect(events.count == 2)
    }

    // UTS: objects/unit/RTO24c1/prefix-mismatch-0
    @Test
    func test_RTO24c1_prefix_mismatch_does_not_trigger() async throws {
        let (_, _, root, ws) = try await setupSyncedChannel("test")
        let profileEvents = Captured<PathObjectSubscriptionEvent>()
        _ = try root.get(key: "profile").subscribe(listener: { profileEvents.append($0) })
        let control = Captured<PathObjectSubscriptionEvent>()
        _ = try root.subscribe(listener: { control.append($0) })

        sendToClient(ws, [StandardTestPool.counterInc(objectId: "counter:score@1000", number: 7, serial: "99", siteCode: "remote")])
        sendToClient(ws, [StandardTestPool.mapSet(objectId: "root", key: "name", value: StandardTestPool.data(string: "Bob"), serial: StandardTestPool.remoteSerial(0), siteCode: "remote")])
        poll("control fired for both") { control.count >= 2 }

        #expect(profileEvents.count == 0) // "profile" is not a prefix of "score"/"name"
    }

    // UTS: objects/unit/RTO24b2a/candidate-paths-map-keys-0
    @Test
    func test_RTO24b2a_candidate_paths_include_map_update_keys() async throws {
        let (_, _, root, ws) = try await setupSyncedChannel("test")
        let scoreEvents = Captured<PathObjectSubscriptionEvent>()
        let rootEvents = Captured<PathObjectSubscriptionEvent>()
        _ = try root.get(key: "score").subscribe(listener: { scoreEvents.append($0) })
        _ = try root.subscribe(listener: { rootEvents.append($0) })

        // MAP_SET on root key "score" -> candidates [] and ["score"]; both subscriptions fire.
        sendToClient(ws, [StandardTestPool.mapSet(objectId: "root", key: "score", value: StandardTestPool.data(objectId: "counter:new@2000"), serial: StandardTestPool.remoteSerial(0), siteCode: "remote")])
        poll("scoreEvents fired") { scoreEvents.count >= 1 }
        poll("rootEvents fired") { rootEvents.count >= 1 }

        #expect(scoreEvents.count == 1)
        #expect(scoreEvents.first?.object.path == "score")
        #expect(rootEvents.count == 1)
    }

    // UTS: objects/unit/RTO24b2c/listener-exception-caught-0
    @Test
    func test_RTO24b2c_listener_exception_does_not_affect_others() async throws {
        // DEVIATION (RTO24b2c): the spec's first listener THROWS; Swift's `PathObjectSubscriptionCallback`
        // is non-throwing (`-> Void`), so a throwing listener isn't expressible. We keep a no-op first
        // listener and assert the second still fires (the observable intent). See deviations.md.
        let (_, _, root, ws) = try await setupSyncedChannel("test")
        let events = Captured<PathObjectSubscriptionEvent>()
        _ = try root.subscribe(listener: { _ in })
        _ = try root.subscribe(listener: { events.append($0) })

        sendToClient(ws, [StandardTestPool.mapSet(objectId: "root", key: "name", value: StandardTestPool.data(string: "Bob"), serial: StandardTestPool.remoteSerial(0), siteCode: "remote")])
        poll("events.count >= 1") { events.count >= 1 }

        #expect(events.count == 1)
    }

    // UTS: objects/unit/RTO24b1/multi-path-dispatch-0
    @Test
    func test_RTO24b1_dispatch_via_getFullPaths_for_multi_path_objects() async throws {
        let (_, _, root, ws) = try await setupSyncedChannel("test")
        let eventsScore = Captured<PathObjectSubscriptionEvent>()
        let eventsAlias = Captured<PathObjectSubscriptionEvent>()

        // Add a second reference "alias" -> counter:score@1000, so it has two paths.
        sendToClient(ws, [StandardTestPool.mapSet(objectId: "root", key: "alias", value: StandardTestPool.data(objectId: "counter:score@1000"), serial: "98", siteCode: "remote")])
        _ = try root.get(key: "score").subscribe(listener: { eventsScore.append($0) })
        _ = try root.get(key: "alias").subscribe(listener: { eventsAlias.append($0) })

        sendToClient(ws, [StandardTestPool.counterInc(objectId: "counter:score@1000", number: 5, serial: "99", siteCode: "remote")])
        poll("score fired") { eventsScore.count >= 1 }
        poll("alias fired") { eventsAlias.count >= 1 }

        #expect(eventsScore.count == 1)
        #expect(eventsScore.first?.object.path == "score")
        #expect(eventsAlias.count == 1)
        #expect(eventsAlias.first?.object.path == "alias")
    }

    // UTS: objects/unit/RTO24b2b/fires-once-per-dispatch-0
    @Test
    func test_RTO24b2b_subscription_fires_exactly_once_per_dispatch() async throws {
        let (_, _, root, ws) = try await setupSyncedChannel("test")
        let events = Captured<PathObjectSubscriptionEvent>()
        // Root (unlimited depth) covers both [] and ["score"], but must fire once per dispatch.
        _ = try root.subscribe(listener: { events.append($0) })

        sendToClient(ws, [StandardTestPool.mapSet(objectId: "root", key: "score", value: StandardTestPool.data(objectId: "counter:new@2000"), serial: StandardTestPool.remoteSerial(0), siteCode: "remote")])
        poll("events.count >= 1") { events.count >= 1 }
        // Control: a second single-candidate dispatch; awaiting it flushes any spurious extra callback.
        sendToClient(ws, [StandardTestPool.counterInc(objectId: "counter:new@2000", number: 1, serial: "100", siteCode: "remote")])
        poll("events.count >= 2") { events.count >= 2 }

        #expect(events.count == 2) // exactly one per dispatch
    }
}

private extension PathObjectSubscribeTests {

    /// Asserts `operation` throws an `ARTErrorInfo` with the given `code` (and optional `statusCode`).
    func expectError(code: Int, statusCode: Int? = nil, sourceLocation: SourceLocation = #_sourceLocation, _ operation: () throws -> Void) {
        do {
            try operation()
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
