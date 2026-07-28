platform :ios, '17.0'
use_frameworks!

target 'PrivateMediaStudio' do
  # Phase 2 — advanced media player (MKV/AVI/HLS/VR/AirPlay/SMB/FTP, VLCMediaListPlayer)
  pod 'MobileVLCKit', '~> 3.6'

  # Phase 3 — local NLE: scale/color/mux/subtitle burn-in (GPL variant needed for
  # the `subtitles` filter, which links libass). Review FFmpegKit's licensing
  # notes before commercial App Store distribution.
  pod 'ffmpeg-kit-ios-full-gpl', '~> 6.0'
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '17.0'
      config.build_settings['EXCLUDED_ARCHS[sdk=iphonesimulator*]'] = 'arm64' if target.name.include?('VLCKit') || target.name.include?('ffmpeg')
    end
  end
end
