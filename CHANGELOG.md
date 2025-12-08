# Change Log

## [0.3.0](https://github.com/ably/ably-liveobjects-swift-plugin/tree/0.3.0)

## What's Changed

No public API changes. Some internal improvements:

- Use server time for object ID ([#98](https://github.com/ably/ably-liveobjects-swift-plugin/pull/98))
- Use server-sent GC grace period ([#99](https://github.com/ably/ably-liveobjects-swift-plugin/pull/99))
- Always transition to `SYNCING` on receipt of `ATTACHED` ([#104](https://github.com/ably/ably-liveobjects-swift-plugin/pull/104))

**Full Changelog**: https://github.com/ably/ably-liveobjects-swift-plugin/compare/0.2.0...0.3.0

## [0.2.0](https://github.com/ably/ably-liveobjects-swift-plugin/tree/0.2.0)

## What's Changed

- Fixes an issue with SPM dependency specification that caused compliation errors. ([#93](https://github.com/ably/ably-liveobjects-swift-plugin/issues/93))
- Changes `JSONValue`'s `number` associated value from `NSNumber` to `Double`. ([#91](https://github.com/ably/ably-liveobjects-swift-plugin/pull/91))

**Full Changelog**: https://github.com/ably/ably-liveobjects-swift-plugin/compare/0.1.0...0.2.0

## [0.1.0](https://github.com/ably/ably-liveobjects-swift-plugin/tree/0.1.0)

## What's New

- Our first release! LiveObjects provides a simple way to build collaborative applications with synchronized state across multiple clients in real-time.

Learn [about Ably LiveObjects.](https://ably.com/docs/liveobjects)

[Getting started with LiveObjects in Swift.](https://ably.com/docs/liveobjects/quickstart/swift)
