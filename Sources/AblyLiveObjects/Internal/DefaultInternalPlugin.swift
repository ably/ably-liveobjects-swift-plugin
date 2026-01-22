internal import _AblyPluginSupportPrivate
import Ably

// We explicitly import the NSObject class, else it seems to get transitively imported from  `internal import _AblyPluginSupportPrivate`, leading to the error "Class cannot be declared public because its superclass is internal".
import ObjectiveC.NSObject

/// The default implementation of `_AblyPluginSupportPrivate`'s `LiveObjectsInternalPluginProtocol`. Implements the interface that ably-cocoa uses to access the functionality provided by the LiveObjects plugin.
@objc
internal final class DefaultInternalPlugin: NSObject, _AblyPluginSupportPrivate.LiveObjectsInternalPluginProtocol {
    private let pluginAPI: _AblyPluginSupportPrivate.PluginAPIProtocol

    internal init(pluginAPI: _AblyPluginSupportPrivate.PluginAPIProtocol) {
        self.pluginAPI = pluginAPI
    }

    // MARK: - Channel `objects` property

    /// The `pluginDataValue(forKey:channel:)` key that we use to store the value of the `ARTRealtimeChannel.objects` property.
    private static let pluginDataKey = "LiveObjects"

    /// Retrieves the `RealtimeObjects` for this channel.
    ///
    /// We expect this value to have been previously set by ``prepare(_:)``.
    internal static func nosync_realtimeObjects(for channel: _AblyPluginSupportPrivate.RealtimeChannel, pluginAPI: _AblyPluginSupportPrivate.PluginAPIProtocol) -> InternalDefaultRealtimeObjects {
        guard let pluginData = pluginAPI.nosync_pluginDataValue(forKey: pluginDataKey, channel: channel) else {
            // InternalPlugin.prepare was not called
            fatalError("To access LiveObjects functionality, you must pass the LiveObjects plugin in the client options when creating the ARTRealtime instance: `clientOptions.plugins = [.liveObjects: AblyLiveObjects.Plugin.self]`")
        }

        // swiftlint:disable:next force_cast
        return pluginData as! InternalDefaultRealtimeObjects
    }

    // MARK: - LiveObjectsInternalPluginProtocol

    // Populates the channel's `objects` property.
    internal func nosync_prepare(_ channel: _AblyPluginSupportPrivate.RealtimeChannel, client: _AblyPluginSupportPrivate.RealtimeClient) {
        let pluginLogger = pluginAPI.logger(for: channel)
        let internalQueue = pluginAPI.internalQueue(for: client)
        let callbackQueue = pluginAPI.callbackQueue(for: client)
        let options = ARTClientOptions.castPluginPublicClientOptions(pluginAPI.options(for: client))

        let garbageCollectionOptions = options.garbageCollectionOptions ?? {
            if let latestConnectionDetails = pluginAPI.nosync_latestConnectionDetails(for: client), let gracePeriod = latestConnectionDetails.objectsGCGracePeriod {
                // If we already have connection details, then use its grace period per RTO10b2
                .init(gracePeriod: .dynamic(gracePeriod.doubleValue))
            } else {
                // Use the default grace period
                .init()
            }
        }()

        let logger = DefaultLogger(pluginLogger: pluginLogger, pluginAPI: pluginAPI)
        logger.log("LiveObjects.DefaultInternalPlugin received prepare(_:)", level: .debug)
        let liveObjects = InternalDefaultRealtimeObjects(
            logger: logger,
            internalQueue: internalQueue,
            userCallbackQueue: callbackQueue,
            clock: DefaultSimpleClock(),
            garbageCollectionOptions: garbageCollectionOptions,
        )
        pluginAPI.nosync_setPluginDataValue(liveObjects, forKey: Self.pluginDataKey, channel: channel)
    }

    /// Retrieves the internally-typed `objects` property for the channel.
    private func nosync_realtimeObjects(for channel: _AblyPluginSupportPrivate.RealtimeChannel) -> InternalDefaultRealtimeObjects {
        Self.nosync_realtimeObjects(for: channel, pluginAPI: pluginAPI)
    }

    /// A class that wraps an object message.
    ///
    /// We need this intermediate type because we want object messages to be structs — because they're nicer to work with internally — but a struct can't conform to the class-bound `_AblyPluginSupportPrivate.ObjectMessageProtocol`.
    private final class ObjectMessageBox<T>: _AblyPluginSupportPrivate.ObjectMessageProtocol where T: Sendable {
        internal let objectMessage: T

        init(objectMessage: T) {
            self.objectMessage = objectMessage
        }
    }

    internal func decodeObjectMessage(
        _ serialized: [String: Any],
        context: DecodingContextProtocol,
        format: EncodingFormat,
        error errorPtr: AutoreleasingUnsafeMutablePointer<_AblyPluginSupportPrivate.PublicErrorInfo?>?,
    ) -> (any ObjectMessageProtocol)? {
        let wireObject = WireValue.objectFromPluginSupportData(serialized)

        do {
            let wireObjectMessage = try InboundWireObjectMessage(
                wireObject: wireObject,
                decodingContext: context,
            )
            let objectMessage = try InboundObjectMessage(
                wireObjectMessage: wireObjectMessage,
                format: format,
            )
            return ObjectMessageBox(objectMessage: objectMessage)
        } catch {
            errorPtr?.pointee = error.asPluginPublicErrorInfo
            return nil
        }
    }

    internal func encodeObjectMessage(
        _ publicObjectMessage: any _AblyPluginSupportPrivate.ObjectMessageProtocol,
        format: EncodingFormat,
    ) -> [String: Any] {
        guard let outboundObjectMessageBox = publicObjectMessage as? ObjectMessageBox<OutboundObjectMessage> else {
            preconditionFailure("Expected to receive the same OutboundObjectMessage type as we emit")
        }

        let wireObjectMessage = outboundObjectMessageBox.objectMessage.toWire(format: format)
        return wireObjectMessage.toWireObject.toPluginSupportDataDictionary
    }

    internal func nosync_onChannelAttached(_ channel: _AblyPluginSupportPrivate.RealtimeChannel, hasObjects: Bool) {
        nosync_realtimeObjects(for: channel).nosync_onChannelAttached(hasObjects: hasObjects)
    }

    internal func nosync_handleObjectProtocolMessage(withObjectMessages publicObjectMessages: [any _AblyPluginSupportPrivate.ObjectMessageProtocol], channel: _AblyPluginSupportPrivate.RealtimeChannel) {
        guard let inboundObjectMessageBoxes = publicObjectMessages as? [ObjectMessageBox<InboundObjectMessage>] else {
            preconditionFailure("Expected to receive the same InboundObjectMessage type as we emit")
        }

        let objectMessages = inboundObjectMessageBoxes.map(\.objectMessage)

        nosync_realtimeObjects(for: channel).nosync_handleObjectProtocolMessage(
            objectMessages: objectMessages,
        )
    }

    internal func nosync_handleObjectSyncProtocolMessage(withObjectMessages publicObjectMessages: [any _AblyPluginSupportPrivate.ObjectMessageProtocol], protocolMessageChannelSerial: String?, channel: _AblyPluginSupportPrivate.RealtimeChannel) {
        guard let inboundObjectMessageBoxes = publicObjectMessages as? [ObjectMessageBox<InboundObjectMessage>] else {
            preconditionFailure("Expected to receive the same InboundObjectMessage type as we emit")
        }

        let objectMessages = inboundObjectMessageBoxes.map(\.objectMessage)

        nosync_realtimeObjects(for: channel).nosync_handleObjectSyncProtocolMessage(
            objectMessages: objectMessages,
            protocolMessageChannelSerial: protocolMessageChannelSerial,
        )
    }

    internal func nosync_onConnected(withConnectionDetails connectionDetails: (any ConnectionDetailsProtocol)?, channel: any RealtimeChannel) {
        let gracePeriod = connectionDetails?.objectsGCGracePeriod?.doubleValue ?? InternalDefaultRealtimeObjects.GarbageCollectionOptions.defaultGracePeriod

        // RTO10b
        nosync_realtimeObjects(for: channel).nosync_setGarbageCollectionGracePeriod(gracePeriod)

        // CD2j: Store siteCode for apply-on-ACK (RTO20c)
        // TODO: Uncomment once siteCode is added to ConnectionDetailsProtocol in ably-cocoa-plugin-support
        // and parsed from connectionDetails in ably-cocoa.
        // if let siteCode = connectionDetails?.siteCode {
        //     nosync_realtimeObjects(for: channel).nosync_setSiteCode(siteCode)
        // }
    }

    // MARK: - Sending `OBJECT` ProtocolMessage

    internal static func sendObject(
        objectMessages: [OutboundObjectMessage],
        channel: _AblyPluginSupportPrivate.RealtimeChannel,
        client: _AblyPluginSupportPrivate.RealtimeClient,
        pluginAPI: PluginAPIProtocol,
    ) async throws(ARTErrorInfo) -> PublishResult {
        let objectMessageBoxes: [ObjectMessageBox<OutboundObjectMessage>] = objectMessages.map { .init(objectMessage: $0) }

        return try await withCheckedContinuation { (continuation: CheckedContinuation<Result<PublishResult, ARTErrorInfo>, _>) in
            let internalQueue = pluginAPI.internalQueue(for: client)

            internalQueue.async {
                // RTO20b: The callback should include `serials` from the ACK `res[0].serials` property.
                // TODO: Update ably-cocoa to pass the serials in the callback per the spec prereqs:
                // - APPluginAPI.h: Change nosync_sendObject completion handler to include serials array
                // - ARTPluginAPI.m: Parse serials from ACK res[0].serials and pass to callback
                // Until those changes are made, serials will be an array of nils.
                pluginAPI.nosync_sendObject(
                    withObjectMessages: objectMessageBoxes,
                    channel: channel,
                ) { error in
                    // We don't currently rely on this documented behaviour of `nosync_sendObject` but we may do later, so assert it to be sure it's happening.
                    dispatchPrecondition(condition: .onQueue(internalQueue))

                    if let error {
                        continuation.resume(returning: .failure(ARTErrorInfo.castPluginPublicErrorInfo(error)))
                    } else {
                        // TODO: Extract serials from callback once ably-cocoa is updated
                        // For now, return an array of nils with the same count as messages sent
                        let serials: [String?] = Array(repeating: nil, count: objectMessageBoxes.count)
                        continuation.resume(returning: .success(PublishResult(serials: serials)))
                    }
                }
            }
        }.get()
    }
}
