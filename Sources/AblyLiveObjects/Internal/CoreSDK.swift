internal import _AblyPluginSupportPrivate
import Ably

/// Result of a successful publish operation (RTO15).
/// Contains information from the ACK needed for apply-on-ACK (RTO20).
/// Corresponds to a single `PublishResult` in the ACK's `res` array.
internal struct PublishResult: Sendable {
    /// The message serials from the ACK `res[i].serials` property.
    /// Each element corresponds 1:1 to the messages that were published.
    /// A serial may be nil if the message was discarded due to a configured conflation rule.
    let serials: [String?]
}

/// The API that the internal components of the SDK (that is, `DefaultLiveObjects` and down) use to interact with our core SDK (i.e. ably-cocoa).
///
/// This provides us with a mockable interface to ably-cocoa, and it also allows internal components and their tests not to need to worry about some of the boring details of how we bridge Swift types to `_AblyPluginSupportPrivate`'s Objective-C API (i.e. boxing).
internal protocol CoreSDK: AnyObject, Sendable {
    /// Implements the internal `#publish` method of RTO15.
    /// Returns a `PublishResult` containing the serial from the ACK for apply-on-ACK (RTO20).
    @discardableResult
    func publish(objectMessages: [OutboundObjectMessage]) async throws(ARTErrorInfo) -> PublishResult

    /// Implements the server time fetch of RTO16, including the storing and usage of the local clock offset.
    func fetchServerTime() async throws(ARTErrorInfo) -> Date

    /// Replaces the implementation of ``publish(objectMessages:)``.
    ///
    /// Used by integration tests, for example to disable `ObjectMessage` publishing so that a test can verify that a behaviour is not a side effect of an `ObjectMessage` sent by the SDK.
    func testsOnly_overridePublish(with newImplementation: @escaping ([OutboundObjectMessage]) async throws(ARTErrorInfo) -> PublishResult)

    /// Returns the current state of the Realtime channel that this wraps.
    var nosync_channelState: _AblyPluginSupportPrivate.RealtimeChannelState { get }
}

internal final class DefaultCoreSDK: CoreSDK {
    /// Used to synchronize access to internal mutable state.
    private let mutex = NSLock()

    private let channel: _AblyPluginSupportPrivate.RealtimeChannel
    private let client: _AblyPluginSupportPrivate.RealtimeClient
    private let pluginAPI: PluginAPIProtocol
    private let logger: Logger

    /// If set to true, ``publish(objectMessages:)`` will behave like a no-op.
    ///
    /// This enables the `testsOnly_overridePublish(with:)` test hook.
    ///
    /// - Note: This should be `throws(ARTErrorInfo)` but that causes a compilation error of "Runtime support for typed throws function types is only available in macOS 15.0.0 or newer".
    private nonisolated(unsafe) var overriddenPublishImplementation: (([OutboundObjectMessage]) async throws -> PublishResult)?

    internal init(
        channel: _AblyPluginSupportPrivate.RealtimeChannel,
        client: _AblyPluginSupportPrivate.RealtimeClient,
        pluginAPI: PluginAPIProtocol,
        logger: Logger
    ) {
        self.channel = channel
        self.client = client
        self.pluginAPI = pluginAPI
        self.logger = logger
    }

    // MARK: - CoreSDK conformance

    @discardableResult
    internal func publish(objectMessages: [OutboundObjectMessage]) async throws(ARTErrorInfo) -> PublishResult {
        logger.log("publish(objectMessages: \(LoggingUtilities.formatObjectMessagesForLogging(objectMessages)))", level: .debug)

        // Use the overridden implementation if supplied
        let overriddenImplementation = mutex.withLock {
            overriddenPublishImplementation
        }
        if let overriddenImplementation {
            do {
                return try await overriddenImplementation(objectMessages)
            } catch {
                guard let artErrorInfo = error as? ARTErrorInfo else {
                    preconditionFailure("Expected ARTErrorInfo, got \(error)")
                }
                throw artErrorInfo
            }
        }

        // TODO: Implement message size checking (https://github.com/ably/ably-liveobjects-swift-plugin/issues/13)
        return try await DefaultInternalPlugin.sendObject(
            objectMessages: objectMessages,
            channel: channel,
            client: client,
            pluginAPI: pluginAPI,
        )
    }

    internal func testsOnly_overridePublish(with newImplementation: @escaping ([OutboundObjectMessage]) async throws(ARTErrorInfo) -> PublishResult) {
        mutex.withLock {
            overriddenPublishImplementation = newImplementation
        }
    }

    internal func fetchServerTime() async throws(ARTErrorInfo) -> Date {
        try await withCheckedContinuation { (continuation: CheckedContinuation<Result<Date, ARTErrorInfo>, _>) in
            let internalQueue = pluginAPI.internalQueue(for: client)

            internalQueue.async { [client, pluginAPI] in
                pluginAPI.nosync_fetchServerTime(for: client) { serverTime, error in
                    // We don't currently rely on this documented behaviour of `noSync_fetchServerTime` but we may do later, so assert it to be sure it's happening.
                    dispatchPrecondition(condition: .onQueue(internalQueue))

                    if let error {
                        continuation.resume(returning: .failure(ARTErrorInfo.castPluginPublicErrorInfo(error)))
                    } else {
                        guard let serverTime else {
                            preconditionFailure("nosync_fetchServerTime gave nil serverTime and nil error")
                        }
                        continuation.resume(returning: .success(serverTime))
                    }
                }
            }
        }.get()
    }

    internal var nosync_channelState: _AblyPluginSupportPrivate.RealtimeChannelState {
        pluginAPI.nosync_state(for: channel)
    }
}

// MARK: - Channel State Validation

/// Extension on CoreSDK to provide channel state validation utilities.
internal extension CoreSDK {
    /// Validates that the channel is not in any of the specified invalid states.
    ///
    /// - Parameters:
    ///   - invalidStates: Array of channel states that are considered invalid for the operation
    ///   - operationDescription: A description of the operation being performed, used in error messages
    /// - Throws: `ARTErrorInfo` with code 90001 and statusCode 400 if the channel is in any of the invalid states
    func nosync_validateChannelState(
        notIn invalidStates: [_AblyPluginSupportPrivate.RealtimeChannelState],
        operationDescription: String,
    ) throws(ARTErrorInfo) {
        let currentChannelState = nosync_channelState
        if invalidStates.contains(currentChannelState) {
            throw LiveObjectsError.objectsOperationFailedInvalidChannelState(
                operationDescription: operationDescription,
                channelState: currentChannelState,
            )
            .toARTErrorInfo()
        }
    }
}
