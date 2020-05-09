Contributing to the LaunchDarkly Swift EventSource library
================================================

Submitting bug reports and feature requests
------------------

The LaunchDarkly SDK team monitors the [issue tracker](https://github.com/launchdarkly/swift-eventsource/issues) for the EventSource repository. Bug reports and feature requests specific to this library should be filed in this issue tracker.

Submitting pull requests
------------------

We encourage pull requests and other contributions from the community. Before submitting pull requests, ensure that all temporary or unintended code is removed. Don't worry about adding reviewers to the pull request; the LaunchDarkly SDK team will add themselves.

Build instructions
------------------

### Prerequisites

This SDK is built with [XCode](https://developer.apple.com/xcode/). This version has been tested with XCode 11.4.

### Building

The exact command used to build the SDK depends on where you want to use it (for example -- iOS, watchOS, etc.). Refer to the `xcodebuild` commands in the SDK's [continuous integration build configuration](.circleci/config.yml) for examples on how to build for the different platforms.

If you wish to clean your working directory between builds, include the `clean` goal in your `xcodebuild` command(s).

### Testing

To build the SDK and run all unit tests, include the `test` goal in your `xcodebuild` command(s).
