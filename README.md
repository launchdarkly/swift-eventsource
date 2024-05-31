# LDSwiftEventSource

[![Run CI](https://github.com/launchdarkly/swift-eventsource/actions/workflows/ci.yml/badge.svg)](https://github.com/launchdarkly/swift-eventsource/actions/workflows/ci.yml)
[![CocoaPods](https://img.shields.io/cocoapods/v/LDSwiftEventSource.svg)](https://cocoapods.org/pods/LDSwiftEventSource)
[![Carthage compatible](https://img.shields.io/badge/Carthage-compatible-4BC51D.svg?style=flat)](https://github.com/Carthage/Carthage)
[![SwiftPM compatible](https://img.shields.io/badge/SwiftPM-compatible-4BC51D.svg?style=flat)](https://swift.org/package-manager/)
[![Platform](https://img.shields.io/cocoapods/p/LDSwiftEventSource.svg?style=flat)](https://cocoapods.org/pods/LDSwiftEventSource)

LDSwiftEventSource is a cross platform implementation of the [EventSource specification](https://html.spec.whatwg.org/multipage/server-sent-events.html) written in Swift. It was developed for use in the [LaunchDarkly iOS SDK](https://github.com/launchdarkly/ios-client-sdk). Generated API docs are available on [GitHub Pages](https://launchdarkly.github.io/swift-eventsource/).

## Requirements
- iOS 11.0+ / watchOS 4.0+ / tvOS 11.0+ / macOS 10.13+
- Swift 5.1+

## Installation

### CocoaPods

To use the [CocoaPods](https://cocoapods.org) dependency manager to integrate LDSwiftEventSource into your Xcode project, specify it in your `Podfile`:

```ruby
pod 'LDSwiftEventSource', '~> 3.3'
```

### Carthage

To use the [Carthage](https://github.com/Carthage/Carthage) dependency manager to integrate LDSwiftEventSource into your Xcode project, specify it in your `Cartfile`:

```ogdl
github "LaunchDarkly/swift-eventsource" ~> 3.3
```

### Swift Package Manager

The [Swift Package Manager](https://swift.org/package-manager/) is a dependency manager integrated into the `swift` compiler and Xcode. Note that the LDSwiftEventSource Swift package provides both a `LDSwiftEventSource` product, which is explicitly dynamic, and a `LDSwiftEventSourceStatic` product which is explicitly static.

To integrate LDSwiftEventSource into an Xcode project, go to the project editor, and select `Swift Packages`. From here hit the `+` button and follow the prompts using  `https://github.com/LaunchDarkly/swift-eventsource.git` as the URL.

To include LDSwiftEventSource in a Swift package, simply add it to the dependencies section of your `Package.swift` file. And add the desired product as a dependency for your targets.

<!-- x-release-please-start-version -->
```swift
dependencies: [
    .package(url: "https://github.com/LaunchDarkly/swift-eventsource.git", .upToNextMajor(from: "3.3.0"))
]
```
<!-- x-release-please-end -->

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
