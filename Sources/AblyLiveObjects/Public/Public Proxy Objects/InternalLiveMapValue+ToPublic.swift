internal import _AblyPluginSupportPrivate

internal extension InternalLiveMapValue {
    // MARK: - Mapping to public types

    struct PublicValueCreationArgs {
        internal var coreSDK: CoreSDK
        internal var mapDelegate: LiveMapObjectsPoolDelegate
        internal var logger: Logger

        internal var toCounterCreationArgs: PublicObjectsStore.CounterCreationArgs {
            // TODO: Figure out how to properly pass realtimeObjects through the object graph
            // swiftlint:disable:next force_cast
            .init(coreSDK: coreSDK, logger: logger, realtimeObjects: mapDelegate as! InternalDefaultRealtimeObjects)
        }

        internal var toMapCreationArgs: PublicObjectsStore.MapCreationArgs {
            .init(coreSDK: coreSDK, delegate: mapDelegate, logger: logger)
        }
    }

    /// Fetches the cached public object that wraps this `InternalLiveMapValue`'s associated value, creating a new public object if there isn't already one.
    func toPublic(creationArgs: PublicValueCreationArgs) -> LiveMapValue {
        switch self {
        case let .string(value):
            .string(value)
        case let .number(value):
            .number(value)
        case let .bool(value):
            .bool(value)
        case let .data(value):
            .data(value)
        case let .jsonArray(value):
            .jsonArray(value)
        case let .jsonObject(value):
            .jsonObject(value)
        case let .liveMap(internalLiveMap):
            .liveMap(
                PublicObjectsStore.shared.getOrCreateMap(
                    proxying: internalLiveMap,
                    creationArgs: creationArgs.toMapCreationArgs,
                ),
            )
        case let .liveCounter(internalLiveCounter):
            .liveCounter(
                PublicObjectsStore.shared.getOrCreateCounter(
                    proxying: internalLiveCounter,
                    creationArgs: creationArgs.toCounterCreationArgs,
                ),
            )
        }
    }
}
