#!/usr/bin/env bash
#
# Downloads the self-built FFmpegKit xcframework bundle produced by
# .github/workflows/build-ffmpegkit.yml and unpacks it into Vendor/ffmpeg-kit,
# next to the podspec that vendors it, then strips bitcode from the binaries.
#
# Requires the GitHub CLI (`gh`), authenticated. In CI that is automatic via
# GH_TOKEN; locally run `gh auth login` once. Using `gh` rather than plain curl
# means this works even if the repo is private.
#
# Run before `pod install`. Idempotent.

set -euo pipefail

RELEASE_TAG="${FFMPEGKIT_RELEASE_TAG:-ffmpegkit-6.0-custom}"
ASSET="ffmpeg-kit-ios-custom.zip"
DEST="Vendor/ffmpeg-kit"
STRIP_MARKER="$DEST/.bitcode-stripped"

mkdir -p "$DEST"

if [ -d "$DEST/ffmpegkit.xcframework" ]; then
  echo "FFmpegKit already present in $DEST — skipping download."
else
  echo "Downloading $ASSET from release $RELEASE_TAG..."
  gh release download "$RELEASE_TAG" --pattern "$ASSET" --output "$DEST/$ASSET" --clobber
  unzip -oq "$DEST/$ASSET" -d "$DEST"
  rm -f "$DEST/$ASSET"

  if [ ! -d "$DEST/ffmpegkit.xcframework" ]; then
    echo "error: archive did not contain ffmpegkit.xcframework" >&2
    exit 1
  fi
fi

# ffmpeg-kit 6.0 predates Apple dropping bitcode, and its build scripts still
# embed a bitcode segment. App Store validation rejects any executable that
# carries one ("Invalid Executable ... contains bitcode"), so strip every slice
# of every framework.
#
# ExportOptions' compileBitcode=false does NOT cover this — that controls
# whether Xcode recompiles from bitcode, not whether vendored binaries contain
# it. Stripping takes seconds; rebuilding without it would take another 90
# minutes.
#
# The marker matters because CI caches Vendor/ffmpeg-kit: on a cache hit the
# download is skipped, and without this check the restored (unstripped)
# binaries would sail through to a rejected upload.
if [ -f "$STRIP_MARKER" ]; then
  echo "Bitcode already stripped."
elif command -v xcrun >/dev/null 2>&1; then
  echo "Stripping bitcode from vendored frameworks..."
  while IFS= read -r -d '' framework; do
    binary="$framework/$(basename "$framework" .framework)"
    [ -f "$binary" ] || continue
    if xcrun bitcode_strip -r "$binary" -o "$binary.nobitcode" 2>/dev/null; then
      mv "$binary.nobitcode" "$binary"
    else
      rm -f "$binary.nobitcode"
    fi
  done < <(find "$DEST" -name "*.framework" -type d -print0)
  touch "$STRIP_MARKER"
  echo "Bitcode stripped."
else
  echo "warning: xcrun unavailable, skipping bitcode strip (non-macOS host)." >&2
fi

echo "FFmpegKit ready in $DEST."
