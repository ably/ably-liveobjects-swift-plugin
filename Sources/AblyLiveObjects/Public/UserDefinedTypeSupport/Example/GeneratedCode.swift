import Foundation
import Ably

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

    enum PathObjectKnownEntry: LiveMapPathObjectKnownEntry {
        case topLevelCounter(LiveCounterPathObject)
        case topLevelMap(any ShapedLiveMapPathObject<TopLevelMap>)

        // TODO: I think that this is going to be another one that's tricky for codegen, again might require us to actually interpret the type because we need to turn a ShapedLiveMap property into a ShapedLiveMapPathObject. Perhaps what we actually want to do here is to let the caller be in charge of creating the object itself, i.e. return some sort of enum result from here instead, but I'm still not sure that fully helps us.
        // (note that the `get` variants don't have to handle this problem because they perform the conversion via the compiler picking the correct overload; maybe we need to see what we can do along those lines, maybe we can lean on the Key type more again)
        init?(key: String, pathObject: any PathObject) {
            fatalError("TODO: Not implemented")
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

    enum PathObjectKnownEntry: LiveMapPathObjectKnownEntry {
        case nestedEntry(any TypedPrimitivePathObject<String>)

        init?(key: String, pathObject: any PathObject) {
            fatalError("TODO: Not implemented")
        }
    }
}

// Note that each `LiveMapKeys` declares their own `Key` type — this is so that we don't have to pollute the library's public types with something that's only used for generated code; i.e. else we'd have to have something like the following:

/*
struct DefaultLiveMapKey<Shape: LiveMapShape, Value>: LiveMapKey {
    var rawKey: String
}
*/
