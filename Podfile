platform :ios, '17.0'
use_frameworks!

target 'PrivateMediaStudio' do
  # Phase 2 — advanced media player (MKV/AVI/HLS/VR/AirPlay/SMB/FTP,
  # VLCMediaListPlayer). libVLC is LGPL v2.1+, which VideoLAN relicensed
  # specifically to permit App Store distribution, so this one is fine as-is.
  # Keep use_frameworks! above: LGPL compliance relies on dynamic linking.
  pod 'MobileVLCKit', '~> 3.6'

  # Phase 3 — local NLE: scale/color/subtitle burn-in.
  #
  # Upstream ffmpeg-kit is retired and its binaries were removed from
  # CocoaPods on 2025-04-01, so 'ffmpeg-kit-ios-full-gpl' 404s on download.
  # We build our own instead — see FFMPEG.md and build-ffmpegkit.yml.
  #
  # Ours is LGPL, not GPL: libass (ISC) covers subtitle burn-in and the
  # hardware VideoToolbox encoder replaces libx265, so no GPL library is
  # linked and App Store distribution stays possible.
  #
  # Run scripts/fetch-ffmpegkit.sh before `pod install` to populate this path.
  pod 'ffmpeg-kit-ios-custom', :path => 'Vendor/ffmpeg-kit'
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '17.0'
    end
  end
end

# NOTE: the previous EXCLUDED_ARCHS[sdk=iphonesimulator*] = 'arm64' hack is
# gone. It existed because the old prebuilt binaries had no arm64 simulator
# slice, but it breaks on Apple-silicon runners and Macs. Our build produces
# arm64-simulator explicitly. If MobileVLCKit turns out to lack an arm64
# simulator slice on your pinned version, re-add the exclusion scoped to that
# pod alone rather than to every target.
