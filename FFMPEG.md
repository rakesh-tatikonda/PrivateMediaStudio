# FFmpeg in this project

## Why we build it ourselves

The editor originally depended on `pod 'ffmpeg-kit-ios-full-gpl'`. That pod no
longer installs. Upstream FFmpegKit was retired, its prebuilt binaries were
removed from CocoaPods, Maven Central and npm on 1 April 2025, and the
repository was archived read-only in June 2025. The podspec still resolves
from the CocoaPods trunk, which is why the failure looks like a clean
dependency graph followed by:

```
curl: (56) The requested URL returned error: 404
```

The download URL points at a GitHub release asset that was deleted. No version
bump fixes this — every tagged version is gone.

There are community mirrors that re-host the old binaries and publish working
podspecs. We do not use them. They serve an unsigned, unaudited binary blob
from a third-party account into an app whose entire premise is that media
never leaves the device, and they are just as capable of vanishing as the
original was. Building from source costs one long CI job and puts the supply
chain back under our control.

## The licensing change that came with it

The old `-full-gpl` variant was GPL v3.0, which conflicts with App Store
distribution. Our build is **LGPL v3.0** instead. FFmpegKit's scripts always
configure FFmpeg with `--enable-version3`, so the output is LGPL unless
`--enable-gpl` is passed; we do not pass it, and we enable no GPL library
(x264, x265, xvidcore, vid.stab, rubberband).

Nothing the editor needs was lost:

| Feature | Before | Now |
|---|---|---|
| Subtitle burn-in | `libass` (GPL build) | `libass` — it is ISC licensed, never needed GPL |
| Scale, pad, colour grade | built-in filters | unchanged |
| HEVC encode | `libx265` (GPL) | `hevc_videotoolbox` — Apple's hardware encoder |
| AAC encode | built-in | unchanged |

Moving to VideoToolbox is a win beyond licensing: hardware encoding is far
faster on device than software x265. The tradeoff is that VideoToolbox has no
constant-quality mode on iOS, so `FFmpegCommandBuilder` targets a
resolution-scaled bitrate instead of `-crf 23`. See `targetBitrateKbps`.

**If you ever add `--enable-gpl`, you are giving up App Store distribution.**

## How it works

1. `.github/workflows/build-ffmpegkit.yml` — run manually, once. Clones the
   archived ffmpeg-kit source, builds an xcframework bundle for arm64 and
   arm64-simulator, and publishes it as a release asset on this repo tagged
   `ffmpegkit-6.0-custom`. Takes 45–90 minutes; macOS runner minutes bill at
   10x, which is why it is not part of normal CI.
2. `scripts/fetch-ffmpegkit.sh` — downloads that asset into
   `Vendor/ffmpeg-kit/` via the GitHub CLI, so it works on private repos too.
   Idempotent, and CI caches the result.
3. `Vendor/ffmpeg-kit/ffmpeg-kit-ios-custom.podspec` — committed; vendors the
   downloaded xcframeworks. The binaries themselves are gitignored.
4. `Podfile` — `pod 'ffmpeg-kit-ios-custom', :path => 'Vendor/ffmpeg-kit'`.

The module name is unchanged, so `import ffmpegkit` in `FFmpegExporter.swift`
needs no edit.

## Local setup

```bash
gh auth login              # once
bash scripts/fetch-ffmpegkit.sh
pod install
```

## LGPL obligations

LGPL requires that users be able to relink against a modified version of the
library. Keep `use_frameworks!` in the Podfile so FFmpeg links dynamically,
and surface the licence texts in Settings. The build workflow copies
`LICENSE-ffmpeg-kit.txt` into the bundle for this purpose. The same applies to
MobileVLCKit, which is LGPL v2.1+.

This is the engineering picture, not legal advice — worth a lawyer's look
before commercial release.

## If the build fails

The most likely causes are Homebrew prerequisites (`autoconf`, `automake`,
`libtool`, `nasm`, `cmake`, `gperf` — the workflow installs them) and Xcode
version drift, since ffmpeg-kit 6.0 predates newer SDKs. The workflow pins
Xcode 15.4 for that reason. Full logs land in `ffmpeg-kit-src/build.log`; add
an artifact upload step if you need to inspect them.
