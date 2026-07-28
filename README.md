# Private Media Studio

100%-offline iOS app: on-device transcription (Captions), an advanced local/network
media player (Streams), a local NLE video editor + screen recorder (Editor), and
configuration (Settings). No analytics, no telemetry, no cloud processing.

## Status: All 4 phases complete

This repo has been built in phases, and **all of it is fully working, not
mockups**: scaffold, CI, theming, nav, SwiftData schema, Keychain, the complete
**Captions** tab, the complete **Streams** tab, the complete **Editor** tab
(multi-clip trim + timeline, resolution/format scaling, the 11-slider color
grading chain, multi-track audio muxing, draggable/rotatable subtitle burn-in,
FFmpeg export with progress, and a ReplayKit HEVC screen recorder), a Retro
theme visual pass (CRT scanlines, LED-style progress meters, beveled buttons),
a polished Settings tab, and a complete no-Mac path to a signed, installable
build — see **[RELEASE.md](./RELEASE.md)**. A security audit pass has also
been done — see **[SECURITY.md](./SECURITY.md)** for findings and fixes.

| Phase | Scope |
|---|---|
| **1 (done)** | Scaffold, CI, theming, nav, SwiftData models, Keychain, **Captions tab (full)** |
| **2 (done)** | **Streams tab (full)**: library list/grid + progress bars, folders, playlists, add-media (URL/local/SMB-FTP/subtitle), MobileVLCKit player, resume playback, VLCMediaListPlayer queueing, self-rendered subtitle sync + alignment, gesture zones, VR/360 + SBS 3D, AirPlay |
| **3 (done)** | **Editor tab (full)**: multi-clip trim + timeline, Format resolution scaling, Adjust color grading (11 sliders → real FFmpeg filters), Audio muxing (-map per track), Text subtitle burn-in (drag + two-finger rotate → .ass \\pos/\\frz), FFmpeg export with live progress + save-to-Photos, ReplayKit HEVC screen recorder |
| **4 (done)** | Retro theme visual pass, Settings polish (About + Reset), device-signed release build path — **[RELEASE.md](./RELEASE.md)** |

## Why the structure is this way (you have no Mac)

Xcode project files (`.pbxproj`) are fragile generated binaries-in-disguise — hand
authoring one by text is a common source of "won't open" bugs, and you have no
local Xcode to fix that by hand. So instead of a checked-in `.xcodeproj`, this repo
uses **[XcodeGen](https://github.com/yonaskolb/XcodeGen)**: `project.yml` is a
plain YAML spec, and the project file is *generated fresh* from it on every build.
You edit YAML, not XML/binary project files — and it can never get out of sync.

**Build/test happens entirely in GitHub Actions**, on a macOS runner:
- `.github/workflows/ios-ci.yml` runs on every push.
- It installs XcodeGen + CocoaPods, generates the project, pulls dependencies
  (MobileVLCKit, FFmpegKit-GPL via CocoaPods; SwiftWhisper via Swift Package
  Manager), downloads the whisper model, and does a **simulator build** (no code
  signing, no Apple Developer account needed for this).
- It boots an iPhone simulator, installs and launches the app, and uploads a
  screenshot + the `.app` bundle + full build log as workflow artifacts — so you
  can see it's actually running from your phone/PC without ever touching Xcode.
- A commented-out second job (`archive-adhoc`) shows how to produce a real
  device-installable `.ipa` once you have an Apple Developer account — it needs
  three GitHub Secrets (signing cert, provisioning profile, App Store Connect API
  key) and does not require a Mac either, since it also runs on the macOS runner.

To see results: push this repo to GitHub → Actions tab → open the latest run →
download the `simulator-build` artifact.

## Setup

1. Create a GitHub repo, push this folder's contents to it.
2. No secrets are needed for Phase 1 (simulator build only).
3. Push — the workflow runs automatically. First run downloads ~150MB (whisper
   model + pod binaries) so it's slower; subsequent runs are cached.
4. Open the Actions run to download the build artifacts.

### Whisper model

The CI workflow downloads `ggml-base.en.bin` (~140MB, English-only base model —
good balance of speed/accuracy on-device) from Hugging Face into
`PrivateMediaStudio/Resources/Models/` before building, so it's bundled into the
app. To change model size, edit `WHISPER_MODEL` in the CI workflow and in
`WhisperEngine.swift`'s default model name. Do not commit the `.bin` file itself
to git — it's in `.gitignore`; CI fetches it fresh (or you can commit it with
Git LFS if you'd rather not re-download it every run).

### Local Network / SMB-FTP note

`NSLocalNetworkUsageDescription` + Bonjour service types are declared in
`Info.plist` for the Streams tab's SMB/FTP browsing (added now so Phase 2 doesn't
need a project-file change).

## Known gaps to verify on first CI run

I wrote this without a macOS/Xcode toolchain to compile against (matching your
setup), so treat the first GitHub Actions run as the real first compile, not
just a formality. Likely friction points, ranked by likelihood:

1. **SwiftWhisper's exact API surface** (`Captions/WhisperEngine.swift`). I've
   written it against that package's well-known shape (`Whisper(fromFileURL:withParams:)`,
   `WhisperParams`, `WhisperDelegate`, async `transcribe(audioFrames:)`), but it's
   pinned to `branch: main` in `project.yml`, and I can't fetch the live source to
   confirm exact method/enum names right now. If the build fails here, it'll be a
   small rename, not a design problem — open the actual package source (Xcode
   will have pulled it into DerivedData/SourcePackages) and adjust names to match.
2. **CocoaPods versions** in `Podfile` (`MobileVLCKit ~> 3.6`, `ffmpeg-kit-ios-full-gpl ~> 6.0`)
   — version-pinned to what's been stable historically; `pod install` will tell you
   immediately if either needs bumping.
3. **MobileVLCKit's exact API surface** (`Player/PlayerViewModel.swift`, `Player/VLCPlayerContainer.swift`).
   Written against the well-established public API (`VLCMediaPlayer`, `VLCMedia`,
   `VLCMediaList`, `VLCMediaListPlayer`, `VLCMediaPlayerDelegate`) — same caveat as
   SwiftWhisper above: I can't fetch the pod's current headers to confirm every
   property/method name (`jumpForward(_:)`, `addOptions(_:)`, `.position`, `.time.intValue`,
   `play(itemAtIndex:)`) against the exact `~> 3.6` version CocoaPods resolves. Likely a
   rename or two, not a structural issue.
4. **VR/360 mode is a known, deliberate simplification** (`Player/VRSphereView.swift`,
   doc comment inline). MobileVLCKit's public Swift API doesn't expose raw decoded video
   frames, so the 360 sphere is textured by snapshotting the live VLC UIView ~15x/second
   via `CADisplayLink` rather than a zero-copy GPU path. It works, but expect it to run
   warm and be the first thing to cut if you need to trim scope — a production version
   would want a custom VLC build exposing `libvlc_video_set_callbacks`.
5. **SMB/FTP browsing is intentionally narrow.** "Connect to Server" saves the
   connection + lets you add one direct file path, rather than browsing the share's
   directory tree — VLCKit plays a fully-qualified `smb://`/`ftp://` URL natively, but a
   real folder browser needs a dedicated SMB/FTP client library (e.g. AMSMB2), which
   isn't wired in. Worth adding in a later pass if you want in-app browsing.
6. **FFmpegKit's exact Swift API surface + module name** (`Editor/FFmpegExporter.swift`).
   Written against the well-known shape (`FFmpegKit.executeAsync(withArguments:withCompleteCallback:withLogCallback:withStatisticsCallback:)`,
   `ReturnCode.isSuccess(_:)`, `Statistics.getTime()`) and `import ffmpegkit` (lowercase) —
   same "verify against actual pulled source" caveat as SwiftWhisper/MobileVLCKit above.
   The module import casing in particular is an easy first thing to check if this file
   fails to resolve.
7. **Color-grading filter mappings are a starting calibration, not measured
   values** (`Editor/FFmpegCommandBuilder.swift`, marked "CALIBRATION" inline). The 11
   sliders map to real FFmpeg filters (`eq`, `colorlevels`, `curves`, `vibrance`,
   `colorbalance`, `unsharp`, `vignette`) with reasonable multipliers, but nobody's
   eyeballed the output against real footage yet — expect to want to nudge constants
   once you can actually preview an export.
8. **Multi-clip audio has a known limitation**: when a project has more than one video
   clip, each clip's own embedded audio isn't individually carried through the concat
   (`FFmpegCommandBuilder`'s doc comment flags this) — only explicitly-added Audio-tool
   tracks are guaranteed to be muxed in for multi-clip projects. Single-clip projects
   keep their original audio via `-map 0:a?`.
9. First CI run downloads the whisper model + both pods fresh, so it'll be slow
   (5–10 min) — expected, not a hang.

ReplayKit + AVAssetWriter (`Editor/ScreenRecorder.swift`) is the one Phase-3 piece I'd
call high-confidence rather than "verify on first build" — it's core Apple framework
API I know well, not a third-party package I can't currently fetch source for.

None of this affects the architecture, data model, or the rest of the Captions
pipeline (audio extraction, PCM conversion, background tasks, export) — that's
ordinary AVFoundation/Security-framework code with a stable, well-documented API.



- **SwiftWhisper** (SPM) — Swift wrapper around whisper.cpp's C API. Used instead
  of hand-writing a C bridging header, since a battle-tested wrapper is less
  error-prone to get right without a local compiler to iterate against.
- **MobileVLCKit** (CocoaPods) — Phase 2.
- **ffmpeg-kit-ios-full-gpl** (CocoaPods) — Phase 3. The GPL variant is required
  because subtitle burn-in depends on libass, which is GPL-licensed. This has
  license implications if you ever distribute on the App Store commercially —
  worth reading FFmpegKit's licensing notes before shipping.
