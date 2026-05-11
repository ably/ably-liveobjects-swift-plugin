import Foundation
import Ably

// MARK: - Public-facing types for shaped LiveMaps

// TODO assess how much LiveMapShape needs to be able to do, and if it's just a convenience, then remove some constraints

// TODO not sure this actually needs to be a protocol
protocol LiveMapShape {
    // I'm unsure about this but I think that we want something like it so that we can do implicit member access: `.get(key: .topLevelCounter)`. but again it's not clear what this would inherit from. Also we might need this in order to see whether a key is a known key or not. But we may have to have one of these per Value type? e.g. LiveMapStringKey, LiveMapLiveCounterKey etc (no, that falls apart when you start having parameterisable types e.g. nested maps) — Hmm. I think that `entries` might just not be possible because there's no obvious type to define. In that case we _would_ have to do codegen and list all of the possible types. we can still have a LiveMapEntry type here I guess

    // TODO: currently this is _only_ used for the convenience extension that allows key path lookups to make things neater
    associatedtype LiveMapKeys

    /// An entry that can be passed to `ShapedLiveMap.create()`.
    associatedtype InitialEntry: LiveMapInitialEntry

    /// An entry that can be returned from `ShapedLiveMapPathObject.entries()`.
    associatedtype PathObjectKnownEntry: LiveMapPathObjectKnownEntry
}

// TODO this name isn't great, it's not really a key, it's a key description (but I guess a KeyPath is not just a "key path")
protocol LiveMapKey<Shape, Value>: Sendable {
    associatedtype Shape: LiveMapShape
    associatedtype Value
}

protocol LiveMapInitialEntry {
    /// A key-value pair to use when creating the LiveMap.
    var toKeyValuePair: (String, Value) { get }
}

protocol LiveMapPathObjectKnownEntry {
    /// Should return `nil` if the key does not correspond to a known entry.
    init?(key: String, pathObject: PathObject)
}

struct ShapedLiveMap<Shape: LiveMapShape>: Sendable {
    private let liveMap: LiveMap

    public static func create(initialEntries: [Shape.InitialEntry] = []) -> Self {
        // TODO: There's a mismatch here between this using an array and LiveMap using a dictionary
        let liveMap = LiveMap.create(initialEntries: .init(uniqueKeysWithValues: initialEntries.map(\.toKeyValuePair)))
        return .init(liveMap: liveMap)
    }

    // TODO: we don't _really_ want this to have to be public

    /// A type-erased representation of this ShapedLiveMap.
    public var toLiveMap: LiveMap {
        return liveMap
    }
}

// TODO: naming TBD
// TODO: we don't have any constraints on Value which makes things trickier
// TODO: I didn't actually do PrimitivePathObject in the non-typed API; we should have that
protocol TypedPrimitivePathObject<Value> {
    associatedtype Value

    var value: Value? { get }
}

// TODO: How is Instance going to work? is it actually going to check types? if so will it do it all the way down through nested maps etc?

/// An element of `ShapedLiveMapPathObject.entries`.
enum ShapedLiveMapPathObjectEntry<Known> {
    /// A known key-value pair.
    case known(Known)

    /// An unknown key-value pair; the best we can do is return a String key and an untyped PathObject.
    case unknown(key: String, value: PathObject)
}

protocol ShapedLiveMapPathObject<Shape> {
    associatedtype Shape: LiveMapShape

    // This is my proposal for `entries`; I think its return value should be consistent with `keys` and `values`; that is, it should be able to represent things that were found at runtime even when they aren't in the known set of keys.
    var entries: [ShapedLiveMapPathObjectEntry<Shape.PathObjectKnownEntry>] { get }

    // I think that we'll just keep `keys` and `values` as String and PathObject (same as LiveMapPathObject), given that shapes only matter when considering the relationship between a key and a value
    var keys: [String] { get }
    var values: [PathObject] { get }

    // TODO: you should still be able to interact with this without shape too — I think the best thing would be to make _this_ type only work with Key but have a way to turn it into a normal LiveMapPathObject

    // Variants of `set()`

    // All the set() operations that this needs to be able to support. (I don't think we can do better than this because this type isn't expected to be able to handle arbitrary values, even if a user can form a Key that has one; that is, we can't just have a single one that takes Key.Value); unless we end up being able to impose constraints on Key.Value somehow but I don't really want to start adding extensions to String etc

    // For entries of each of the primitive types
    func set<Key: LiveMapKey>(key: Key, value: String) async throws(ARTErrorInfo) where Key.Shape == Shape, Key.Value == String
    func set<Key: LiveMapKey>(key: Key, value: Double) async throws(ARTErrorInfo) where Key.Shape == Shape, Key.Value == Double
    func set<Key: LiveMapKey>(key: Key, value: Bool) async throws(ARTErrorInfo) where Key.Shape == Shape, Key.Value == Bool
    func set<Key: LiveMapKey>(key: Key, value: Data) async throws(ARTErrorInfo) where Key.Shape == Shape, Key.Value == Data
    func set<Key: LiveMapKey>(key: Key, value: [JSONValue]) async throws(ARTErrorInfo) where Key.Shape == Shape, Key.Value == JSONValue
    func set<Key: LiveMapKey>(key: Key, value: [String: JSONValue]) async throws(ARTErrorInfo) where Key.Shape == Shape, Key.Value == [String: JSONValue]

    // For LiveMap entries
    func set<Key: LiveMapKey>(key: Key, value: LiveMap) async throws(ARTErrorInfo) where Key.Shape == Shape, Key.Value == LiveMap
    func set<Key: LiveMapKey, EntryShape: LiveMapShape>(key: Key, value: ShapedLiveMap<EntryShape>) async throws(ARTErrorInfo) where Key.Shape == Shape, Key.Value == ShapedLiveMap<EntryShape>

    // For LiveCounter entries
    func set<Key: LiveMapKey>(key: Key, value: LiveCounter) async throws(ARTErrorInfo) where Key.Shape == Shape, Key.Value == LiveCounter

    // `remove()`

    func remove<Key: LiveMapKey>(key: Key) async throws(ARTErrorInfo)

    // Variants of `get()`

    // I don't _think_ there is a less verbose way of figuring out the shape of the PathObject

    // For entries of each of the primitive types
    func get<Key: LiveMapKey>(key: Key) -> any TypedPrimitivePathObject<String> where Key.Shape == Shape, Key.Value == String
    func get<Key: LiveMapKey>(key: Key) -> any TypedPrimitivePathObject<Double> where Key.Shape == Shape, Key.Value == Double
    func get<Key: LiveMapKey>(key: Key) -> any TypedPrimitivePathObject<Bool> where Key.Shape == Shape, Key.Value == Bool
    func get<Key: LiveMapKey>(key: Key) -> any TypedPrimitivePathObject<Data> where Key.Shape == Shape, Key.Value == Data
    func get<Key: LiveMapKey>(key: Key) -> any TypedPrimitivePathObject<[JSONValue]> where Key.Shape == Shape, Key.Value == [JSONValue]
    func get<Key: LiveMapKey>(key: Key) -> any TypedPrimitivePathObject<[String: JSONValue]> where Key.Shape == Shape, Key.Value == [String: JSONValue]

    // For LiveMap entries
    func get<Key: LiveMapKey>(key: Key) -> LiveMapPathObject where Key.Shape == Shape, Key.Value == LiveMap
    func get<Key: LiveMapKey, EntryShape: LiveMapShape>(key: Key) -> any ShapedLiveMapPathObject<EntryShape> where Key.Shape == Shape, Key.Value == ShapedLiveMap<EntryShape>

    // For LiveCounter entries
    func get<Key: LiveMapKey>(key: Key) -> LiveCounterPathObject where Key.Shape == Shape, Key.Value == LiveCounter
}

// MARK: - RealtimeObject `get` implementation for shaped LiveMaps

extension RealtimeObject {
    func get<Shape: LiveMapShape>(withShape shape: Shape.Type = Shape.self) async throws(ARTErrorInfo) -> any ShapedLiveMapPathObject<Shape> {
        // TODO
        fatalError("Not implemented")
    }
}
