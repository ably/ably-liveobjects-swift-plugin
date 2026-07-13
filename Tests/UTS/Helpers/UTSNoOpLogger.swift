import _AblyPluginSupportPrivate
@testable import AblyLiveObjects

/// A no-op ``Logger`` for the tests that drive `ObjectsPool` / `InternalDefaultRealtimeObjects` /
/// the live-object classes directly (without the mock WebSocket).
final class UTSNoOpLogger: AblyLiveObjects.Logger {
    func log(_: String, level _: _AblyPluginSupportPrivate.LogLevel, codeLocation _: CodeLocation) {}
}
