Pod::Spec.new do |s|
  s.name         = "LDSwiftEventSource"
  s.version      = "2.0.0"
  s.summary      = "Swift EventSource library"
  s.homepage     = "https://github.com/launchdarkly/swift-eventsource"
  s.license      = { :type => "Apache License, Version 2.0", :file => "LICENSE.txt" }
  s.author       = { "LaunchDarkly" => "sdks@launchdarkly.com" }

  s.ios.deployment_target     = "11.0"
  s.watchos.deployment_target = "4.0"
  s.tvos.deployment_target    = "11.0"
  s.osx.deployment_target     = "10.13"

  s.source       = { :git => s.homepage + '.git', :tag => s.version}
  s.source_files = "Source/**/*.swift"

  s.swift_versions = ['5.0', '5.1', '5.2', '5.3', '5.4', '5.5', '5.6', '5.7']
end
