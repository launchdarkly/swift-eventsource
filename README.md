# LDSwiftEventSource

[![Run CI](https://github.com/launchdarkly/swift-eventsource/actions/workflows/ci.yml/badge.svg)](https://github.com/launchdarkly/swift-eventsource/actions/workflows/ci.yml)
[![SwiftPM compatible](https://img.shields.io/badge/SwiftPM-compatible-4BC51D.svg?style=flat)](https://swift.org/package-manager/)

LDSwiftEventSource is a cross platform implementation of the [EventSource specification](https://html.spec.whatwg.org/multipage/server-sent-events.html) written in Swift. It was developed for use in the [LaunchDarkly iOS SDK](https://github.com/launchdarkly/ios-client-sdk). Generated API docs are available on [GitHub Pages](https://launchdarkly.github.io/swift-eventsource/).

## Requirements
- iOS 15.0+ / watchOS 8.0+ / tvOS 15.0+ / macOS 11.0+
- Swift 6.0+

## Installation

LDSwiftEventSource is distributed exclusively through the [Swift Package Manager](https://swift.org/package-manager/), which is integrated into the `swift` compiler and Xcode.

To integrate LDSwiftEventSource into an Xcode project, go to the project editor, and select `Swift Packages`. From here hit the `+` button and follow the prompts using `https://github.com/LaunchDarkly/swift-eventsource.git` as the URL.

To include LDSwiftEventSource in a Swift package, simply add it to the dependencies section of your `Package.swift` file, and add the `LDSwiftEventSource` product as a dependency for your targets.

<!-- x-release-please-start-version -->
```swift
dependencies: [
    .package(url: "https://github.com/LaunchDarkly/swift-eventsource.git", .upToNextMajor(from: "3.3.0"))
]
```
<!-- x-release-please-end -->

## Usage

`EventSource` exposes received events as an `AsyncSequence`. Configure it with a `URL`, call `start()`, and iterate `events`:

```swift
import LDSwiftEventSource

let config = EventSource.Config(url: URL(string: "https://example.com/stream")!)
let eventSource = EventSource(config: config)
eventSource.start()

for await event in eventSource.events {
    switch event {
    case let .opened(headers):
        // Connection (re)established. `headers` are the response headers, keys lowercased.
        print("opened: \(headers)")
    case .closed:
        print("connection closed; the client will reconnect")
    case let .message(eventType, message):
        print("\(eventType): \(message.data)")
    case let .comment(comment):
        print("comment: \(comment)")
    case let .error(error):
        // Recoverable errors are advisory — the client keeps retrying and the stream stays open.
        // An unrecoverable error is the last event before the stream finishes.
        print("error (status: \(error.statusCode.map(String.init) ?? "none"), recoverable: \(error.recoverable))")
    }
}
```

The sequence is single-consumer: iterate it from one task. Call `stop()` to shut the client down and finish the stream; the connection is also torn down if the consuming task is cancelled. Errors are reported as values on the stream rather than thrown, so a recoverable failure does not interrupt iteration.

## Contributing

We encourage pull requests and other contributions from the community. Check out our [contributing guidelines](https://github.com/LaunchDarkly/swift-eventsource/blob/main/CONTRIBUTING.md) for instructions on how to contribute to this SDK.

## About LaunchDarkly

* LaunchDarkly is a continuous delivery platform that provides feature flags as a service and allows developers to iterate quickly and safely. We allow you to easily flag your features and manage them from the LaunchDarkly dashboard.  With LaunchDarkly, you can:
    * Roll out a new feature to a subset of your users (like a group of users who opt-in to a beta tester group), gathering feedback and bug reports from real-world use cases.
    * Gradually roll out a feature to an increasing percentage of users, and track the effect that the feature has on key metrics (for instance, how likely is a user to complete a purchase if they have feature A versus feature B?).
    * Turn off a feature that you realize is causing performance problems in production, without needing to re-deploy, or even restart the application with a changed configuration file.
    * Grant access to certain features based on user attributes, like payment plan (eg: users on the ‘gold’ plan get access to more features than users in the ‘silver’ plan). Disable parts of your application to facilitate maintenance, without taking everything offline.
* LaunchDarkly provides feature flag SDKs for a wide variety of languages and technologies. Check out [our documentation](https://docs.launchdarkly.com/sdk) for a complete list.
* Explore LaunchDarkly
    * [launchdarkly.com](https://www.launchdarkly.com/ "LaunchDarkly Main Website") for more information
    * [docs.launchdarkly.com](https://docs.launchdarkly.com/  "LaunchDarkly Documentation") for our documentation and SDK reference guides
    * [apidocs.launchdarkly.com](https://apidocs.launchdarkly.com/  "LaunchDarkly API Documentation") for our API documentation
    * [blog.launchdarkly.com](https://blog.launchdarkly.com/  "LaunchDarkly Blog Documentation") for the latest product updates
