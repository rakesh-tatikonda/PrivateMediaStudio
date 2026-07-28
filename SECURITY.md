# Security audit

A pass over the codebase looking specifically for security issues (as
distinct from the functional "known gaps" tracked in README.md). Findings
below, ranked roughly by severity, all patched in this pass.

## 1. Subtitle override-tag injection (Editor) — the serious one

**File:** `Editor/SRTToASSConverter.swift`

Subtitle files are untrusted input almost by definition — people download
`.srt` files from third-party sites to match up with a given video, all the
time. The Editor's burn-in feature converted `.srt` → `.ass` and embedded
each subtitle line's raw text directly into the output, only escaping
newlines. ASS's `{...}` syntax opens an "override block" that the renderer
(libass, via FFmpeg's `subtitles` filter) interprets as styling/position/
animation directives rather than literal text — so a crafted subtitle file
could inject its own `\pos`, `\move`, `\t` (transform), etc. tags into what
was supposed to be plain dialogue.

This is exactly the bug class behind the real, disclosed 2017 subtitle RCEs
in VLC, Kodi, Popcorn Time, and Stremio (Check Point's "subtitle attack"
research) — malicious tag content triggering parser bugs in the subtitle
renderer itself. I can't audit libass's own C parser from here, but the app
can and should refuse to hand it attacker-controlled tag syntax in the first
place.

**Fix:** strip `{` / `}` from subtitle text before embedding (replaced with
visually-similar fullwidth characters). Without an unescaped `{`, there's no
way to open an override block at all, which closes the injection path
regardless of what's inside it.

## 2. Orphaned Keychain secret — no way to delete a saved server

**Files:** `Streams/StreamsViewModel.swift`, `Streams/SMBFTPConnectionSheet.swift`

There was a "Connect to Server" flow that saves an SMB/FTP password to
Keychain, but no corresponding delete flow anywhere in the app. Once saved, a
credential had no user-facing removal path short of deleting the entire app
— which sits awkwardly next to this app's whole stated premise ("zero data
collection", full local control).

**Fix:** added `StreamsViewModel.deleteServerConnection(_:)` (removes both
the SwiftData row and the Keychain entry) and a delete UI (swipe-to-delete)
in the server connection sheet.

## 3. Orphaned thumbnail files on media deletion

**File:** `Streams/StreamsViewModel.swift`

Deleting a `MediaItem` removed it from the SwiftData library but never
touched its cached poster thumbnail on disk — thumbnails accumulated
indefinitely for media the user had explicitly removed.

**Fix:** `delete(_:)` now also removes the cached thumbnail file.

## 4. Loose URL scheme validation (Captions)

**File:** `Captions/CaptionsViewModel.swift`

The "Media URL" input checked only that a scheme was *present*, not that it
was `http`/`https` — so a `file://` or other non-network scheme string would
pass validation and get handed to `URLSession.shared.download(from:)`.
Streams' equivalent URL-add flow already restricted this correctly; Captions
didn't.

**Fix:** restricted to `http`/`https`, matching Streams.

## 5. Unbounded subtitle file read (DoS)

**File:** `Streams/SRTParser.swift`

Subtitle files (untrusted input, per #1) were read fully into memory with no
size limit. A maliciously oversized `.srt` could force a large, avoidable
allocation.

**Fix:** added a 10MB cap (real `.srt` files are a few hundred KB at most)
before reading.

## 6. Data-at-rest protection was implicit, not explicit

**Files:** `App/PrivateMediaStudioApp.swift`, `Captions/TranscriptExporter.swift`

The SwiftData store (media library metadata, saved server hostnames/
usernames, subtitle sync settings) and exported transcripts (which can
contain sensitive spoken content — voice memos, private conversations) were
relying on whatever the platform's default file-protection class happens to
resolve to, rather than an explicit, reviewed choice.

**Fix:** both now explicitly set
`.completeUntilFirstUserAuthentication` — encrypted at rest before the
device's first unlock after boot, but still accessible afterward (which the
app's own Background Translations / Background Live Mic settings depend on;
the stricter `.complete` would break those while locked). Exported
transcripts get the same treatment, since they land in Documents and are
reachable via the Files app / sharing.

## 7. ATS scope wider than needed

**File:** `Info.plist`

`NSAllowsLocalNetworking` was set alongside `NSAllowsArbitraryLoadsForMedia`.
The latter is what the app's LAN/self-hosted media streaming actually needs
(scoped to AVFoundation media loading); the former applies to *all*
URLSession requests to local-network hosts, which nothing in the app actually
uses — the only URLSession network call (Captions' Media URL fetch) targets
public URLs, and VLCKit/FFmpegKit's own SMB/FTP/HLS networking doesn't go
through ATS regardless of this key.

**Fix:** removed `NSAllowsLocalNetworking`. If a plain-HTTP *LAN* stream
(not SMB/FTP, an actual `http://192.168.x.x/...` URL) ever needs to load
through `URLSession` specifically, this is the first thing to reconsider.

## 8. FFmpeg filtergraph path-escaping was incomplete

**File:** `Editor/FFmpegCommandBuilder.swift`

The subtitle burn-in filter's file path was only escaped for single quotes,
not colons or backslashes, which FFmpeg's own filtergraph parser also treats
specially. Not currently exploitable — the path is always an app-generated
UUID filename, never user- or attacker-controlled — but hardened anyway so
that stays a fact about the code rather than an assumption resting on it.

**Fix:** added `:` and `\` escaping alongside the existing `'` handling.

## 9. Signing secrets weren't excluded from git

**File:** `.gitignore`

RELEASE.md (added in Phase 4) walks through generating a private key,
distribution certificate, provisioning profile, and App Store Connect API
key locally via `openssl`. None of those file patterns were in `.gitignore`
— a routine `git add .` while following that guide could commit real signing
secrets to the repo.

**Fix:** added `*.p12`, `*.key`, `*.csr`, `*.cer`, `*.pem`,
`*.mobileprovision`, `AuthKey_*.p8`, and the intermediate `.b64` files.

## Reviewed and already sound (no change needed)

- **Keychain configuration** (`Security/KeychainManager.swift`): correctly
  uses `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` and
  `kSecAttrSynchronizable = false` — no iCloud Keychain sync, inaccessible
  before first unlock.
- **Photos permission scope**: uses `.addOnly`, not full read/write library
  access — least privilege for a feature that only ever saves, never reads.
- **FFmpeg command construction**: built as an argument array, never a shell
  string, so there's no shell-injection surface regardless of what's in a
  file path.
- **No hardcoded secrets or API keys anywhere** — consistent with the
  zero-cloud-dependency design; there's nothing to leak because nothing
  calls out to a service that would need one.

## Residual, lower-severity items not fixed (flagged, not blocking)

- Editor's app-owned temp copies (imported clips/audio/subtitles) aren't
  guaranteed to be cleaned up if the user backs out of an edit without
  removing them or exporting — relies on iOS's own periodic temp-directory
  purging rather than explicit app cleanup. Storage hygiene, not a data
  exposure risk (still inside the app's own sandbox).
- FFmpeg failure messages surface the tool's own log/stack-trace text to the
  user, which can include local sandbox file paths. iOS sandbox paths don't
  reveal anything identifying (no real usernames, random per-install), so
  this is low-severity, but a future pass could truncate/sanitize it for
  display.
- Swift `String` values (e.g., a Keychain password briefly in memory during
  entry/use) aren't zeroed deterministically — a general limitation of using
  `String` for secrets in Swift, not specific to this app, and disproportionate
  to fix relative to this app's threat model (a lost/stolen locked device,
  not live memory forensics on a running app).
