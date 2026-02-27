import _AblyPluginSupportPrivate
import Ably
@testable import AblyLiveObjects

final class MockCoreSDK: CoreSDK {
    /// Synchronizes access to `_publishHandler`.
    private let mutex = NSLock()
    private nonisolated(unsafe) var _publishHandler: (([OutboundObjectMessage]) async throws(ARTErrorInfo) -> PublishResult)?

    private let channelStateMutex: DispatchQueueMutex<_AblyPluginSupportPrivate.RealtimeChannelState>
    private let serverTime: Date
    private let _siteCode: String?

    init(channelState: _AblyPluginSupportPrivate.RealtimeChannelState, serverTime: Date = .init(), siteCode: String? = "site1", internalQueue: DispatchQueue) {
        channelStateMutex = DispatchQueueMutex(dispatchQueue: internalQueue, initialValue: channelState)
        self.serverTime = serverTime
        self._siteCode = siteCode
    }

    func publish(objectMessages: [OutboundObjectMessage]) async throws(ARTErrorInfo) -> PublishResult {
        if let handler = _publishHandler {
            return try await handler(objectMessages)
        } else {
            protocolRequirementNotImplemented()
        }
    }

    func testsOnly_overridePublish(with _: @escaping ([OutboundObjectMessage]) async throws(ARTErrorInfo) -> PublishResult) {
        protocolRequirementNotImplemented()
    }

    var nosync_channelState: _AblyPluginSupportPrivate.RealtimeChannelState {
        channelStateMutex.withoutSync { $0 }
    }

    func nosync_siteCode() -> String? {
        _siteCode
    }

    /// Sets a custom publish handler for testing
    func setPublishHandler(_ handler: @escaping ([OutboundObjectMessage]) async throws(ARTErrorInfo) -> PublishResult) {
        mutex.withLock {
            _publishHandler = handler
        }
    }

    func fetchServerTime() async throws(ARTErrorInfo) -> Date {
        serverTime
    }
}
