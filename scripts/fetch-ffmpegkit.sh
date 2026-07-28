#!/usr/bin/env bash
#
# Downloads the self-built FFmpegKit xcframework bundle produced by
# .github/workflows/build-ffmpegkit.yml and unpacks it into Vendor/ffmpeg-kit,
# next to the podspec that vendors it.
#
# Requires the GitHub CLI (`gh`) to be installed and authenticated. In CI that
# is automatic via GH_TOKEN; locally run `gh auth login` once. Using `gh`
# rather than a plain curl means this works even if your repo is private.
#
# Run before `pod install`. Idempotent — skips the download if the frameworks
# are already present.

set -euo pipefail

RELEASE_TAG="${FFMPEGKIT_RELEASE_TAG:-ffmpegkit-6.0-custom}"
ASSET="ffmpeg-kit-ios-custom.zip"
DEST="Vendor/ffmpeg-kit"

if [ -d "$DEST/ffmpegkit.xcframework" ]; then
  echo "FFmpegKit already present in $DEST — skipping download."
  exit 0
fi

mkdir -p "$DEST"

echo "Downloading $ASSET from release $RELEASE_TAG..."
gh release download "$RELEASE_TAG" --pattern "$ASSET" --output "$DEST/$ASSET" --clobber

unzip -oq "$DEST/$ASSET" -d "$DEST"
rm -f "$DEST/$ASSET"

if [ ! -d "$DEST/ffmpegkit.xcframework" ]; then
  echo "error: archive did not contain ffmpegkit.xcframework" >&2
  exit 1
fi

echo "FFmpegKit unpacked into $DEST."
