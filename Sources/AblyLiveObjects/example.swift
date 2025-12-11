import Ably

// An example to show the usage of the proposed asLiveMap and asLiveCounter properties

func exampleWithNoUserTypes(channel: ARTRealtimeChannel) async throws {
    // `object` has type `any LiveMapPathObject`
    let object = try await channel.object.get()

    // - `topLevelCounter` has type `any LiveCounterPathObject`
    // - the compiler will not let you call any LiveMap methods on it (e.g. `entries()`, `set()`)
    let topLevelCounter = object.get(key: "topLevelCounter").asLiveCounter

    // - `topLevelMap` has type `any LiveMapPathObject`
    // - the compiler will not let you call any LiveCounter methods on it (e.g. `increment()`)
    let topLevelMap = object.get(key: "topLevelMap").asLiveMap

    // And imagining if there were a LiveList type, we'd have an asLiveList property too. Its `entries()` would have a different return value type to that of `asLiveMap.entries()`.
}

// An example to show the consequent changes to the Instance API

func instanceExampleWithNoUserTypes(channel: ARTRealtimeChannel) async throws {
    let object = try await channel.object.get()

    let topLevelCounter = object.get(key: "topLevelCounter")

    // topLevelCounterInstance has type `(any LiveCounterInstance)?`. If it is non-nil, then the underlying value is a LiveCounter
    let topLevelCounterInstance = topLevelCounter.instance?.asLiveCounter

    guard let topLevelCounterInstance else {
        // the underlying value is not a LiveCounter
        return
    }

    // counterInstanceValue has type Double (i.e. there's no equivalent to the "undefined" possibility in JS)
    let counterInstanceValue = topLevelCounterInstance.value
}
