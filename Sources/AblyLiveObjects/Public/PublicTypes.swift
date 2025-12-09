import Ably

/// A callback used in ``LiveObject`` to listen for updates to the object.
///
/// - Parameters:
///   - update: The update object describing the changes made to the object.
///   - subscription: A ``SubscribeResponse`` object that allows the provided listener to deregister itself from future updates.
public typealias LiveObjectUpdateCallback<T> = @Sendable (_ update: sending T, _ subscription: Subscription) -> Void

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
/// `LiveMapValue` implements Swift's `ExpressibleBy*Literal` protocols. This, in combination with `JSONValue`'s conformance to these protocols, allows you to write type-safe map values using familiar syntax. For example:
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
public enum LiveMapValue: Sendable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case data(Data)
    case jsonArray([JSONValue])
    case jsonObject([String: JSONValue])
    case liveMap(any LiveMap)
    case liveCounter(any LiveCounter)

    // MARK: - Convenience getters for associated values

    /// If this `LiveMapValue` has case `liveMap`, this returns the associated value. Else, it returns `nil`.
    public var liveMapValue: (any LiveMap)? {
        if case let .liveMap(value) = self {
            return value
        }
        return nil
    }

    /// If this `LiveMapValue` has case `liveCounter`, this returns the associated value. Else, it returns `nil`.
    public var liveCounterValue: (any LiveCounter)? {
        if case let .liveCounter(value) = self {
            return value
        }
        return nil
    }

    /// If this `LiveMapValue` has case `string`, this returns the associated value. Else, it returns `nil`.
    public var stringValue: String? {
        if case let .string(value) = self {
            return value
        }
        return nil
    }

    /// If this `LiveMapValue` has case `number`, this returns the associated value. Else, it returns `nil`.
    public var numberValue: Double? {
        if case let .number(value) = self {
            return value
        }
        return nil
    }

    /// If this `LiveMapValue` has case `bool`, this returns the associated value. Else, it returns `nil`.
    public var boolValue: Bool? {
        if case let .bool(value) = self {
            return value
        }
        return nil
    }

    /// If this `LiveMapValue` has case `data`, this returns the associated value. Else, it returns `nil`.
    public var dataValue: Data? {
        if case let .data(value) = self {
            return value
        }
        return nil
    }

    /// If this `LiveMapValue` has case `jsonArray`, this returns the associated value. Else, it returns `nil`.
    public var jsonArrayValue: [JSONValue]? {
        if case let .jsonArray(value) = self {
            return value
        }
        return nil
    }

    /// If this `LiveMapValue` has case `jsonObject`, this returns the associated value. Else, it returns `nil`.
    public var jsonObjectValue: [String: JSONValue]? {
        if case let .jsonObject(value) = self {
            return value
        }
        return nil
    }

    // MARK: - Equatable Implementation

    public static func == (lhs: LiveMapValue, rhs: LiveMapValue) -> Bool {
        switch (lhs, rhs) {
        case let (.string(lhsValue), .string(rhsValue)):
            lhsValue == rhsValue
        case let (.number(lhsValue), .number(rhsValue)):
            lhsValue == rhsValue
        case let (.bool(lhsValue), .bool(rhsValue)):
            lhsValue == rhsValue
        case let (.data(lhsValue), .data(rhsValue)):
            lhsValue == rhsValue
        case let (.jsonArray(lhsValue), .jsonArray(rhsValue)):
            lhsValue == rhsValue
        case let (.jsonObject(lhsValue), .jsonObject(rhsValue)):
            lhsValue == rhsValue
        case let (.liveMap(lhsMap), .liveMap(rhsMap)):
            lhsMap === rhsMap
        case let (.liveCounter(lhsCounter), .liveCounter(rhsCounter)):
            lhsCounter === rhsCounter
        default:
            false
        }
    }
}

// MARK: - ExpressibleBy*Literal conformances

extension LiveMapValue: ExpressibleByDictionaryLiteral {
    public init(dictionaryLiteral elements: (String, JSONValue)...) {
        self = .jsonObject(.init(uniqueKeysWithValues: elements))
    }
}

extension LiveMapValue: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: JSONValue...) {
        self = .jsonArray(elements)
    }
}

extension LiveMapValue: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self = .string(value)
    }
}

extension LiveMapValue: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int) {
        self = .number(Double(value))
    }
}

extension LiveMapValue: ExpressibleByFloatLiteral {
    public init(floatLiteral value: Double) {
        self = .number(value)
    }
}

extension LiveMapValue: ExpressibleByBooleanLiteral {
    public init(booleanLiteral value: Bool) {
        self = .bool(value)
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

    func compact() -> JSONValue?
}

public protocol PathObjectCollectionMethods {
    func at(path: String) -> PathObject
}

public protocol LiveMapPathObject: PathObjectBase, PathObjectCollectionMethods, LiveMapPathObjectCollectionMethods, LiveMapOperations {
    func get(key: String) -> PathObject

    var instance: LiveMapInstance? { get }

    func compact() -> [String: JSONValue]?
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
