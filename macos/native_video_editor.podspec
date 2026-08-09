Pod::Spec.new do |s|
  s.name             = 'native_video_editor'
  s.version          = '0.3.0'
  s.summary          = 'A Flutter plugin for native video edits using AVFoundation.'
  s.description      = <<-DESC
A Flutter plugin for native video edits using AVFoundation on macOS.
                       DESC
  s.homepage         = 'https://github.com/MuhammadFahad0/native_video_editor'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Muhammad Fahad' => 'fahad@example.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'FlutterMacOS'

  s.platform = :osx, '10.15'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'
end
