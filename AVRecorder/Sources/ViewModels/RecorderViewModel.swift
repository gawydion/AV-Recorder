import Foundation
import SwiftUI
import AVFoundation
import CoreMedia

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
    private(set) var lastRecordedURL: URL?

    let camera = CameraManager()
    private let engine = RecordingEngine()
    private let audioCapturer = SystemAudioCapturer()

    var isRecording: Bool { state != .idle }

    func toggleRecoding() {
        switch state {
        case .idle:
            startRecording()
        case .recording, .paused:
            stop()
        }
    }

    func togglePause() {
        switch state {
        case .recording:
            pause()
        case .paused:
            resume()
        case .idle:
            break
        }
    }

    // MARK: - Sample intake (called from capture queues)

    func handleVideo(_ buffer: CMSampleBuffer, hostTimeSeconds: Double) {
        engine.handleVideo(buffer, hostTimeSeconds: hostTimeSeconds)
    }

    func handleAudio(_ buffer: CMSampleBuffer) {
        engine.handleAudio(buffer)
    }

    // MARK: - Recording control

    private func startRecording() {
        var audioFormat: AudioFormatInfo?
        do {
            audioFormat = try audioCapturer.prepare()
        } catch {
            print("System audio unavailable, recording video only: \(error)")
        }

        do {
            let videoSettings = camera.videoWriterSettings ?? [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: 1280,
                AVVideoHeightKey: 720
            ]
            try engine.startWriting(to: Self.nextDesktopURL(), videoSettings: videoSettings, audioFormat: audioFormat)
        } catch {
            audioCapturer.stop()
            engine.cancel()
            print("Failed to start recording: \(error)")
            return
        }

        if audioFormat != nil {
            audioCapturer.onSampleBuffer = { [weak self] buffer in
                self?.handleAudio(buffer)
            }
            do {
                try audioCapturer.start()
            } catch {
                print("System audio failed to start, recording video only: \(error)")
            }
        }

        state = .recording
    }

    private func pause() {
        guard state == .recording else { return }
        state = .paused
        engine.pause()
    }

    private func resume() {
        guard state == .paused else { return }
        state = .recording
        engine.resume()
    }

    func stop() {
        guard state != .idle else { return }
        state = .idle
        audioCapturer.stop()
        engine.finish { [weak self] url in
            DispatchQueue.main.async {
                self?.lastRecordedURL = url
            }
        }
    }

    // MARK: - Helpers

    private static func nextDesktopURL() -> URL {
        let desktop = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let name = "AVRecorder-\(formatter.string(from: Date())).mov"
        return desktop.appendingPathComponent(name)
    }
}