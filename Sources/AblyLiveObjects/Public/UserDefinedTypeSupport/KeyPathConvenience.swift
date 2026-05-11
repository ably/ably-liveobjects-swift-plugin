import Foundation
import Ably

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
