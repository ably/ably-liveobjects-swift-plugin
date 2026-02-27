import _AblyPluginSupportPrivate
import Ably
@testable import AblyLiveObjects

final class MockCoreSDK: CoreSDK {
    /// Synchronizes access to `_publishHandler`.
    private let mutex = NSLock()
    private nonisolated(unsafe) var _publishHandler: (([OutboundObjectMessage]) async throws(ARTErrorInfo) -> Void)?

    private let channelStateMutex: DispatchQueueMutex<_AblyPluginSupportPrivate.RealtimeChannelState>
    private let serverTime: Date

    init(channelState: _AblyPluginSupportPrivate.RealtimeChannelState, serverTime: Date = .init(), internalQueue: DispatchQueue) {
        channelStateMutex = DispatchQueueMutex(dispatchQueue: internalQueue, initialValue: channelState)
        self.serverTime = serverTime
    }

    func nosync_publish(objectMessages: [OutboundObjectMessage], callback: @escaping @Sendable (Result<Void, ARTErrorInfo>) -> Void) {
        if let handler = _publishHandler {
            let queue = channelStateMutex.dispatchQueue
            Task {
                do throws(ARTErrorInfo) {
                    try await handler(objectMessages)
                    queue.async { callback(.success(())) }
                } catch {
                    queue.async { callback(.failure(error)) }
                }
            }
        } else {
            protocolRequirementNotImplemented()
        }
    }

    func testsOnly_overridePublish(with _: @escaping ([OutboundObjectMessage]) async throws(ARTErrorInfo) -> Void) {
        protocolRequirementNotImplemented()
    }

    var nosync_channelState: _AblyPluginSupportPrivate.RealtimeChannelState {
        channelStateMutex.withoutSync { $0 }
    }

    /// Sets a custom publish handler for testing
    func setPublishHandler(_ handler: @escaping ([OutboundObjectMessage]) async throws(ARTErrorInfo) -> Void) {
        mutex.withLock {
            _publishHandler = handler
        }
    }

    func nosync_fetchServerTime(callback: @escaping @Sendable (Result<Date, ARTErrorInfo>) -> Void) {
        callback(.success(serverTime))
    }
}
