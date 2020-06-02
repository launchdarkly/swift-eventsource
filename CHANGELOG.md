# Change log

All notable changes to the LaunchDarkly Swift EventSource library will be documented in this file. This project adheres to [Semantic Versioning](http://semver.org).

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
