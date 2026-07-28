import SwiftUI

struct RecordToolSheet: View {
    @EnvironmentObject var themeManager: ThemeManager
    @ObservedObject var recorder: ScreenRecorder

    var body: some View {
        let theme = themeManager.currentTheme

        VStack(spacing: Spacing.lg) {
            Text("Screen Recorder").font(.headline).foregroundStyle(theme.primaryText)
            Text("Captures your screen + audio as HEVC and saves straight to Photos.")
                .font(.caption)
                .foregroundStyle(theme.secondaryText)
                .multilineTextAlignment(.center)

            if recorder.isRecording {
                Text(elapsedLabel)
                    .font(.system(.title, design: .monospaced))
                    .foregroundStyle(.red)
            }

            Button {
                if recorder.isRecording {
                    recorder.stopRecording()
                } else {
                    recorder.startRecording()
                }
            } label: {
                Label(
                    recorder.isRecording ? "Stop Recording" : "Start Recording",
                    systemImage: recorder.isRecording ? "stop.circle.fill" : "record.circle"
                )
            }
            .buttonStyle(PrimaryButtonStyle(colorOverride: recorder.isRecording ? .red : nil))
        }
        .padding(Spacing.lg)
        .alert("Error", isPresented: .constant(recorder.errorMessage != nil)) {
            Button("OK") { recorder.errorMessage = nil }
        } message: {
            Text(recorder.errorMessage ?? "")
        }
    }

    private var elapsedLabel: String {
        let m = Int(recorder.elapsedSeconds) / 60
        let s = Int(recorder.elapsedSeconds) % 60
        return String(format: "%d:%02d", m, s)
    }
}
