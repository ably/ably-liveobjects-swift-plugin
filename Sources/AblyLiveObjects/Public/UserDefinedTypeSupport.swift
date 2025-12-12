import Foundation
import Ably

// MARK: - Public-facing types for shaped LiveMaps

// TODO not sure this actually needs to be a protocol
protocol LiveMapShape {
    // I'm unsure about this but I think that we want something like it so that we can do implicit member access: `.get(key: .topLevelCounter)`. but again it's not clear what this would inherit from. Also we might need this in order to see whether a key is a known key or not. But we may have to have one of these per Value type? e.g. LiveMapStringKey, LiveMapLiveCounterKey etc (no, that falls apart when you start having parameterisable types e.g. nested maps) — Hmm
//    associatedtype LiveMapKey
}

// TODO this name isn't great, it's not really a key, it's a key description (but I guess a KeyPath is not just a "key path")
// This is going to be something described by
protocol LiveMapKey<Shape, Value>: Sendable {
    associatedtype Shape: LiveMapShape
    associatedtype Value
}

struct ShapedLiveMap<Shape: LiveMapShape>: Sendable {
    // TODO this needs a `create()` with constraints

}

// TODO: naming TBD
// TODO: we don't have any constraints on Value which makes things trickier
// TODO: I didn't actually do PrimitivePathObject in the non-typed API; we should have that
protocol TypedPrimitivePathObject<Value> {
    associatedtype Value

    var value: Value? { get }
}

protocol ShapedLiveMapPathObject<Shape> {
    associatedtype Shape: LiveMapShape

    // TODO: we need set, entries etc
    // TODO: what do keys and entries return when it's not a known key?
    // TODO: you should still be able to interact with this without shape too

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

    // TODO: this is a bit ugly; implicit member access would be nice but I'm not sure how that works when you might be fetching from one of various types depending on the value?
    // TODO consider key paths instead of implicit member access
    let topLevelCounter = myChannelPathObject.get(key: MyChannelObject.LiveMapKeys.topLevelCounter)
    let topLevelMap = myChannelPathObject.get(key: MyChannelObject.LiveMapKeys.topLevelMap)

    let nestedEntry = topLevelMap.get(key: MyChannelObject.TopLevelMap.LiveMapKeys.nestedEntry)
    let nestedEntryValue = nestedEntry.value
}

// MARK: - Code that would be generated (for now we're just writing it out)

// These would come from some sort of macro like @LiveMapShape
extension MyChannelObject: LiveMapShape {}
extension MyChannelObject.TopLevelMap: LiveMapShape {}

extension MyChannelObject {
    enum LiveMapKeys {
        static let topLevelCounter: some LiveMapKey<MyChannelObject, LiveCounter> = DefaultLiveMapKey(rawKey: "topLevelCounter")
        static let topLevelMap: some LiveMapKey<MyChannelObject, ShapedLiveMap<TopLevelMap>> = DefaultLiveMapKey(rawKey: "topLevelCounter")
    }
}

extension MyChannelObject.TopLevelMap {
    enum LiveMapKeys {
        static let nestedEntry: some LiveMapKey<MyChannelObject.TopLevelMap, String> = DefaultLiveMapKey(rawKey: "nestedEntry")
    }
}

// Not exactly clear where this would come from (because we don't really want this to be a public type, so the user would have to create it themselves)
struct DefaultLiveMapKey<Shape: LiveMapShape, Value>: LiveMapKey {
    /// The underlying key to use for fetching this key from a map's entries
    var rawKey: String
}
