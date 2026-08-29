import SwiftUI

/// Big red circular Record button. Inner square toggles into a stop-style
/// icon while recording/paused per the mockup.
struct RecordButton: View {
    let state: RecordingState
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(state != .idle ? Color.orange : Color.red)
                    .frame(width: 64, height: 64)
                RoundedRectangle(cornerRadius: state != .idle ? 6 : 8, style: .continuous)
                    .fill(.white)
                    .frame(width: state != .idle ? 18 : 26, height: state != .idle ? 18 : 26)
            }
        }
        .buttonStyle(.plain)
        .help(state != .idle ? "Stop recording" : "Start recording")
    }
}

/// Pause button (two vertical bars).
struct PauseButton: View {
    let state: RecordingState
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.12))
                    .frame(width: 56, height: 56)
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(.white)
                        .frame(width: 6, height: 22)
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(.white)
                        .frame(width: 6, height: 22)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(state == .idle)
        .opacity(state == .idle ? 0.35 : 1)
        .help(state == .paused ? "Resume" : "Pause")
    }
}