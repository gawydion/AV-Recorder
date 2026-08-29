import SwiftUI

/// Status text with clear states: Idle → Recording… → Paused.
struct StatusLabel: View {
    let state: RecordingState

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(state.tint)
                .frame(width: 8, height: 8)
            Text(state.label)
                .font(.callout.weight(.medium))
                .foregroundStyle(state.tint)
        }
        .frame(minWidth: 110, alignment: .trailing)
    }
}