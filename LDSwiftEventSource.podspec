Pod::Spec.new do |ld|

  ld.name         = "LDSwiftEventSource"
  ld.version      = "0.1.0"
  ld.summary      = "Swift EventSource library"

  ld.description  = <<-DESC
                    The best EventSource library around
                   DESC

  ld.homepage     = "https://github.com/launchdarkly/swift-eventsource"

  ld.license      = { :type => "Apache License, Version 2.0", :file => "LICENSE.txt" }

  ld.author       = { "LaunchDarkly" => "team@launchdarkly.com" }

  ld.ios.deployment_target     = "8.0"
  ld.watchos.deployment_target = "2.0"
  ld.tvos.deployment_target    = "9.0"
  ld.osx.deployment_target     = "10.10"

  ld.source       = { :git => "https://github.com/launchdarkly/swift-eventsource.git", :tag => 'master'}

  ld.source_files = "LDSwiftEventSource/LDSwiftEventSource/**/*.{h,m,swift}"

  ld.requires_arc = true

  ld.swift_version = '5.0'

end
