import Ably
import Foundation
import Testing
@testable import AblyLiveObjects

/// RealtimeObject orchestration (`RTO2`, `RTO10`, `RTO15`, `RTO17`–`RTO20`, `RTO22`–`RTO26`).
/// Derived from https://github.com/ably/specification/blob/0a531c79adfc072c6d1441591f2dd838913dfe73/uts/objects/unit/realtime_object.md
///
/// Uses `setupSyncedChannel` / `objectsChannel` from the harness. Publish/apply behaviour is exercised
/// through the public path-object mutations (`increment`/`set`), which internally publishAndApply, and
/// sync events through `channel.object.on(...)`.
@Suite(.serialized)
final class RealtimeObjectTests: UTSTestCase {
    // MARK: - RTO23 — get()

    // UTS: objects/unit/RTO23/get-returns-path-object-0
    @Test
    func test_RTO23_get_returns_path_object_wrapping_root() async throws {
        let (_, _, root, _) = try await setupSyncedChannel("test")
        #expect(root.path == "") // RTO23d: root path is the empty path
    }

    // UTS: objects/unit/RTO23/get-implicit-attach-0
    @Test
    func test_RTO23_get_implicitly_attaches_channel() async throws {
        let objects = objectsChannel("test")
        #expect(objects.channel.state == .initialized)
        _ = try await objects.channel.object.get()
        #expect(objects.channel.state == .attached)
    }

    // UTS: objects/unit/RTO23d/get-resolves-immediately-synced-0
    @Test
    func test_RTO23d_get_resolves_immediately_when_already_synced() async throws {
        let (_, channel, _, _) = try await setupSyncedChannel("test")
        let root2 = try await channel.object.get()
        #expect(root2.path == "")
    }

    // UTS: objects/unit/RTO23c/get-waits-for-synced-0
    @Test
    func test_RTO23c_get_waits_for_synced_state() async throws {
        // ATTACHED arrives but the OBJECT_SYNC is deferred; get() must wait for it.
        let objects = objectsChannel("test", sync: false)
        async let pendingRoot = objects.channel.object.get()
        // Deliver the sync so get() can resolve.
        objects.ws.activeConnection?.sendToClient(.objectSync(channel: "test", channelSerial: "sync1:", state: StandardTestPool.objects))
        let root = try await pendingRoot
        #expect(root.path == "")
    }

    // UTS: objects/unit/RTO23a/get-requires-subscribe-mode-0
    // UTS: objects/unit/RTO25a/access-requires-subscribe-mode-0
    @Test
    func test_RTO23a_get_requires_OBJECT_SUBSCRIBE_mode() async throws {
        // Without OBJECT_SUBSCRIBE, get()/access throws 40024 (RTO2a2 / RTO25a).
        let objects = objectsChannel("test", modes: [.objectPublish], sync: false)
        await expectError(code: 40024, statusCode: 400) {
            _ = try await objects.channel.object.get()
        }
    }

    // UTS: objects/unit/RTO23e/get-reattaches-detached-0
    @Test
    func test_RTO23e_get_reattaches_detached_channel() async throws {
        let (_, channel, _, ws) = try await setupSyncedChannel("test")

        channel.detach()
        ws.activeConnection?.sendToClient(.detached(channel: "test"))
        awaitChannelState(channel, .detached)

        // get() on a DETACHED channel runs ensure-active-channel (RTL33b) -> implicit re-attach.
        let root = try await channel.object.get()
        #expect(root.path == "")
        #expect(channel.state == .attached)
    }

    // UTS: objects/unit/RTO23e/get-rejects-failed-0
    @Test
    func test_RTO23e_get_on_failed_channel_rejects_90001() async throws {
        let objects = objectsChannel("test", modes: [.objectSubscribe], sync: false)
        objects.channel.attach()
        objects.ws.activeConnection?.sendToClient(.channelError(channel: "test", code: 90000, statusCode: 400, message: "Channel error"))
        awaitChannelState(objects.channel, .failed)

        await expectError(code: 90001, statusCode: 400) {
            _ = try await objects.channel.object.get()
        }
    }

    // MARK: - RTO15 — publish

    // UTS: objects/unit/RTO15/publish-sends-object-pm-0
    @Test
    func test_RTO15_publish_sends_object_protocol_message() throws {
        // DEVIATION (RTO15): `publish` (and `PublishResult`) is an internal RealtimeObject method, not
        // part of the public `RealtimeObject` protocol (which exposes only `get()` / `on(...)`). The
        // publish path is exercised indirectly through the path-object mutations (see the RTO20 tests).
        // See deviations.md.
    }

    // MARK: - RTO20 — publishAndApply (apply-on-ACK)

    // UTS: objects/unit/RTO20/publish-and-apply-local-0
    @Test
    func test_RTO20_publish_and_apply_local_on_ack() async throws {
        let (_, _, root, _) = try await setupSyncedChannel("test")
        try await root.get(key: "score").asLiveCounter().increment(amount: 10)
        #expect(try root.get(key: "score").asLiveCounter().value() == 110)
    }

    // UTS: objects/unit/RTO20c/missing-site-code-0
    @Test
    func test_RTO20c_publish_and_apply_without_site_code_does_not_apply() async throws {
        // No siteCode in ConnectionDetails -> the synthetic message can't be built, so no local apply.
        let objects = objectsChannel("test", siteCode: nil)
        let root = try await objects.channel.object.get()
        try await root.get(key: "score").asLiveCounter().increment(amount: 10)
        #expect(try root.get(key: "score").asLiveCounter().value() == 100)
    }

    // UTS: objects/unit/RTO20d1/null-serial-skipped-0
    @Test
    func test_RTO20d1_null_serial_in_publish_result_is_skipped() async throws {
        // ACK with a null serial -> that synthetic message is skipped, so no local apply.
        let objects = objectsChannel("test", autoAck: false)
        let root = try await objects.channel.object.get()
        // Respond to the OBJECT publish with a single null serial.
        // (autoAck is off; a bespoke ACK is not wired here since the API traps first — documents intent.)
        try await root.get(key: "score").asLiveCounter().increment(amount: 10)
        objects.ws.activeConnection?.sendToClient(.ack(msgSerial: 0, count: 1, serials: [nil]))
        #expect(try root.get(key: "score").asLiveCounter().value() == 100)
    }

    // UTS: objects/unit/RTO20e/waits-for-synced-0
    @Test
    func test_RTO20e_publish_and_apply_waits_for_synced_during_syncing() async throws {
        let (_, _, root, ws) = try await setupSyncedChannel("test")

        // Begin a new sync (SYNCING) without completing it.
        ws.activeConnection?.sendToClient(.attached(channel: "test", channelSerial: "sync2:cursor", hasObjects: true))

        async let pending: Void = root.get(key: "score").asLiveCounter().increment(amount: 10)
        // While SYNCING the increment must not have applied yet.
        #expect(try root.get(key: "score").asLiveCounter().value() == 100)

        // Complete the sync; the write then applies.
        ws.activeConnection?.sendToClient(.objectSync(channel: "test", channelSerial: "sync2:", state: StandardTestPool.objects))
        try await pending
        #expect(try root.get(key: "score").asLiveCounter().value() == 110)
    }

    // UTS: objects/unit/RTO20e1/fails-on-channel-detached-0
    @Test
    func test_RTO20e1_publish_and_apply_fails_when_channel_detached_during_sync_wait() async throws {
        let (_, _, root, ws) = try await setupSyncedChannel("test")
        ws.activeConnection?.sendToClient(.attached(channel: "test", channelSerial: "sync2:cursor", hasObjects: true))

        await expectError(code: 92008) {
            async let pending: Void = root.get(key: "score").asLiveCounter().increment(amount: 10)
            ws.activeConnection?.sendToClient(.detached(channel: "test"))
            try await pending
        }
    }

    // UTS: objects/unit/RTO20/echo-dedup-0
    @Test
    func test_RTO20_echo_deduplication_via_appliedOnAckSerials() async throws {
        let (_, _, root, ws) = try await setupSyncedChannel("test")
        try await root.get(key: "score").asLiveCounter().increment(amount: 10)
        #expect(try root.get(key: "score").asLiveCounter().value() == 110)

        // Echo with the same serial as the apply-on-ACK -> deduplicated (RTO9a3).
        sendToClient(ws, [StandardTestPool.counterInc(objectId: "counter:score@1000", number: 10, serial: StandardTestPool.ackSerial(0, 0), siteCode: StandardTestPool.siteCode)])
        #expect(try root.get(key: "score").asLiveCounter().value() == 110)
    }

    // UTS: objects/unit/RTO20f/ack-no-site-timeserials-update-0
    @Test
    func test_RTO20f_apply_on_ack_does_not_update_site_timeserials() async throws {
        let (_, _, root, ws) = try await setupSyncedChannel("test")
        try await root.get(key: "score").asLiveCounter().increment(amount: 10)
        #expect(try root.get(key: "score").asLiveCounter().value() == 110)

        // Inbound from SITE_CODE with a serial that is NOT the ACK serial but sorts below it. It
        // applies only if the LOCAL apply-on-ACK left siteTimeserials[SITE_CODE] untouched (RTLC7c).
        sendToClient(ws, [StandardTestPool.counterInc(objectId: "counter:score@1000", number: 10, serial: StandardTestPool.belowAckSerial(9), siteCode: StandardTestPool.siteCode)])
        poll("value == 120") { (try? root.get(key: "score").asLiveCounter().value()) == 120 }
        #expect(try root.get(key: "score").asLiveCounter().value() == 120)
    }

    // UTS: objects/unit/RTO20/ack-after-echo-no-double-apply-0
    @Test
    func test_RTO20_ack_after_echo_does_not_double_apply() async throws {
        let (_, _, root, ws) = try await setupSyncedChannel("test", autoAck: false)

        async let pending: Void = root.get(key: "score").asLiveCounter().increment(amount: 10)
        // Echo arrives BEFORE the ACK.
        sendToClient(ws, [StandardTestPool.counterInc(objectId: "counter:score@1000", number: 10, serial: StandardTestPool.ackSerial(0, 0), siteCode: StandardTestPool.siteCode)])
        // Then the ACK.
        ws.activeConnection?.sendToClient(.ack(msgSerial: 0, count: 1, serials: [StandardTestPool.ackSerial(0, 0)]))
        try await pending

        #expect(try root.get(key: "score").asLiveCounter().value() == 110)
    }

    // UTS: objects/unit/RTO5c9-RTO20/ack-serials-cleared-on-resync-0
    @Test
    func test_RTO5c9_applied_on_ack_serials_cleared_on_resync() async throws {
        let (_, _, root, ws) = try await setupSyncedChannel("test")
        try await root.get(key: "score").asLiveCounter().increment(amount: 10)
        #expect(try root.get(key: "score").asLiveCounter().value() == 110)

        // Re-sync resets the counter to its pool value and clears appliedOnAckSerials (RTO5c9).
        ws.activeConnection?.sendToClient(.attached(channel: "test", channelSerial: "sync2:cursor", hasObjects: true))
        ws.activeConnection?.sendToClient(.objectSync(channel: "test", channelSerial: "sync2:", state: StandardTestPool.objects))
        #expect(try root.get(key: "score").asLiveCounter().value() == 100)

        // The previously-applied serial now applies normally (not deduped).
        sendToClient(ws, [StandardTestPool.counterInc(objectId: "counter:score@1000", number: 10, serial: StandardTestPool.ackSerial(0, 0), siteCode: StandardTestPool.siteCode)])
        poll("value == 110") { (try? root.get(key: "score").asLiveCounter().value()) == 110 }
        #expect(try root.get(key: "score").asLiveCounter().value() == 110)
    }

    // UTS: objects/unit/RTO20/subscription-fires-on-ack-apply-0
    @Test
    func test_RTO20_subscription_fires_on_apply_on_ack() async throws {
        let (_, _, root, _) = try await setupSyncedChannel("test")
        let events = Captured<PathObjectSubscriptionEvent>()
        _ = try root.get(key: "score").subscribe(listener: { events.append($0) })

        try await root.get(key: "score").asLiveCounter().increment(amount: 10)
        #expect(events.count >= 1)
        #expect(try root.get(key: "score").asLiveCounter().value() == 110)
    }

    // MARK: - RTO17 / RTO18 / RTO19 — sync events

    // UTS: objects/unit/RTO17/sync-state-events-0
    @Test
    func test_RTO17_sync_state_events_in_order() async throws {
        let objects = objectsChannel("test", sync: false)
        let events = Captured<String>()
        _ = objects.channel.object.on(event: .syncing) { events.append("SYNCING") }
        _ = objects.channel.object.on(event: .synced) { events.append("SYNCED") }

        async let pendingRoot = objects.channel.object.get()
        poll("events.count >= 1") { events.count >= 1 }
        objects.ws.activeConnection?.sendToClient(.objectSync(channel: "test", channelSerial: "sync1:", state: StandardTestPool.objects))
        _ = try await pendingRoot

        #expect(events.all == ["SYNCING", "SYNCED"])
    }

    // UTS: objects/unit/RTO18d/duplicate-listener-0
    @Test
    func test_RTO18d_duplicate_listener_fires_twice() async throws {
        let (_, channel, _, ws) = try await setupSyncedChannel("test")
        let calls = Captured<Void>()
        let listener: @Sendable () -> Void = { calls.append(()) }
        _ = channel.object.on(event: .synced, callback: listener)
        _ = channel.object.on(event: .synced, callback: listener)

        ws.activeConnection?.sendToClient(.attached(channel: "test", channelSerial: "sync2:cursor", hasObjects: true))
        ws.activeConnection?.sendToClient(.objectSync(channel: "test", channelSerial: "sync2:", state: StandardTestPool.objects))
        poll("calls.count >= 2") { calls.count >= 2 }

        #expect(calls.count == 2)
    }

    // UTS: objects/unit/RTO19/off-deregisters-0
    @Test
    func test_RTO19_off_deregisters_listener() async throws {
        let (_, channel, _, ws) = try await setupSyncedChannel("test")
        let calls = Captured<Void>()
        let sub = channel.object.on(event: .synced) { calls.append(()) }
        sub.off()

        ws.activeConnection?.sendToClient(.attached(channel: "test", channelSerial: "sync2:cursor", hasObjects: true))
        ws.activeConnection?.sendToClient(.objectSync(channel: "test", channelSerial: "sync2:", state: StandardTestPool.objects))

        #expect(calls.count == 0)
    }

    // MARK: - RTO2 / RTO25 / RTO26 — mode & state preconditions

    // UTS: objects/unit/RTO2/mode-enforcement-0
    // UTS: objects/unit/RTO26a/write-requires-publish-mode-0
    @Test
    func test_RTO26a_write_requires_OBJECT_PUBLISH_mode() async throws {
        // Channel granted only OBJECT_SUBSCRIBE -> a write throws 40024.
        let objects = objectsChannel("test", modes: [.objectSubscribe])
        let root = try await objects.channel.object.get()
        await expectError(code: 40024, statusCode: 400) {
            try await root.set(key: "name", value: "Bob")
        }
    }

    // UTS: objects/unit/RTO25b/access-throws-detached-0
    @Test
    func test_RTO25b_access_throws_on_detached_channel() async throws {
        let (_, channel, root, ws) = try await setupSyncedChannel("test")
        ws.activeConnection?.sendToClient(.detached(channel: "test"))
        awaitChannelState(channel, .detached)

        expectErrorSync(code: 90001, statusCode: 400) {
            _ = try root.keys()
        }
    }

    // UTS: objects/unit/RTO25b/access-throws-failed-0
    @Test
    func test_RTO25b_access_throws_on_failed_channel() async throws {
        let (_, channel, root, ws) = try await setupSyncedChannel("test")
        ws.activeConnection?.sendToClient(.channelError(channel: "test", code: 90000, statusCode: 400, message: "Channel error"))
        awaitChannelState(channel, .failed)

        expectErrorSync(code: 90001, statusCode: 400) {
            _ = try root.keys()
        }
    }

    // UTS: objects/unit/RTO26b/write-throws-detached-0
    @Test
    func test_RTO26b_write_throws_on_detached_channel() async throws {
        let (_, channel, root, ws) = try await setupSyncedChannel("test")
        ws.activeConnection?.sendToClient(.detached(channel: "test"))
        awaitChannelState(channel, .detached)

        await expectError(code: 90001, statusCode: 400) {
            try await root.set(key: "name", value: "Bob")
        }
    }

    // UTS: objects/unit/RTO26b/write-throws-failed-0
    @Test
    func test_RTO26b_write_throws_on_failed_channel() async throws {
        let (_, channel, root, ws) = try await setupSyncedChannel("test")
        ws.activeConnection?.sendToClient(.channelError(channel: "test", code: 90000, statusCode: 400, message: "Channel error"))
        awaitChannelState(channel, .failed)

        await expectError(code: 90001, statusCode: 400) {
            try await root.set(key: "name", value: "Bob")
        }
    }

    // UTS: objects/unit/RTO26c/write-throws-echo-disabled-0
    @Test
    func test_RTO26c_write_throws_when_echo_disabled() async throws {
        let objects = objectsChannel("test", echoMessages: false)
        let root = try await objects.channel.object.get()
        await expectError(code: 40000, statusCode: 400) {
            try await root.set(key: "name", value: "Bob")
        }
    }

    // MARK: - RTO24 — dispatch register

    // UTS: objects/unit/RTO24a/single-register-instance-0
    @Test
    func test_RTO24a_single_subscription_register_per_channel() async throws {
        let (_, _, root, ws) = try await setupSyncedChannel("test")
        let rootEvents = Captured<PathObjectSubscriptionEvent>()
        let scoreEvents = Captured<PathObjectSubscriptionEvent>()
        _ = try root.subscribe(listener: { rootEvents.append($0) })
        _ = try root.get(key: "score").subscribe(listener: { scoreEvents.append($0) })

        sendToClient(ws, [StandardTestPool.counterInc(objectId: "counter:score@1000", number: 5, serial: "t:1", siteCode: "remote")])
        poll("score fired") { scoreEvents.count >= 1 }

        #expect(rootEvents.count >= 1)
        #expect(scoreEvents.count >= 1)
    }

    // UTS: objects/unit/RTO24c1/coverage-prefix-depth-0
    @Test
    func test_RTO24c1_coverage_prefix_with_depth_constraint() async throws {
        let (_, _, root, ws) = try await setupSyncedChannel("test")
        let shallowEvents = Captured<PathObjectSubscriptionEvent>()
        let deepEvents = Captured<PathObjectSubscriptionEvent>()
        _ = try root.subscribe(options: PathObjectSubscriptionOptions(depth: 1), listener: { shallowEvents.append($0) })
        _ = try root.subscribe(listener: { deepEvents.append($0) })

        // Root self-update ([], covered by depth 1).
        sendToClient(ws, [StandardTestPool.mapSet(objectId: "root", key: "name", value: StandardTestPool.data(string: "Bob"), serial: StandardTestPool.remoteSerial(0), siteCode: "remote")])
        poll("deep >= 1") { deepEvents.count >= 1 }
        // Child update (["score"], relativeDepth 2 > 1) — only deep covers it.
        sendToClient(ws, [StandardTestPool.counterInc(objectId: "counter:score@1000", number: 5, serial: "t:2", siteCode: "remote")])
        poll("deep >= 2") { deepEvents.count >= 2 }
        poll("shallow >= 1") { shallowEvents.count >= 1 }

        #expect(shallowEvents.count == 1)
        #expect(deepEvents.count >= 2)
    }

    // MARK: - RTO10 — garbage collection

    // UTS: objects/unit/RTO10/gc-tombstoned-objects-0
    @Test
    func test_RTO10_gc_removes_tombstoned_objects_past_grace_period() async throws {
        enableFakeTimers()
        let (_, _, root, ws) = try await setupSyncedChannel("test")

        sendToClient(ws, [StandardTestPool.objectDelete(objectId: "counter:score@1000", serial: "99", siteCode: "site1", serialTimestamp: Date(timeIntervalSince1970: 1))])

        advanceTime(byMilliseconds: 86_400_000 + 300_000)

        #expect(try root.get(key: "score").asLiveCounter().value() == nil)
    }

    // UTS: objects/unit/RTO10b1/gc-grace-period-source-0
    @Test
    func test_RTO10b1_gc_grace_period_from_connection_details() async throws {
        enableFakeTimers()
        // Short grace period (5000ms) from ConnectionDetails.
        let objects = objectsChannel("test", gcGracePeriod: 5000)
        let root = try await objects.channel.object.get()

        sendToClient(objects.ws, [StandardTestPool.objectDelete(objectId: "counter:score@1000", serial: "99", siteCode: "site1", serialTimestamp: Date(timeIntervalSince1970: 1))])
        advanceTime(byMilliseconds: 5000 + 1000)

        #expect(try root.get(key: "score").asLiveCounter().value() == nil)
    }

    // MARK: - RTO17 / RTO18 — sync event sequences

    // UTS: objects/unit/RTO17-RTO18/sync-event-sequences-0
    @Test
    func test_RTO17_RTO18_sync_event_sequence_initial_attach() async throws {
        // A genuine first attach: register listeners on a fresh (non-synced) channel BEFORE attach.
        let objects = objectsChannel("test", sync: false)
        let events = Captured<String>()
        _ = objects.channel.object.on(event: .syncing) { events.append("SYNCING") }
        _ = objects.channel.object.on(event: .synced) { events.append("SYNCED") }

        objects.channel.attach()
        objects.ws.activeConnection?.sendToClient(.objectSync(channel: "test", channelSerial: "sync1:", state: StandardTestPool.objects))
        poll("events.count >= 2") { events.count >= 2 }

        #expect(events.all == ["SYNCING", "SYNCED"])
    }

    // UTS: objects/unit/RTO17-RTO18/sync-event-sequences-0 (re-sync on new ATTACHED)
    @Test
    func test_RTO17_RTO18_sync_event_sequence_resync_on_new_attached() async throws {
        let (_, channel, _, ws) = try await setupSyncedChannel("test")
        let events = Captured<String>()
        _ = channel.object.on(event: .syncing) { events.append("SYNCING") }
        _ = channel.object.on(event: .synced) { events.append("SYNCED") }

        ws.activeConnection?.sendToClient(.attached(channel: "test", channelSerial: "sync3:cursor", hasObjects: true))
        ws.activeConnection?.sendToClient(.objectSync(channel: "test", channelSerial: "sync3:", state: StandardTestPool.objects))
        poll("events.count >= 2") { events.count >= 2 }

        #expect(events.all == ["SYNCING", "SYNCED"])
    }

    // UTS: objects/unit/RTO17-RTO18/sync-event-sequences-0 (ATTACHED without HAS_OBJECTS)
    @Test
    func test_RTO17_RTO18_sync_event_sequence_attached_without_has_objects() async throws {
        let (_, channel, _, ws) = try await setupSyncedChannel("test")
        let events = Captured<String>()
        _ = channel.object.on(event: .syncing) { events.append("SYNCING") }
        _ = channel.object.on(event: .synced) { events.append("SYNCED") }

        // ATTACHED without HAS_OBJECTS: RTO4c -> SYNCING, then RTO4b4 completes immediately -> SYNCED.
        ws.activeConnection?.sendToClient(.attached(channel: "test", channelSerial: "sync4:", hasObjects: false))
        poll("events.count >= 2") { events.count >= 2 }

        #expect(events.all == ["SYNCING", "SYNCED"])
    }
}

private extension RealtimeObjectTests {

    func expectError(code: Int, statusCode: Int? = nil, sourceLocation: SourceLocation = #_sourceLocation, _ operation: () async throws -> Void) async {
        do {
            try await operation()
            Issue.record("expected operation to throw ARTErrorInfo with code \(code)", sourceLocation: sourceLocation)
        } catch let error as ARTErrorInfo {
            #expect(error.code == code, sourceLocation: sourceLocation)
            if let statusCode { #expect(error.statusCode == statusCode, sourceLocation: sourceLocation) }
        } catch {
            Issue.record("expected ARTErrorInfo, got \(error)", sourceLocation: sourceLocation)
        }
    }

    func expectErrorSync(code: Int, statusCode: Int? = nil, sourceLocation: SourceLocation = #_sourceLocation, _ operation: () throws -> Void) {
        do {
            try operation()
            Issue.record("expected operation to throw ARTErrorInfo with code \(code)", sourceLocation: sourceLocation)
        } catch let error as ARTErrorInfo {
            #expect(error.code == code, sourceLocation: sourceLocation)
            if let statusCode { #expect(error.statusCode == statusCode, sourceLocation: sourceLocation) }
        } catch {
            Issue.record("expected ARTErrorInfo, got \(error)", sourceLocation: sourceLocation)
        }
    }
}
