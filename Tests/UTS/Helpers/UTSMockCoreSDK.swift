import _AblyPluginSupportPrivate
import Ably
import Foundation
@testable import AblyLiveObjects

/// A minimal ``CoreSDK`` for the tests that drive the internal live-object classes directly. Reports
/// a fixed channel state (so value/size reads pass the RTO25 precondition) and resolves publishes
/// synchronously via `publishHandler` (used to feed a known ACK serial into the LOCAL-source apply
/// path).
final class UTSMockCoreSDK: CoreSDK {
    private let channelState: _AblyPluginSupportPrivate.RealtimeChannelState
    private let internalQueue: DispatchQueue
    private let publishHandler: @Sendable ([ProtocolTypes.OutboundObjectMessage]) -> PublishResult

    init(
        channelState: _AblyPluginSupportPrivate.RealtimeChannelState = .attached,
        internalQueue: DispatchQueue,
        publishHandler: @escaping @Sendable ([ProtocolTypes.OutboundObjectMessage]) -> PublishResult = { _ in PublishResult(serials: []) },
    ) {
        self.channelState = channelState
        self.internalQueue = internalQueue
        self.publishHandler = publishHandler
    }

    func nosync_publish(objectMessages: [ProtocolTypes.OutboundObjectMessage], callback: @escaping @Sendable (Result<PublishResult, ARTErrorInfo>) -> Void) {
        let result = publishHandler(objectMessages)
        internalQueue.async { callback(.success(result)) }
    }

    func nosync_fetchServerTime(callback: @escaping @Sendable (Result<Date, ARTErrorInfo>) -> Void) {
        callback(.success(Date()))
    }

    func testsOnly_overridePublish(with _: @escaping ([ProtocolTypes.OutboundObjectMessage]) async throws(ARTErrorInfo) -> PublishResult) {}

    var nosync_channelState: _AblyPluginSupportPrivate.RealtimeChannelState {
        channelState
    }
}
