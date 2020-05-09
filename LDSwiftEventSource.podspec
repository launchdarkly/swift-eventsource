Pod::Spec.new do |s|
  s.name         = "LDSwiftEventSource"
  s.version      = "0.1.0"
  s.summary      = "Swift EventSource library"
  s.homepage     = "https://github.com/launchdarkly/swift-eventsource"
  s.license      = { :type => "Apache License, Version 2.0", :file => "LICENSE.txt" }
  s.author       = { "LaunchDarkly" => "team@launchdarkly.com" }

  s.ios.deployment_target     = "10.0"
  s.watchos.deployment_target = "3.0"
  s.tvos.deployment_target    = "10.0"
  s.osx.deployment_target     = "10.12"

  s.source       = { :git => s.homepage + '.git', :tag => v + s.version}
  s.source_files = "Source/**/*.swift"

  s.swift_versions = ['5.0', '5.1', '5.2']
end
