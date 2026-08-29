import SwiftUI

/// Stereo (left/right) audio level meter driven by the Process Tap stream.
/// Placeholder values for Phase 1; Phase 3 will feed real levels.
struct LevelMeter: View {
    @State private var leftLevel: Double = 0.12
    @State private var rightLevel: Double = 0.16

    var body: some View {
        HStack(spacing: 6) {
            MeterBar(level: leftLevel, color: .green)
            MeterBar(level: rightLevel, color: .green)
        }
    }
}

private struct MeterBar: View {
    let level: Double
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.08))
                Capsule()
                    .fill(color)
                    .frame(width: proxy.size.width * level)
            }
        }
        .frame(height: 8)
    }
}