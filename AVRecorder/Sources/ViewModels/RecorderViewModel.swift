import Foundation
import SwiftUI

// MARK: - Recording State

enum RecordingState: Equatable {
    case idle
    case recording
    case paused

    var label: String {
        switch self {
        case .idle: return "Idle"
        case .recording: return "Recording…"
        case .paused: return "Paused"
        }
    }

    var tint: Color {
        switch self {
        case .idle: return .secondary
        case .recording: return .red
        case .paused: return .orange
        }
    }
}

// MARK: - View Model

@MainActor
final class RecorderViewModel: ObservableObject {
    @Published private(set) var state: RecordingState = .idle

    var isRecording: Bool { state != .idle }

    func toggleRecoding() {
        switch state {
        case .idle:
            state = .recording
        case .recording, .paused:
            stop()
        }
    }

    func togglePause() {
        switch state {
        case .recording:
            state = .paused
        case .paused:
            state = .recording
        case .idle:
            break
        }
    }

    func stop() {
        state = .idle
    }
}