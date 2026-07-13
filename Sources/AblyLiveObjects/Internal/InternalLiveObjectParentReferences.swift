/// The parent-reference tracking that a `LiveObject` maintains so that its full key-paths from root
/// can be resolved (`RTLO3f`, `RTLO4f`, `RTLO4g`, `RTLO4h`).
///
/// > Note: This is the API shape only; the behaviour is not yet implemented in this target, so every
/// > member traps via ``notImplemented()``. The shape is defined here so that the path-based
/// > dispatch and the LiveObjects graph traversal can be built against it.
internal protocol ParentReferencing: AnyObject {
    /// Tracks which `InternalLiveMap`s currently reference this `LiveObject`, and at which keys, keyed
    /// by the parent's `objectId`. Set to an empty map when the `LiveObject` is initialized (RTLO3f2).
    /// Spec: `RTLO3f`.
    var parentReferences: [String: Set<String>] { get set }

    /// Records that the `InternalLiveMap` `parent` references this `LiveObject` at `key`: adds `key` to
    /// the existing entry for `parent.objectId` (RTLO4g1), or inserts a new entry `{parent.objectId:
    /// {key}}` (RTLO4g2).
    /// Spec: `RTLO4g`.
    func addParentReference(_ parent: InternalDefaultLiveMap, key: String)

    /// Removes the recorded reference from `parent` at `key`: no-op if there is no entry for
    /// `parent.objectId` (RTLO4h1); otherwise removes `key` from the entry's set (RTLO4h2), and drops
    /// the entry entirely if its set becomes empty (RTLO4h3).
    /// Spec: `RTLO4h`.
    func removeParentReference(_ parent: InternalDefaultLiveMap, key: String)

    /// Returns every key-path from the root `InternalLiveMap` to this `LiveObject` — one per simple
    /// path through the parent-reference graph (RTLO4f2), each appearing once, order unspecified
    /// (RTLO4f3). Root itself yields the single empty key-path `[]`; an unreachable object yields `[]`.
    /// Spec: `RTLO4f`.
    func getFullPaths() -> [[String]]
}

internal extension ParentReferencing {
    var parentReferences: [String: Set<String>] {
        get { notImplemented() }
        set {
            _ = newValue
            notImplemented()
        }
    }

    func addParentReference(_ parent: InternalDefaultLiveMap, key: String) {
        _ = (parent, key)
        notImplemented()
    }

    func removeParentReference(_ parent: InternalDefaultLiveMap, key: String) {
        _ = (parent, key)
        notImplemented()
    }

    func getFullPaths() -> [[String]] {
        notImplemented()
    }
}

extension InternalDefaultLiveCounter: ParentReferencing {}

extension InternalDefaultLiveMap: ParentReferencing {}
