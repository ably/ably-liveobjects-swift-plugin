import Foundation
import Ably

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

    for entry in myChannelPathObject.entries {
        switch entry {
        case .known(let known):
            switch known {
            case .topLevelCounter(let liveCounterPathObject):
                break
            case .topLevelMap(let shapedLiveMapPathObject):
                break
            }
        case .unknown(let key, let value):
            break
        }
    }

    for entry in topLevelMap.entries {
        switch entry {
        case .known(let known):
            switch known {
            case .nestedEntry(let typedPrimitivePathObject):
                break
            }
        case .unknown(let key, let value):
            break
        }

    }
}
