#!/usr/bin/env bash
#
# Substitutes the placeholders committed to this repo with real values taken
# from environment variables:
#
#   __BUNDLE_ID__     <- $APP_BUNDLE_ID              (GitHub secret)
#   __TEAM_ID__       <- $APPLE_TEAM_ID              (GitHub secret)
#   __PROFILE_NAME__  <- $PROVISIONING_PROFILE_NAME  (extracted in CI from the
#                                                     .mobileprovision itself)
#
# The defaults below are enough to build and run in the simulator. They are
# deliberately NOT valid for signed device builds — that path requires the
# real secrets.
#
# This script contains no secrets and is safe to commit.
#
# NOTE: it edits tracked files in place. Run `git checkout -- .` afterwards
# locally so real values are never committed. CI checks out fresh each run.

set -euo pipefail

BUNDLE_ID="${APP_BUNDLE_ID:-com.example.privatemediastudio}"
TEAM_ID="${APPLE_TEAM_ID:-0000000000}"
PROFILE_NAME="${PROVISIONING_PROFILE_NAME:-}"

# BSD sed (macOS) requires an argument to -i; GNU sed (Linux/WSL) must not
# have one. Detect rather than guess, so this runs in both places.
if sed --version >/dev/null 2>&1; then
  sed_inplace() { sed -i "$@"; }        # GNU
else
  sed_inplace() { sed -i '' "$@"; }     # BSD
fi

FILES=(
  "project.yml"
  "PrivateMediaStudio/Info.plist"
  "ExportOptions.plist"
  "ExportOptionsAdHoc.plist"
)

for f in "${FILES[@]}"; do
  sed_inplace \
    -e "s|__BUNDLE_ID__|${BUNDLE_ID}|g" \
    -e "s|__TEAM_ID__|${TEAM_ID}|g" \
    -e "s|__PROFILE_NAME__|${PROFILE_NAME}|g" \
    "$f"
done

# Fail loudly rather than handing a half-configured project to xcodebuild.
if grep -q "__BUNDLE_ID__\|__TEAM_ID__\|__PROFILE_NAME__" "${FILES[@]}"; then
  echo "error: unsubstituted placeholders remain" >&2
  exit 1
fi

# Guard against the more insidious failure: a file that was never updated to
# use the placeholders at all. Substitution then finds nothing, reports
# success, and the stale literal reaches xcodebuild — which fails much later
# with "No profiles for team 'REPLACE_WITH_YOUR_TEAM_ID'" or similar.
if grep -q "REPLACE_WITH_YOUR_TEAM_ID\|com\.privatemediastudio" "${FILES[@]}"; then
  echo "error: a stale pre-placeholder value is still present. One of these" >&2
  echo "       files was not updated to the placeholder scheme:" >&2
  grep -ln "REPLACE_WITH_YOUR_TEAM_ID\|com\.privatemediastudio" "${FILES[@]}" >&2
  exit 1
fi

# Never echoes the values themselves. GitHub masks registered secrets in log
# output, but the profile name is not a registered secret and can contain the
# team name, so it stays unprinted too.
echo "Identifiers configured."
