# Local podspec for our self-built FFmpegKit.
#
# The .xcframework bundles it vendors are NOT committed — they are downloaded
# into this directory by scripts/fetch-ffmpegkit.sh, which pulls the release
# asset produced by .github/workflows/build-ffmpegkit.yml. Run that script
# once before `pod install` (CI does it automatically).
#
# The pod name differs from upstream but the module name does not: the binary
# is still ffmpegkit.xcframework, so `import ffmpegkit` in FFmpegExporter.swift
# keeps working unchanged.

Pod::Spec.new do |s|
  s.name             = 'ffmpeg-kit-ios-custom'
  s.version          = '6.0'
  s.summary          = 'Self-built FFmpegKit 6.0 for iOS (LGPL v3.0, no GPL libraries).'
  s.description      = <<-DESC
    FFmpegKit 6.0 built from source with libass, fontconfig, freetype and
    fribidi for subtitle burn-in, plus Apple's built-in AudioToolbox,
    AVFoundation and VideoToolbox support. No GPL libraries are enabled, so
    the result is LGPL v3.0 and safe to distribute through the App Store.
  DESC
  s.homepage         = 'https://github.com/arthenica/ffmpeg-kit'
  s.license          = { :type => 'LGPL-3.0', :file => 'LICENSE-ffmpeg-kit.txt' }
  s.author           = 'ARTHENICA Information Technologies'
  s.source           = { :http => 'https://github.com/arthenica/ffmpeg-kit' }

  s.platform         = :ios, '17.0'
  s.requires_arc     = true
  s.static_framework = true

  s.vendored_frameworks = [
    'ffmpegkit.xcframework',
    'libavcodec.xcframework',
    'libavdevice.xcframework',
    'libavfilter.xcframework',
    'libavformat.xcframework',
    'libavutil.xcframework',
    'libswresample.xcframework',
    'libswscale.xcframework'
  ]

  s.libraries = 'z', 'bz2', 'c++', 'iconv'
  s.frameworks = 'AudioToolbox', 'AVFoundation', 'CoreMedia', 'VideoToolbox'
end
