import Foundation

/// Translates an EditorProject into a real FFmpeg argument list. Returns
/// arguments (not a single shell string) so paths with spaces/unicode never
/// need manual quoting — FFmpegExporter passes these straight to
/// FFmpegKit.executeAsync(withArguments:).
///
/// Calibration note: the color-grading slider→filter-parameter mappings below
/// (search "CALIBRATION") are a reasonable starting scale, not values pulled
/// from measured perceptual testing — nudge the multipliers once you can
/// actually preview output on-device against real footage.
enum FFmpegCommandBuilder {

    static func buildExportArguments(
        project: EditorProject,
        outputURL: URL,
        assSubtitlePath: URL?
    ) -> [String] {
        var args: [String] = ["-y"]

        // MARK: Inputs — video clips first, then audio clips, in that order.
        // filter_complex below references video inputs as [0:v]...[n-1:v];
        // audio -map indices are offset by videoClips.count accordingly.
        for clip in project.videoClips {
            args += ["-i", clip.url.path]
        }
        for clip in project.audioClips {
            args += ["-i", clip.url.path]
        }

        let videoCount = project.videoClips.count
        let (width, height) = project.resolution.dimensions

        // MARK: filter_complex — trim each video clip, concat, scale+pad,
        // color grade, then burn in subtitles if present.
        var filterParts: [String] = []
        var trimmedLabels: [String] = []

        for (index, clip) in project.videoClips.enumerated() {
            let label = "vtrim\(index)"
            filterParts.append(
                "[\(index):v]trim=start=\(clip.trimStart):end=\(clip.trimEnd),setpts=PTS-STARTPTS[\(label)]"
            )
            trimmedLabels.append("[\(label)]")
        }

        let concatLabel: String
        if videoCount > 1 {
            concatLabel = "vconcat"
            filterParts.append("\(trimmedLabels.joined())concat=n=\(videoCount):v=1:a=0[\(concatLabel)]")
        } else {
            // Single clip: skip the concat node entirely, just carry the trim
            // label forward — concat=n=1 is legal but pointless overhead.
            concatLabel = "vtrim0"
        }

        var chain = "[\(concatLabel)]"
        var chainStages: [String] = []

        // Scale to target resolution, letterboxing rather than stretching.
        chainStages.append("scale=\(width):\(height):force_original_aspect_ratio=decrease,pad=\(width):\(height):(ow-iw)/2:(oh-ih)/2")

        chainStages.append(contentsOf: colorGradingStages(project.colorGrading))

        if let assSubtitlePath {
            // FFmpeg filter args need literal colons in Windows-style drive
            // paths escaped, but iOS sandbox paths won't contain those — the
            // path still gets wrapped in single quotes since the subtitles
            // filter's own argument parser treats ':' as a sub-option
            // separator otherwise.
            chainStages.append("subtitles=filename='\(escapedForFilter(assSubtitlePath.path))'")
        }

        chain += chainStages.joined(separator: ",") + "[vout]"
        filterParts.append(chain)

        args += ["-filter_complex", filterParts.joined(separator: ";")]
        args += ["-map", "[vout]"]

        // MARK: Audio mapping — original video's own audio (single-clip
        // projects only; see doc comment) plus every imported audio file as
        // its own selectable track, matching the spec's "-map 0:v -map 1:a
        // -map 2:a" pattern.
        if videoCount == 1 {
            args += ["-map", "0:a?"] // "?" = don't fail the export if this clip has no audio track
        }
        for (index, _) in project.audioClips.enumerated() {
            args += ["-map", "\(videoCount + index):a"]
        }

        // MARK: Codec — HEVC per the spec's compression requirement.
        //
        // hevc_videotoolbox rather than libx265: VideoToolbox is Apple's
        // hardware encoder, so it is dramatically faster on device and, just
        // as importantly, it is a built-in FFmpeg encoder rather than an
        // external GPL library. Keeping x265 out is what lets this app link
        // an LGPL-only FFmpeg build (see FFMPEG.md).
        //
        // VideoToolbox encoders are rate-controlled, not CRF-based — there is
        // no -crf or -preset equivalent — so the quality knob is a target
        // bitrate scaled to the output resolution.
        args += ["-c:v", "hevc_videotoolbox"]
        args += ["-b:v", "\(targetBitrateKbps(width: width, height: height))k"]
        args += ["-tag:v", "hvc1"] // required for QuickTime/AVPlayer to recognise HEVC
        args += ["-c:a", "aac", "-b:a", "192k"]
        args += ["-movflags", "+faststart"]

        args += [outputURL.path]
        return args
    }

    // MARK: - Bitrate targeting

    /// Rough bits-per-pixel target for HEVC hardware encoding. VideoToolbox
    /// has no constant-quality mode on iOS, so quality is expressed as a
    /// resolution-scaled bitrate: ~0.07 bits per pixel per frame at 30fps,
    /// which sits close to libx265 -crf 23 in practice, with a floor so that
    /// very small outputs do not end up starved.
    private static func targetBitrateKbps(width: Int, height: Int) -> Int {
        let pixels = Double(width * height)
        let kbps = pixels * 30.0 * 0.07 / 1000.0
        return max(1200, Int(kbps.rounded()))
    }

    // MARK: - Color grading → real FFmpeg filters

    /// Maps the 11 spec'd sliders onto FFmpeg's eq / colorlevels / curves /
    /// vibrance / colorbalance / unsharp / vignette filters. Sliders that are
    /// at their default (0, or 0 for vignette) are omitted from the chain
    /// entirely rather than passed as no-op filter instances — keeps the
    /// command shorter and avoids relying on every filter's neutral-value
    /// behavior being bug-free.
    private static func colorGradingStages(_ settings: ColorGradingSettings) -> [String] {
        var stages: [String] = []

        // Brightness + Saturation → eq. (CALIBRATION: eq's own brightness
        // range is -1...1 but that's extreme; scaled down to stay usable
        // across the slider's full range.)
        if settings.brightness != 0 || settings.saturation != 0 {
            let brightness = settings.brightness * 0.3
            let saturation = 1 + settings.saturation // eq saturation: 0...3, 1 = neutral
            stages.append("eq=brightness=\(f(brightness)):saturation=\(f(saturation))")
        }

        // Whites + Blacks → colorlevels input black/white points.
        // (CALIBRATION: ±0.25 max shift keeps the image from clipping to
        // solid black/white at the slider extremes.)
        if settings.whites != 0 || settings.blacks != 0 {
            let blackPoint = max(0, settings.blacks * 0.25)
            let whitePoint = 1 - max(0, -settings.whites * 0.25)
            stages.append("colorlevels=rimin=\(f(blackPoint)):gimin=\(f(blackPoint)):bimin=\(f(blackPoint)):rimax=\(f(whitePoint)):gimax=\(f(whitePoint)):bimax=\(f(whitePoint))")
        }

        // Highlights + Shadows → curves, lifting/lowering the quarter- and
        // three-quarter-tone points of a master tone curve.
        if settings.highlights != 0 || settings.shadows != 0 {
            let shadowPoint = 0.25 + settings.shadows * 0.1
            let highlightPoint = 0.75 + settings.highlights * 0.1
            stages.append("curves=master='0/0 0.25/\(f(shadowPoint)) 0.75/\(f(highlightPoint)) 1/1'")
        }

        // Vibrance → FFmpeg's dedicated vibrance filter.
        if settings.vibrance != 0 {
            stages.append("vibrance=intensity=\(f(settings.vibrance * 1.5))")
        }

        // Warmth → colorbalance midtone red/blue push (positive = warmer).
        if settings.warmth != 0 {
            let shift = settings.warmth * 0.3
            stages.append("colorbalance=rm=\(f(shift)):bm=\(f(-shift))")
        }

        // Sharpness → standard small-radius unsharp mask.
        if settings.sharpness != 0 {
            stages.append("unsharp=luma_msize_x=5:luma_msize_y=5:luma_amount=\(f(settings.sharpness * 1.5))")
        }

        // Clarity → large-radius unsharp mask, a common approximation for
        // "local contrast" style clarity adjustments.
        if settings.clarity != 0 {
            stages.append("unsharp=luma_msize_x=23:luma_msize_y=23:luma_amount=\(f(settings.clarity * 0.6))")
        }

        // Vignette (0...1, 0 = off).
        if settings.vignette > 0 {
            let angle = Double.pi / 2 * (1 - settings.vignette * 0.8)
            stages.append("vignette=angle=\(f(angle)):mode=backward")
        }

        return stages
    }

    private static func f(_ value: Double) -> String {
        String(format: "%.3f", value)
    }

    /// Escapes a path for safe embedding inside an FFmpeg filtergraph string
    /// value (distinct from shell escaping — filter_complex args are passed
    /// as a single array element, never through a shell). FFmpeg's own
    /// filtergraph parser treats `:` as an option separator and `\` as an
    /// escape character even inside single quotes in some parsing paths, so
    /// both get neutralized alongside the quote itself. Paths handed to this
    /// are currently always app-generated UUID filenames, not attacker- or
    /// user-controlled strings, but escaping it properly means that stays a
    /// non-issue rather than an unstated assumption.
    private static func escapedForFilter(_ path: String) -> String {
        path
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "'\\''")
            .replacingOccurrences(of: ":", with: "\\:")
    }
}
