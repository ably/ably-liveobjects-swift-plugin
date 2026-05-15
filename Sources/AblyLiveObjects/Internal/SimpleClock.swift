import Foundation
internal import _AblyPluginSupportPrivate

/// A simple clock interface for getting the current time.
///
/// This protocol allows for dependency injection of time-related functionality,
/// making it easier to test time-dependent code.
internal protocol SimpleClock: Sendable {
    /// Returns the current time as a Date.
    var now: Date { get }
}

/// The default implementation of `SimpleClock`, which reads the current time through ably-cocoa's injected `ARTTimeProvider` via the `APPluginAPI` boundary.
///
/// Using this adapter (rather than calling `Date()` directly) means that when the SDK has a fake-time provider installed via `options.testOptions.timeProvider`, the plugin's notion of "now" follows it.
internal final class DefaultSimpleClock: SimpleClock {
    private let pluginAPI: PluginAPIProtocol
    private let client: RealtimeClient

    internal init(pluginAPI: PluginAPIProtocol, client: RealtimeClient) {
        self.pluginAPI = pluginAPI
        self.client = client
    }

    internal var now: Date {
        pluginAPI.wallClockNow(for: client)
    }
}
