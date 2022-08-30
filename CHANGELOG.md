# Change log

All notable changes to the LaunchDarkly Swift EventSource library will be documented in this file. This project adheres to [Semantic Versioning](http://semver.org).

## [2.0.0] - 2022-08-29
### Changed
- The CI build now incorporates the cross-platform contract tests defined in https://github.com/launchdarkly/sse-contract-tests to ensure consistent test coverage across different LaunchDarkly SSE implementations.
- Removed explicit typed package products. Thanks to @simba909 for the PR ([#48](https://github.com/launchdarkly/swift-eventsource/pull/48)).

## [1.3.1] - 2022-03-11
### Fixed
- Fixed a race condition that could cause a crash when `stop()` is called when there is a pending reconnection attempt.

## [1.3.0] - 2022-01-18
### Added
- Added the configuration option `urlSessionConfiguration` to `EventSource.Config` which allows setting the `URLSessionConfiguration` used by the `EventSource` to create `URLSession` instances.

### Fixed
- Fixed a retain cycle issue when the stream connection is ended.
- Removed deprecated `VALID_ARCHS` build setting from Xcode project.
- Unterminated events will no longer be dispatched when the stream connection is dropped.
- Stream events that set the `lastEventId` will now record the updated `lastEventId` even if the event does not generate a `MessageEvent`.
- Empty stream "data" fields will now always record a newline to the resultant `MessageEvent` data.
- Empty stream "event" fields will result in now result in the default "message" event type rather than an event type of "".

## [1.2.1] - 2021-02-10
### Added
- [SwiftLint](https://github.com/realm/SwiftLint) configuration. Linting will be automatically run as part of the build if [Mint](https://github.com/yonaskolb/Mint) is installed.
- Support for building docs with [jazzy](https://github.com/realm/jazzy). These docs are available through [GitHub Pages](https://launchdarkly.github.io/swift-eventsource/).

### Fixed
- Reconnection backoff was always reset if the  previous successful connection was at least `backoffResetThreshold` prior to the scheduling of a reconnection attempt. The connection backoff has been corrected to not reset after the first reconnection attempt until the next successful connection. Thanks to  @tomasf for the PR ([#14](https://github.com/launchdarkly/swift-eventsource/pull/14)).
- On an `UnsuccessfulResponseError` the configured `connectionErrorHandler` would be called twice, the second time with a `URLError.cancelled` error. Only if the second call returned `ConnectionErrorAction.shutdown` would the `EventSource` client actually shutdown. This has been corrected to only call the `connectionErrorHandler` once, and will shutdown the client if `ConnectionErrorAction.shutdown` is returned. Thanks to  @tomasf for the PR ([#13](https://github.com/launchdarkly/swift-eventsource/pull/13)).
- A race condition that could cause the `EventSource` client to restart after shutting down has been fixed.

## [1.2.0] - 2020-10-21
### Added
- Added `headerTransform` closure to `LDConfig` to allow dynamic http header configuration.

## [1.1.0] - 2020-07-20
### Added
- Support `arm64e` on `appletvos`, `iphoneos`, and `macosx` SDKs by extending valid architectures.
- Support for building LDSwiftEventSource on Linux. Currently this library will not generate log messages on Linux, and may not behave correctly on Linux due to Foundation being [incomplete](https://github.com/apple/swift-corelibs-foundation/blob/main/Docs/Status.md).

## [1.0.0] - 2020-07-16
This is the first public release of the LDSwiftEventSource library. The following notes are what changed since the previous pre-release version.
### Changed
- Renamed `EventHandler.onMessage` parameter `event` to `eventType`.
- The `EventSource` class no longer extends `NSObject` or `URLSessionDataDelegate` to not expose `urlSession` functions.

## [0.5.0] - 2020-07-14
### Changed
- Default `LDSwiftEventSource` product defined for the SwiftPM package is now explicitly a dynamic product. An explicitly static product is now available as `LDSwiftEventSourceStatic`.

## [0.4.0] - 2020-07-13
### Changed
- Converted build system to use a single target to produce a universal framework, rather than separate targets for each platform that share a product name. This is to prevent issues with `xcodebuild` resolving the build scheme to an incorrect platform when building dependent packages with 'Find Implicit Dependencies' enabled. This is due to a bug in `xcodebuild`, for more information see [http://www.openradar.me/20490378](http://www.openradar.me/20490378) and [http://www.openradar.me/22008701](http://www.openradar.me/22008701).

## [0.3.0] - 2020-06-02
### Added
- Added `stop()` method to shutdown the EventSource connection.
### Changed
- Logging `subsystem` renamed from `com.launchdarkly.swift-event-source` to `com.launchdarkly.swift-eventsource`

## [0.2.0] - 2020-05-21
### Added
- Public constructors for `UnsuccessfulResponseError` and `MessageEvent` to allow consumers of the library to use them for unit tests.

## [0.1.0] - 2020-05-09
### Added
- Initial implementation for internal alpha testing.
