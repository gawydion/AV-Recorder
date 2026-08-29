import SwiftUI

/// Live system-audio level meter driven by the Process Tap stream.
struct LevelMeter: View {
    let level: Double

    var body: some View {
        MeterBar(level: level, color: .green)
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