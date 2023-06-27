Pod::Spec.new do |s|
  s.name             = 'SecureXPC'
  s.version          = '0.8.0'
  s.summary          = 'SecureXPC protects against XPC exploitation on macOS by performing security checks agains the calling process.'

  s.homepage         = 'https://github.com/trilemma-dev/SecureXPC'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'Josh Kaplan' => 'https://github.com/jakaplan' }
  s.source           = { :git => 'https://github.com/trilemma-dev/SecureXPC.git', :tag => s.version.to_s }

  s.osx.deployment_target = '10.13'
  s.swift_version = '5.5'

  s.source_files = 'Sources/SecureXPC/**/*'
end
