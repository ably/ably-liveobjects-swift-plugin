import Ably

public typealias EventCallback<T> = @Sendable (_ event: sending T, _ subscription: Subscription) -> Void

/// The callback used for the events emitted by ``RealtimeObjects``.
///
/// - Parameter subscription: An ``OnObjectsEventResponse`` object that allows the provided listener to deregister itself from future updates.
public typealias ObjectsEventCallback = @Sendable (_ subscription: StatusSubscription) -> Void

/// The callback used for the lifecycle events emitted by ``LiveObject``.
/// - Parameter subscription: A ``OnLiveObjectLifecycleEventResponse`` object that allows the provided listener to deregister itself from future updates.
public typealias LiveObjectLifecycleEventCallback = @Sendable (_ subscription: OnLiveObjectLifecycleEventResponse) -> Void

/// Describes the events emitted by an ``RealtimeObjects`` object.
public enum ObjectsEvent: Sendable {
    /// The local copy of Objects on a channel is currently being synchronized with the Ably service.
    case syncing
    /// The local copy of Objects on a channel has been synchronized with the Ably service.
    case synced
}

/// Enables the Objects to be read, modified and subscribed to for a channel.
public protocol RealtimeObject: Sendable {
    func get() async throws(ARTErrorInfo) -> LiveMapPathObject

    /// Registers the provided listener for the specified event. If `on()` is called more than once with the same listener and event, the listener is added multiple times to its listener registry. Therefore, as an example, assuming the same listener is registered twice using `on()`, and an event is emitted once, the listener would be invoked twice.
    ///
    /// - Parameters:
    ///   - event: The named event to listen for.
    ///   - callback: The event listener.
    /// - Returns: An ``OnObjectsEventResponse`` object that allows the provided listener to be deregistered from future updates.
    @discardableResult
    func on(event: ObjectsEvent, callback: @escaping ObjectsEventCallback) -> StatusSubscription

    /// Deregisters all registrations, for all events and listeners.
    func offAll()
}

/// Represents the type of data stored for a given key in a ``LiveMap``.
/// It may be a primitive value (string, number, boolean, binary data, JSON array, or JSON object), or another ``LiveObject``.
///
/// `Value` implements Swift's `ExpressibleBy*Literal` protocols. This, in combination with `JSONValue`'s conformance to these protocols, allows you to write type-safe map values using familiar syntax. For example:
///
/// ```swift
/// let map = try await channel.objects.createMap(entries: [
///     "someStringKey": "someString",
///     "someIntegerKey": 123,
///     "someFloatKey": 123.456,
///     "someTrueKey": true,
///     "someFalseKey": false,
///     "someJSONObjectKey": [
///         "someNestedJSONObjectKey": [
///             "someOtherKey": "someOtherValue",
///         ],
///     ],
///     "someJSONArrayKey": [
///         "foo",
///         42,
///     ],
/// ])
/// ```
public enum Value: Sendable {
    case primitive(Primitive)
    case liveMap(LiveMap)
    case liveCounter(LiveCounter)
}

// MARK: - Value ExpressibleBy*Literal conformances

extension Value: ExpressibleByDictionaryLiteral {
    public init(dictionaryLiteral elements: (String, JSONValue)...) {
        self = .primitive(.jsonObject(.init(uniqueKeysWithValues: elements)))
    }
}

extension Value: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: JSONValue...) {
        self = .primitive(.jsonArray(elements))
    }
}

extension Value: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self = .primitive(.string(value))
    }
}

extension Value: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int) {
        self = .primitive(.number(Double(value)))
    }
}

extension Value: ExpressibleByFloatLiteral {
    public init(floatLiteral value: Double) {
        self = .primitive(.number(value))
    }
}

extension Value: ExpressibleByBooleanLiteral {
    public init(booleanLiteral value: Bool) {
        self = .primitive(.bool(value))
    }
}

/// Object returned from an `on` call, allowing the listener provided in that call to be deregistered.
public protocol StatusSubscription: Sendable {
    /// Deregisters the listener passed to the `on` call.
    func off()
}

public protocol PathObjectBase: AnyObject, Sendable {
    var path: String { get }

    @discardableResult
    func subscribe(listener: @escaping EventCallback<PathObjectSubscriptionEvent>, options: PathObjectSubscriptionOptions?) throws(ARTErrorInfo) -> Subscription
}

public protocol PathObject: PathObjectBase, PathObjectCollectionMethods {
    func get(key: String) -> PathObject

    var asLiveMap: LiveMapPathObject { get }
    var asLiveCounter: LiveCounterPathObject { get }

    var value: Primitive? { get }
    var instance: Instance? { get }

    func compact() -> CompactedValue?
}

public protocol PathObjectCollectionMethods {
    func at(path: String) -> PathObject
}

public protocol LiveMapPathObject: PathObjectBase, PathObjectCollectionMethods, LiveMapPathObjectCollectionMethods, LiveMapOperations {
    func get(key: String) -> PathObject

    var instance: LiveMapInstance? { get }

    func compact() -> CompactedValue.ObjectReference?
}

public protocol LiveMapPathObjectCollectionMethods {
    var entries: [(key: String, value: PathObject)] { get }

    var keys: [String] { get }
    var values: [PathObject] { get }

    var size: Int? { get }
}

public protocol LiveMapOperations {
    func set(key: String, value: Value) async throws(ARTErrorInfo)

    func remove(key: String) async throws(ARTErrorInfo)
}

public protocol LiveCounterPathObject: PathObjectBase, LiveCounterOperations {
    var value: Double? { get }

    var instance: LiveCounterInstance? { get }

    func compact() -> Double?
}

public protocol LiveCounterOperations {
    func increment(amount: Double) async throws(ARTErrorInfo)
    func decrement(amount: Double) async throws(ARTErrorInfo)
}

/// Object returned from a `subscribe` call, allowing the listener provided in that call to be deregistered.
public protocol Subscription: Sendable {
    /// Deregisters the listener passed to the `subscribe` call.
    func unsubscribe()
}

/// Object returned from an `on` call, allowing the listener provided in that call to be deregistered.
public protocol OnLiveObjectLifecycleEventResponse: Sendable {
    /// Deregisters the listener passed to the `on` call.
    func off()
}

public protocol InstanceBase: AnyObject, Sendable {
    var id: String? { get }

    @discardableResult
    func subscribe(listener: @escaping EventCallback<InstanceSubscriptionEvent>) throws(ARTErrorInfo) -> Subscription
}

public protocol Instance {
    func get(key: String) -> Instance?

    // These return `nil` if the underlying instance is not of the referenced type.
    var asLiveMap: LiveMapInstance? { get }
    var asLiveCounter: LiveCounterInstance? { get }

    var value: Primitive? { get }

    func compact() -> CompactedValue?
}

public protocol LiveMapInstance: InstanceBase, LiveMapInstanceCollectionMethods, LiveMapOperations {
    func get(key: String) -> Instance?

    func compact() -> CompactedValue.ObjectReference?
}

public protocol LiveMapInstanceCollectionMethods {
    var entries: [(key: String, value: Instance)] { get }

    var keys: [String] { get }
    var values: [Instance] { get }

    var size: Int { get }
}

public protocol LiveCounterInstance: InstanceBase, LiveCounterOperations {
    var value: Double { get }

    func compact() -> Double?
}

public struct LiveMap: Sendable {
    public static func create(initialEntries _: [String: Value]? = nil) -> Self {
        fatalError("Not implemented")
    }
}

public struct LiveCounter: Sendable {
    public static func create(initialCount _: Double = 0) {
        fatalError("Not implemented")
    }
}

public enum Primitive: Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case data(Data)
    case jsonArray([JSONValue])
    case jsonObject([String: JSONValue])

    /// If this `Primitive` has case `string`, this returns the associated value. Else, it returns `nil`.
    public var stringValue: String? {
        if case let .string(value) = self {
            return value
        }
        return nil
    }

    /// If this `Primitive` has case `number`, this returns the associated value. Else, it returns `nil`.
    public var numberValue: Double? {
        if case let .number(value) = self {
            return value
        }
        return nil
    }

    /// If this `Primitive` has case `bool`, this returns the associated value. Else, it returns `nil`.
    public var boolValue: Bool? {
        if case let .bool(value) = self {
            return value
        }
        return nil
    }

    /// If this `Primitive` has case `data`, this returns the associated value. Else, it returns `nil`.
    public var dataValue: Data? {
        if case let .data(value) = self {
            return value
        }
        return nil
    }

    /// If this `Primitive` has case `jsonArray`, this returns the associated value. Else, it returns `nil`.
    public var jsonArrayValue: [JSONValue]? {
        if case let .jsonArray(value) = self {
            return value
        }
        return nil
    }

    /// If this `Primitive` has case `jsonObject`, this returns the associated value. Else, it returns `nil`.
    public var jsonObjectValue: [String: JSONValue]? {
        if case let .jsonObject(value) = self {
            return value
        }
        return nil
    }
}

// MARK: - Primitive ExpressibleBy*Literal conformances

extension Primitive: ExpressibleByDictionaryLiteral {
    public init(dictionaryLiteral elements: (String, JSONValue)...) {
        self = .jsonObject(.init(uniqueKeysWithValues: elements))
    }
}

extension Primitive: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: JSONValue...) {
        self = .jsonArray(elements)
    }
}

extension Primitive: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self = .string(value)
    }
}

extension Primitive: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int) {
        self = .number(Double(value))
    }
}

extension Primitive: ExpressibleByFloatLiteral {
    public init(floatLiteral value: Double) {
        self = .number(value)
    }
}

extension Primitive: ExpressibleByBooleanLiteral {
    public init(booleanLiteral value: Bool) {
        self = .bool(value)
    }
}

public struct PathObjectSubscriptionEvent {
    var object: PathObject
    var message: ObjectMessage?
}

public struct PathObjectSubscriptionOptions {
    var depth: Int?
}

public struct InstanceSubscriptionEvent {
    var object: Instance
    var message: ObjectMessage?
}

public struct ObjectMessage {
    // TODO: fill this in; there's nothing too interesting here (just need to avoid a clash with the internal types with the same name)
}

// A ``JSON``-like value whose `object` and `array` cases may contain cyclical references.
public indirect enum CompactedValue: Sendable {
    case object(ObjectReference)
    case array(ArrayReference)
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    public final class ObjectReference: Sendable {
        public let value: [String: CompactedValue]

        init(value: [String: CompactedValue]) {
            self.value = value
        }
    }

    public final class ArrayReference: Sendable {
        public let value: [CompactedValue]

        init(value: [CompactedValue]) {
            self.value = value
        }
    }

    // MARK: - Convenience getters for associated values

    /// If this `CompactedValue` has case `object`, this returns the associated value. Else, it returns `nil`.
    public var objectValue: ObjectReference? {
        if case let .object(objectValue) = self {
            objectValue
        } else {
            nil
        }
    }

    /// If this `CompactedValue` has case `array`, this returns the associated value. Else, it returns `nil`.
    public var arrayValue: ArrayReference? {
        if case let .array(arrayValue) = self {
            arrayValue
        } else {
            nil
        }
    }

    /// If this `CompactedValue` has case `string`, this returns the associated value. Else, it returns `nil`.
    public var stringValue: String? {
        if case let .string(stringValue) = self {
            stringValue
        } else {
            nil
        }
    }

    /// If this `CompactedValue` has case `number`, this returns the associated value. Else, it returns `nil`.
    public var numberValue: Double? {
        if case let .number(numberValue) = self {
            numberValue
        } else {
            nil
        }
    }

    /// If this `CompactedValue` has case `bool`, this returns the associated value. Else, it returns `nil`.
    public var boolValue: Bool? {
        if case let .bool(boolValue) = self {
            boolValue
        } else {
            nil
        }
    }

    /// Returns true if and only if this `CompactedValue` has case `null`.
    public var isNull: Bool {
        if case .null = self {
            true
        } else {
            false
        }
    }
}

// TODO: Update for new API (also note that JS now has a similar one with AsyncIterableIterator
/*
 // MARK: - AsyncSequence Extensions

 /// Extension to provide AsyncSequence-based subscription for `LiveObject` updates.
 public extension LiveObject {
     /// Returns an `AsyncSequence` that emits updates to this `LiveObject`.
     ///
     /// This provides an alternative to the callback-based ``subscribe(listener:)`` method,
     /// allowing you to use Swift's structured concurrency features like `for await` loops.
     ///
     /// - Returns: An AsyncSequence that emits ``Update`` values when the object is updated.
     /// - Throws: An ``ARTErrorInfo`` if the subscription fails.
     func updates() throws(ARTErrorInfo) -> AsyncStream<Update> {
         let (stream, continuation) = AsyncStream.makeStream(of: Update.self)

         let subscription = try subscribe { update, _ in
             continuation.yield(update)
         }

         continuation.onTermination = { _ in
             subscription.unsubscribe()
         }

         return stream
     }
 }
 */
