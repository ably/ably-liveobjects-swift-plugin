import Foundation
import Ably

// MARK: - Public-facing types for shaped LiveMaps

// TODO assess how much LiveMapShape needs to be able to do, and if it's just a convenience, then remove some constraints

// TODO not sure this actually needs to be a protocol
protocol LiveMapShape {
    // I'm unsure about this but I think that we want something like it so that we can do implicit member access: `.get(key: .topLevelCounter)`. but again it's not clear what this would inherit from. Also we might need this in order to see whether a key is a known key or not. But we may have to have one of these per Value type? e.g. LiveMapStringKey, LiveMapLiveCounterKey etc (no, that falls apart when you start having parameterisable types e.g. nested maps) — Hmm. I think that `entries` might just not be possible because there's no obvious type to define. In that case we _would_ have to do codegen and list all of the possible types. we can still have a LiveMapEntry type here I guess

    // TODO: currently this is _only_ used for the convenience extension that allows key path lookups to make things neater
    associatedtype LiveMapKeys

    /// An entry that can be passed to `ShapedLiveMap.create()`.
    associatedtype InitialEntry: LiveMapInitialEntry
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

protocol ShapedLiveMapPathObject<Shape> {
    associatedtype Shape: LiveMapShape

    // TODO: we need keys and entries (what does entries return, and how do they both handle an unknown key?). I think that perhaps `keys` could just return [String], and that the LiveMapShape will need to define a Entry associated type (most likely an enum in practice) that can create itself from a given key and PathObject (or fail to do so in which case we'll have to return some "unknown" type)
    // TODO: you should still be able to interact with this without shape too — I think the best thing would be to make _this_ type only work with Key but have a way to turn it into a normal LiveMapPathObject

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

// Convenience extensions for specifying a key by using a key path into a static member of Shape.LiveMapKeys. TODO improve naming: it's a bit confusing because it's a key path _into a set of keys_ (i.e. not into the shape itself). The reason we use key paths instead of implicit member access is because it doesn't require that the "member" actually have that type
extension ShapedLiveMapPathObject {
    // `set()`

    func set<Key: LiveMapKey>(keyAt keyPath: KeyPath<Shape.LiveMapKeys.Type, Key>, value: String) async throws(ARTErrorInfo) where Key.Shape == Shape, Key.Value == String {
        try await set(key: Shape.LiveMapKeys.self[keyPath: keyPath], value: value)
    }

    func set<Key: LiveMapKey>(keyAt keyPath: KeyPath<Shape.LiveMapKeys.Type, Key>, value: Double) async throws(ARTErrorInfo) where Key.Shape == Shape, Key.Value == Double {
        try await set(key: Shape.LiveMapKeys.self[keyPath: keyPath], value: value)
    }

    func set<Key: LiveMapKey>(keyAt keyPath: KeyPath<Shape.LiveMapKeys.Type, Key>, value: Bool) async throws(ARTErrorInfo) where Key.Shape == Shape, Key.Value == Bool {
        try await set(key: Shape.LiveMapKeys.self[keyPath: keyPath], value: value)
    }

    func set<Key: LiveMapKey>(keyAt keyPath: KeyPath<Shape.LiveMapKeys.Type, Key>, value: Data) async throws(ARTErrorInfo) where Key.Shape == Shape, Key.Value == Data {
        try await set(key: Shape.LiveMapKeys.self[keyPath: keyPath], value: value)
    }

    func set<Key: LiveMapKey>(keyAt keyPath: KeyPath<Shape.LiveMapKeys.Type, Key>, value: [JSONValue]) async throws(ARTErrorInfo) where Key.Shape == Shape, Key.Value == JSONValue {
        try await set(key: Shape.LiveMapKeys.self[keyPath: keyPath], value: value)
    }

    func set<Key: LiveMapKey>(keyAt keyPath: KeyPath<Shape.LiveMapKeys.Type, Key>, value: [String: JSONValue]) async throws(ARTErrorInfo) where Key.Shape == Shape, Key.Value == [String: JSONValue] {
        try await set(key: Shape.LiveMapKeys.self[keyPath: keyPath], value: value)
    }

    func set<Key: LiveMapKey>(keyAt keyPath: KeyPath<Shape.LiveMapKeys.Type, Key>, value: LiveMap) async throws(ARTErrorInfo) where Key.Shape == Shape, Key.Value == LiveMap {
        try await set(key: Shape.LiveMapKeys.self[keyPath: keyPath], value: value)
    }

    func set<Key: LiveMapKey, EntryShape: LiveMapShape>(keyAt keyPath: KeyPath<Shape.LiveMapKeys.Type, Key>, value: ShapedLiveMap<EntryShape>) async throws(ARTErrorInfo) where Key.Shape == Shape, Key.Value == ShapedLiveMap<EntryShape> {
        try await set(key: Shape.LiveMapKeys.self[keyPath: keyPath], value: value)
    }

    func set<Key: LiveMapKey>(keyAt keyPath: KeyPath<Shape.LiveMapKeys.Type, Key>, value: LiveCounter) async throws(ARTErrorInfo) where Key.Shape == Shape, Key.Value == LiveCounter {
        try await set(key: Shape.LiveMapKeys.self[keyPath: keyPath], value: value)
    }

    // `remove()`

    func remove<Key: LiveMapKey>(keyAt keyPath: KeyPath<Shape.LiveMapKeys.Type, Key>) async throws(ARTErrorInfo) where Key.Shape == Shape {
        try await remove(key: Shape.LiveMapKeys.self[keyPath: keyPath])
    }

    // `get()`

    func get<Key: LiveMapKey>(keyAt keyPath: KeyPath<Shape.LiveMapKeys.Type, Key>) -> any TypedPrimitivePathObject<String> where Key.Shape == Shape, Key.Value == String {
        get(key: Shape.LiveMapKeys.self[keyPath: keyPath])
    }

    func get<Key: LiveMapKey>(keyAt keyPath: KeyPath<Shape.LiveMapKeys.Type, Key>) -> any TypedPrimitivePathObject<Double> where Key.Shape == Shape, Key.Value == Double {
        get(key: Shape.LiveMapKeys.self[keyPath: keyPath])
    }

    func get<Key: LiveMapKey>(keyAt keyPath: KeyPath<Shape.LiveMapKeys.Type, Key>) -> any TypedPrimitivePathObject<Bool> where Key.Shape == Shape, Key.Value == Bool {
        get(key: Shape.LiveMapKeys.self[keyPath: keyPath])
    }

    func get<Key: LiveMapKey>(keyAt keyPath: KeyPath<Shape.LiveMapKeys.Type, Key>) -> any TypedPrimitivePathObject<Data> where Key.Shape == Shape, Key.Value == Data {
        get(key: Shape.LiveMapKeys.self[keyPath: keyPath])
    }

    func get<Key: LiveMapKey>(keyAt keyPath: KeyPath<Shape.LiveMapKeys.Type, Key>) -> any TypedPrimitivePathObject<[JSONValue]> where Key.Shape == Shape, Key.Value == [JSONValue] {
        get(key: Shape.LiveMapKeys.self[keyPath: keyPath])
    }

    func get<Key: LiveMapKey>(keyAt keyPath: KeyPath<Shape.LiveMapKeys.Type, Key>) -> LiveMapPathObject where Key.Shape == Shape, Key.Value == LiveMap {
        get(key: Shape.LiveMapKeys.self[keyPath: keyPath])

    }

    func get<Key: LiveMapKey, EntryShape: LiveMapShape>(keyAt keyPath: KeyPath<Shape.LiveMapKeys.Type, Key>) -> any ShapedLiveMapPathObject<EntryShape> where Key.Shape == Shape, Key.Value == ShapedLiveMap<EntryShape> {
        get(key: Shape.LiveMapKeys.self[keyPath: keyPath])
    }

    func get<Key: LiveMapKey>(keyAt keyPath: KeyPath<Shape.LiveMapKeys.Type, Key>) -> LiveCounterPathObject where Key.Shape == Shape, Key.Value == LiveCounter {
        get(key: Shape.LiveMapKeys.self[keyPath: keyPath])
    }
}

// MARK: - RealtimeObject `get` implementation for shaped LiveMaps

extension RealtimeObject {
    func get<Shape: LiveMapShape>(withShape shape: Shape.Type = Shape.self) async throws(ARTErrorInfo) -> any ShapedLiveMapPathObject<Shape> {
        // TODO
        fatalError("Not implemented")
    }
}

// MARK: - Example

struct MyChannelObject {
    var topLevelCounter: LiveCounter
    var topLevelMap: ShapedLiveMap<TopLevelMap>

    struct TopLevelMap {
        var nestedEntry: String
    }
}

func exampleWithChannel(_ channel: ARTRealtimeChannel) async throws {
    // Note that we can't say `.get<MyChannelObject>()` like in TypeScript; gives us "Cannot explicitly specialize instance method 'get()'"
    let myChannelPathObject = try await channel.object.get(withShape: MyChannelObject.self)

    // Note that fetching the keys is verbose; see the next example with key paths
    let topLevelCounter = myChannelPathObject.get(key: MyChannelObject.LiveMapKeys.topLevelCounter)
    let topLevelMap = myChannelPathObject.get(key: MyChannelObject.LiveMapKeys.topLevelMap)

    let nestedEntry = topLevelMap.get(key: MyChannelObject.TopLevelMap.LiveMapKeys.nestedEntry)
}

// Example that uses the key paths convenience methods for get(), set(), remove()
func keyPathsExampleWithChannel(_ channel: ARTRealtimeChannel) async throws {
    let myChannelPathObject = try await channel.object.get(withShape: MyChannelObject.self)

    let topLevelCounter = myChannelPathObject.get(keyAt: \.topLevelCounter)
    let topLevelMap = myChannelPathObject.get(keyAt: \.topLevelMap)

    let nestedEntry = topLevelMap.get(keyAt: \.nestedEntry)

    try await topLevelMap.set(keyAt: \.nestedEntry, value: "Hello")
    try await topLevelMap.remove(keyAt: \.nestedEntry)

    try await myChannelPathObject.set(keyAt: \.topLevelCounter, value: LiveCounter.create(initialCount: 3))
    try await topLevelCounter.increment(amount: 4)

    try await myChannelPathObject.set(
        keyAt: \.topLevelMap,
        value: .create(
            // TODO not decided if this is the API I want yet (that is, `Entry` being an enum); see the other places where I need entries and figure it out
            initialEntries: [
                .nestedEntry("Goodbye")
            ]
        )
    )
}


// MARK: - Code that would be generated (for now we're just writing it out)

// These would come from some sort of macro like @LiveMapShape applied to MyChannelObject

extension MyChannelObject: LiveMapShape {
    enum LiveMapKeys {
        private struct Key<Value>: LiveMapKey {
            typealias Shape = MyChannelObject

            /// The underlying key to use for fetching this key from a map's entries
            var rawKey: String
        }

        static let topLevelCounter: some LiveMapKey<MyChannelObject, LiveCounter> = Key(rawKey: "topLevelCounter")
        static let topLevelMap: some LiveMapKey<MyChannelObject, ShapedLiveMap<TopLevelMap>> = Key(rawKey: "topLevelCounter")
    }

    enum InitialEntry: LiveMapInitialEntry {
        case topLevelCounter(LiveCounter)
        case topLevelMap(ShapedLiveMap<TopLevelMap>)

        // TODO: this might be a bit tricky for codegen as-is, because ideally we wouldn't have to understand the meaning of the shape's properties; we just want to copy and paste their types. Might be better to have an init(containerCreationValue:) on Value, overloaded for all of the supported types. Although according to ChatGPT you can perform full type resolution inside a macro expansion now: https://chatgpt.com/c/693c6ec0-32d0-8333-8776-1145397c263f

        var toKeyValuePair: (String, Value) {
            switch self {
            case .topLevelCounter(let liveCounter):
                ("topLevelCounter", .liveCounter(liveCounter))
            case .topLevelMap(let shapedLiveMap):
                ("topLevelMap", .liveMap(shapedLiveMap.toLiveMap))
            }
        }
    }
}

extension MyChannelObject.TopLevelMap: LiveMapShape {
    enum LiveMapKeys {
        private struct Key<Value>: LiveMapKey {
            typealias Shape = MyChannelObject.TopLevelMap

            /// The underlying key to use for fetching this key from a map's entries
            var rawKey: String
        }

        static let nestedEntry: some LiveMapKey<MyChannelObject.TopLevelMap, String> = Key(rawKey: "nestedEntry")
    }

    enum InitialEntry: LiveMapInitialEntry {
        case nestedEntry(String)

        var toKeyValuePair: (String, Value) {
            switch self {
            case .nestedEntry(let string):
                ("nestedEntry", .primitive(.string(string)))
            }
        }
    }
}

// Note that each `LiveMapKeys` declares their own `Key` type — this is so that we don't have to pollute the library's public types with something that's only used for generated code; i.e. else we'd have to have something like the following:

/*
struct DefaultLiveMapKey<Shape: LiveMapShape, Value>: LiveMapKey {
    var rawKey: String
}
*/
