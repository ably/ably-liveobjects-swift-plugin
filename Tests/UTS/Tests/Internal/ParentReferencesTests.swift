import Ably
import Foundation
import Testing
@testable import AblyLiveObjects

/// Parent-reference tracking on `LiveObject` (`RTLO3f`, `RTLO4f`, `RTLO4g`, `RTLO4h`, `RTO5c10`).
/// Derived from https://github.com/ably/specification/blob/0a531c79adfc072c6d1441591f2dd838913dfe73/uts/objects/unit/parent_references.md
///
/// The spec's `InternalLiveCounter(objectId:)` / `InternalLiveMap(objectId:, semantics:)` map to
/// `makeCounter` / `makeMap` (zero-valued), and `pool[id] = obj` to
/// `pool.testsOnly_setLiveMap(_:forObjectID:)` / `testsOnly_setLiveCounter(_:forObjectID:)`. The parent-reference API (`parentReferences`,
/// `addParentReference`, `removeParentReference`, `getFullPaths`) is a skeleton in this target — see
/// ``ParentReferencing`` — so every case traps via `notImplemented()` at runtime; the goal here is a
/// faithful translation that compiles and that will pass once the API is implemented.
///
/// The `RTO5c10` post-sync cases drive `nosync_handleObjectSyncProtocolMessage`; the spec's
/// `build_object_sync_message(channel, channelSerial, …)` channel argument (e.g. `"test"`) has no
/// counterpart because ``InternalDefaultRealtimeObjects`` is already scoped to a single channel.
@Suite(.serialized)
final class ParentReferencesTests: UTSTestCase {

    // MARK: - RTLO3f2 — initialized empty

    // UTS: objects/unit/RTLO3f2/init-empty-counter-0
    @Test
    func test_RTLO3f2_parentReferences_empty_on_counter() {
        let counter = makeCounter(objectID: "counter:abc@1000")
        #expect(counter.parentReferences == [:])
    }

    // UTS: objects/unit/RTLO3f2/init-empty-map-0
    @Test
    func test_RTLO3f2_parentReferences_empty_on_map() {
        let map = makeMap(objectID: "map:abc@1000")
        #expect(map.parentReferences == [:])
    }

    // MARK: - RTLO4g — addParentReference

    // UTS: objects/unit/RTLO4g2/first-reference-new-entry-0
    @Test
    func test_RTLO4g2_first_reference_creates_new_entry() {
        let child = makeCounter(objectID: "counter:child@1000")
        let parent = makeMap(objectID: "map:parent@1000")

        child.addParentReference(parent, key: "score")

        #expect(child.parentReferences["map:parent@1000"] == ["score"])
    }

    // UTS: objects/unit/RTLO4g1/second-key-same-parent-0
    @Test
    func test_RTLO4g1_second_key_added_to_existing_entry() {
        let child = makeCounter(objectID: "counter:child@1000")
        let parent = makeMap(objectID: "map:parent@1000")
        child.parentReferences = ["map:parent@1000": ["score"]]

        child.addParentReference(parent, key: "points")

        #expect(child.parentReferences["map:parent@1000"] == ["score", "points"])
    }

    // UTS: objects/unit/RTLO4g/different-parent-separate-entry-0
    @Test
    func test_RTLO4g_different_parent_creates_separate_entry() {
        let child = makeCounter(objectID: "counter:child@1000")
        let parentA = makeMap(objectID: "map:a@1000")
        let parentB = makeMap(objectID: "map:b@1000")

        child.addParentReference(parentA, key: "x")
        child.addParentReference(parentB, key: "y")

        #expect(child.parentReferences["map:a@1000"] == ["x"])
        #expect(child.parentReferences["map:b@1000"] == ["y"])
    }

    // UTS: objects/unit/RTLO4g/multiple-parents-multiple-keys-0
    @Test
    func test_RTLO4g_multiple_parents_multiple_keys() {
        let child = makeCounter(objectID: "counter:child@1000")
        let parentA = makeMap(objectID: "map:a@1000")
        let parentB = makeMap(objectID: "map:b@1000")

        child.addParentReference(parentA, key: "x")
        child.addParentReference(parentA, key: "y")
        child.addParentReference(parentB, key: "p")
        child.addParentReference(parentB, key: "q")

        #expect(child.parentReferences["map:a@1000"] == ["x", "y"])
        #expect(child.parentReferences["map:b@1000"] == ["p", "q"])
    }

    // MARK: - RTLO4h — removeParentReference

    // UTS: objects/unit/RTLO4h1/nonexistent-parent-noop-0
    @Test
    func test_RTLO4h1_remove_nonexistent_parent_is_noop() {
        let child = makeCounter(objectID: "counter:child@1000")
        let parent = makeMap(objectID: "map:parent@1000")

        child.removeParentReference(parent, key: "score")

        #expect(child.parentReferences == [:])
    }

    // UTS: objects/unit/RTLO4h2/remove-key-leaves-others-0
    @Test
    func test_RTLO4h2_remove_key_leaves_other_keys() {
        let child = makeCounter(objectID: "counter:child@1000")
        let parent = makeMap(objectID: "map:parent@1000")
        child.parentReferences = ["map:parent@1000": ["score", "points"]]

        child.removeParentReference(parent, key: "score")

        #expect(child.parentReferences["map:parent@1000"] == ["points"])
    }

    // UTS: objects/unit/RTLO4h3/remove-last-key-removes-entry-0
    @Test
    func test_RTLO4h3_remove_last_key_removes_entry() {
        let child = makeCounter(objectID: "counter:child@1000")
        let parent = makeMap(objectID: "map:parent@1000")
        child.parentReferences = ["map:parent@1000": ["score"]]

        child.removeParentReference(parent, key: "score")

        #expect(child.parentReferences["map:parent@1000"] == nil)
        #expect(child.parentReferences == [:])
    }

    // UTS: objects/unit/RTLO4h/remove-nonexistent-key-0
    @Test
    func test_RTLO4h_remove_nonexistent_key_leaves_existing() {
        let child = makeCounter(objectID: "counter:child@1000")
        let parent = makeMap(objectID: "map:parent@1000")
        child.parentReferences = ["map:parent@1000": ["score"]]

        child.removeParentReference(parent, key: "nonexistent")

        #expect(child.parentReferences["map:parent@1000"] == ["score"])
    }

    // MARK: - RTLO4f — getFullPaths

    // UTS: objects/unit/RTLO4f2/root-returns-empty-path-0
    @Test
    func test_RTLO4f2_root_returns_empty_key_path() {
        let pool = makePool()
        let root = pool.root

        let paths = root.getFullPaths()
        #expect(paths.count == 1)
        #expect(paths.contains([]))
    }

    // UTS: objects/unit/RTLO4f/direct-child-single-path-0
    @Test
    func test_RTLO4f_direct_child_of_root_single_path() {
        var pool = makePool()
        let counter = makeCounter(objectID: "counter:score@1000")
        pool.testsOnly_setLiveCounter(counter, forObjectID: "counter:score@1000")

        counter.addParentReference(pool.root, key: "score")

        let paths = counter.getFullPaths()
        #expect(paths.count == 1)
        #expect(paths.contains(["score"]))
    }

    // UTS: objects/unit/RTLO4f/deep-nesting-0
    @Test
    func test_RTLO4f_deeply_nested_object() {
        var pool = makePool()
        let profile = makeMap(objectID: "map:profile@1000")
        pool.testsOnly_setLiveMap(profile, forObjectID: "map:profile@1000")
        profile.addParentReference(pool.root, key: "profile")

        let prefs = makeMap(objectID: "map:prefs@1000")
        pool.testsOnly_setLiveMap(prefs, forObjectID: "map:prefs@1000")
        prefs.addParentReference(profile, key: "prefs")

        let themeCounter = makeCounter(objectID: "counter:theme@1000")
        pool.testsOnly_setLiveCounter(themeCounter, forObjectID: "counter:theme@1000")
        themeCounter.addParentReference(prefs, key: "theme_counter")

        let paths = themeCounter.getFullPaths()
        #expect(paths.count == 1)
        #expect(paths.contains(["profile", "prefs", "theme_counter"]))
    }

    // UTS: objects/unit/RTLO4f/diamond-graph-0
    @Test
    func test_RTLO4f_diamond_graph_multiple_parents() {
        var pool = makePool()
        let mapA = makeMap(objectID: "map:a@1000")
        pool.testsOnly_setLiveMap(mapA, forObjectID: "map:a@1000")
        mapA.addParentReference(pool.root, key: "a")

        let mapB = makeMap(objectID: "map:b@1000")
        pool.testsOnly_setLiveMap(mapB, forObjectID: "map:b@1000")
        mapB.addParentReference(pool.root, key: "b")

        let leaf = makeCounter(objectID: "counter:leaf@1000")
        pool.testsOnly_setLiveCounter(leaf, forObjectID: "counter:leaf@1000")
        leaf.addParentReference(mapA, key: "x")
        leaf.addParentReference(mapB, key: "y")

        let paths = leaf.getFullPaths()
        #expect(paths.count == 2)
        #expect(paths.contains(["a", "x"]))
        #expect(paths.contains(["b", "y"]))
    }

    // UTS: objects/unit/RTLO4f/single-parent-multiple-keys-0
    @Test
    func test_RTLO4f_single_parent_multiple_keys() {
        var pool = makePool()
        let child = makeCounter(objectID: "counter:child@1000")
        pool.testsOnly_setLiveCounter(child, forObjectID: "counter:child@1000")
        child.addParentReference(pool.root, key: "primary")
        child.addParentReference(pool.root, key: "alias")

        let paths = child.getFullPaths()
        #expect(paths.count == 2)
        #expect(paths.contains(["primary"]))
        #expect(paths.contains(["alias"]))
    }

    // UTS: objects/unit/RTLO4f/orphan-returns-empty-0
    @Test
    func test_RTLO4f_orphan_returns_empty_list() {
        var pool = makePool()
        let orphan = makeCounter(objectID: "counter:orphan@1000")
        pool.testsOnly_setLiveCounter(orphan, forObjectID: "counter:orphan@1000")

        #expect(orphan.getFullPaths().isEmpty)
    }

    // UTS: objects/unit/RTLO4f/cycle-suppression-0
    @Test
    func test_RTLO4f_suppresses_cycles() {
        var pool = makePool()
        let mapA = makeMap(objectID: "map:a@1000")
        pool.testsOnly_setLiveMap(mapA, forObjectID: "map:a@1000")
        mapA.addParentReference(pool.root, key: "a")

        let mapB = makeMap(objectID: "map:b@1000")
        pool.testsOnly_setLiveMap(mapB, forObjectID: "map:b@1000")
        mapB.addParentReference(mapA, key: "b")

        // Introduce a cycle: map:A also has map:B as a parent.
        mapA.addParentReference(mapB, key: "a")

        let pathsB = mapB.getFullPaths()
        #expect(pathsB.count == 1)
        #expect(pathsB.contains(["a", "b"]))

        let pathsA = mapA.getFullPaths()
        #expect(pathsA.count == 1)
        #expect(pathsA.contains(["a"]))
    }

    // UTS: objects/unit/RTLO4f/complex-diamond-deep-0
    @Test
    func test_RTLO4f_complex_diamond_with_deep_nesting() {
        var pool = makePool()
        let mapL = makeMap(objectID: "map:l@1000")
        pool.testsOnly_setLiveMap(mapL, forObjectID: "map:l@1000")
        mapL.addParentReference(pool.root, key: "left")

        let mapR = makeMap(objectID: "map:r@1000")
        pool.testsOnly_setLiveMap(mapR, forObjectID: "map:r@1000")
        mapR.addParentReference(pool.root, key: "right")

        let mapM = makeMap(objectID: "map:m@1000")
        pool.testsOnly_setLiveMap(mapM, forObjectID: "map:m@1000")
        mapM.addParentReference(mapL, key: "mid")

        let target = makeCounter(objectID: "counter:t@1000")
        pool.testsOnly_setLiveCounter(target, forObjectID: "counter:t@1000")
        target.addParentReference(mapM, key: "target")
        target.addParentReference(mapR, key: "target")

        let paths = target.getFullPaths()
        #expect(paths.count == 2)
        #expect(paths.contains(["left", "mid", "target"]))
        #expect(paths.contains(["right", "target"]))
    }

    // MARK: - RTO5c10 — post-sync rebuild

    // UTS: objects/unit/RTO5c10/rebuild-from-sync-0
    @Test
    func test_RTO5c10_post_sync_rebuild_populates_parentReferences() {
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
                            entries: StandardTestPool.mapEntries([
                                "nested": StandardTestPool.data(objectId: "counter:nested@1000"),
                            ]),
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

        #expect(realtimeObjects.testsOnly_objectsSyncState == .synced)
        let pool = realtimeObjects.testsOnly_objectsPool
        #expect(pool.entries["counter:score@1000"]?.counterValue?.parentReferences["root"] == ["score"])
        #expect(pool.entries["map:profile@1000"]?.mapValue?.parentReferences["root"] == ["profile"])
        #expect(pool.entries["counter:nested@1000"]?.counterValue?.parentReferences["map:profile@1000"] == ["nested"])
        #expect(pool.root.parentReferences == [:])
        #expect(pool.entries["counter:score@1000"]?.counterValue?.getFullPaths().contains(["score"]) == true)
        #expect(pool.entries["counter:nested@1000"]?.counterValue?.getFullPaths().contains(["profile", "nested"]) == true)
    }

    // UTS: objects/unit/RTO5c10a/rebuild-clears-stale-refs-0
    @Test
    func test_RTO5c10a_post_sync_rebuild_clears_stale_parentReferences() {
        let realtimeObjects = makeRealtimeObjects()
        // First sync: root --"score"--> counter:abc@1000.
        onQueue {
            realtimeObjects.nosync_onChannelAttached(hasObjects: true)
            realtimeObjects.nosync_handleObjectSyncProtocolMessage(
                objectMessages: [
                    StandardTestPool.objectStateMessage(
                        objectId: "root",
                        siteTimeserials: ["aaa": "t:0"],
                        map: StandardTestPool.objectsMap(
                            semantics: .lww,
                            entries: StandardTestPool.mapEntries(["score": StandardTestPool.data(objectId: "counter:abc@1000")]),
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
        #expect(realtimeObjects.testsOnly_objectsPool.entries["counter:abc@1000"]?.counterValue?.parentReferences["root"] == ["score"])

        // Second sync: root --"points"--> counter:abc@1000 (key changed).
        onQueue {
            realtimeObjects.nosync_onChannelAttached(hasObjects: true)
            realtimeObjects.nosync_handleObjectSyncProtocolMessage(
                objectMessages: [
                    StandardTestPool.objectStateMessage(
                        objectId: "root",
                        siteTimeserials: ["aaa": "t:1"],
                        map: StandardTestPool.objectsMap(
                            semantics: .lww,
                            entries: StandardTestPool.mapEntries(["points": StandardTestPool.data(objectId: "counter:abc@1000")]),
                        ),
                        createOp: StandardTestPool.mapCreateOp(objectId: "root"),
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

        let counter = realtimeObjects.testsOnly_objectsPool.entries["counter:abc@1000"]?.counterValue
        #expect(counter?.parentReferences["root"] == ["points"])
        #expect(counter?.getFullPaths().contains(["points"]) == true)
        #expect(counter?.getFullPaths().count == 1)
    }

    // UTS: objects/unit/RTO5c10/unreferenced-empty-refs-0
    @Test
    func test_RTO5c10_unreferenced_objects_have_empty_parentReferences() {
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
                        objectId: "counter:orphan@1000",
                        siteTimeserials: ["aaa": "t:0"],
                        counter: WireObjectsCounter(count: NSNumber(value: 0)),
                        createOp: StandardTestPool.counterCreateOp(objectId: "counter:orphan@1000", count: 42),
                    ),
                ],
                protocolMessageChannelSerial: "sync1:",
            )
        }

        #expect(realtimeObjects.testsOnly_objectsSyncState == .synced)
        let orphan = realtimeObjects.testsOnly_objectsPool.entries["counter:orphan@1000"]?.counterValue
        #expect(orphan?.parentReferences == [:])
        #expect(orphan?.getFullPaths().isEmpty == true)
    }
}
