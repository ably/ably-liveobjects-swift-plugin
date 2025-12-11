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

    // And imagining if there were a LiveList type, we'd have an asLiveList property too. Its `entries()` would have a different static type to that of `asLiveMap.entries()`.
}
