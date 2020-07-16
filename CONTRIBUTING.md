Contributing to the LDSwiftEventSource library
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

This SDK is built with [XCode](https://developer.apple.com/xcode/). This version has been tested with XCode 11.5.

### Building And Testing

This library can be built directly with the Swift package manager, or through XCode.  To build and run tests using SwiftPM simply:

```bash
swift test
```

Or in XCode, simply select the desired target and select `Product -> Test`.

For building on the command line with `xcodebuild`, see the [continuous integration build configuration](.circleci/config.yml) for examples on building and running tests.
