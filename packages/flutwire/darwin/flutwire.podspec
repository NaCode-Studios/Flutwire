#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint flutwire.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'flutwire'
  s.version          = '0.1.0'
  s.summary          = 'Network inspector for Flutter that lives in the notification shade.'
  s.description      = <<-DESC
Records the HTTP calls a Flutter app makes and opens them from a notification.
This pod is the iOS and macOS half: the notification and the share sheet.
                       DESC
  s.homepage         = 'https://github.com/NaCode-Studios/Flutwire'
  s.license          = { :type => 'Apache-2.0', :file => '../LICENSE' }
  s.author           = { 'NaCode Studios' => 'https://github.com/NaCode-Studios' }
  s.source           = { :path => '.' }
  s.source_files     = 'flutwire/Sources/flutwire/**/*.swift'
  s.ios.dependency 'Flutter'
  s.osx.dependency 'FlutterMacOS'
  s.ios.deployment_target = '15.0'
  s.osx.deployment_target = '11.0'
  s.swift_version = '5.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.resource_bundles = { 'flutwire_privacy' => ['flutwire/Sources/flutwire/PrivacyInfo.xcprivacy'] }
end
