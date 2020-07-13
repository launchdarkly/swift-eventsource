# Change log

All notable changes to the LaunchDarkly Swift EventSource library will be documented in this file. This project adheres to [Semantic Versioning](http://semver.org).

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
