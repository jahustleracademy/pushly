Pod::Spec.new do |s|
  s.name           = 'PushlyNative'
  s.version        = '1.0.0'
  s.summary        = 'Pushly native iOS screen-time and pose-detection foundation'
  s.description    = 'Native AVFoundation/Vision pose tracking and Family Controls bridge for Pushly.'
  s.author         = ''
  s.homepage       = 'https://docs.expo.dev/modules/'
  s.platforms      = {
    :ios => '16.0'
  }
  s.source         = { git: '' }
  s.static_framework = true

  s.dependency 'ExpoModulesCore'
  s.dependency 'MediaPipeTasksVision'

  # Swift/Objective-C compatibility
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
  }

  s.source_files = "**/*.{h,m,mm,swift,hpp,cpp}"
  s.exclude_files = "**/*Tests.swift"
  s.resource_bundles = {
    'PushlyNativeResources' => ['Models/*.task']
  }

  s.test_spec 'UnitTests' do |test_spec|
    test_spec.source_files = "**/*Tests.swift"
    test_spec.requires_app_host = false
  end
end
