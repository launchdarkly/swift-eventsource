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

This library is built with [XCode](https://developer.apple.com/xcode/) or [SwiftPM](https://swift.org/package-manager/). The [CI build](https://circleci.com/gh/launchdarkly/swift-eventsource) builds and tests various configurations of the library on various systems, platforms, and devices. For details, see [the CircleCI configuration][ci-config].

### Building And Testing

This library can be built directly with the Swift package manager, or through XCode. To build and run tests using SwiftPM simply:

```bash
swift test
```

Or in XCode, simply select the desired target and select `Product -> Test`.

For building on the command line with `xcodebuild`, see the [continuous integration build configuration][ci-config] for examples on building and running tests.

### Generating API documentation

Docs are built with [jazzy](https://github.com/realm/jazzy), which is configured [here](https://github.com/launchdarkly/swift-eventsource/blob/master/.jazzy.yaml). To build them, simply run `jazzy`. Pull requests should keep our documentation coverage at 100%.

[ci-config]: https://github.com/launchdarkly/swift-eventsource/blob/master/.circleci/config.yml
