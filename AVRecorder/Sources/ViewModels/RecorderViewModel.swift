import Foundation
import SwiftUI
import AVFoundation
import CoreMedia

// MARK: - Recording State

enum RecordingState: Equatable {
    case idle
    case recording

    var label: String {
        switch self {
        case .idle: return "Idle"
        case .recording: return "Recording…"
        }
    }

    var tint: Color {
        switch self {
        case .idle: return .secondary
        case .recording: return .red
        }
    }
}

// MARK: - View Model

@MainActor
final class RecorderViewModel: ObservableObject {
    @Published private(set) var state: RecordingState = .idle
    @Published private(set) var audioLevel: Double = 0
    private(set) var lastRecordedURL: URL?

    let camera = CameraManager()
    private let engine = RecordingEngine()
    private let audioCapturer = SystemAudioCapturer()
    private let appSettings: AppSettingsStore

    init(appSettings: AppSettingsStore) {
        self.appSettings = appSettings
        startAudioMonitoring()
    }

    var isRecording: Bool { state != .idle }

    func toggleRecoding() {
        switch state {
        case .idle:
            startRecording()
        case .recording:
            stop()
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
        let audioFormat = audioCapturer.availableFormat

        do {
            let videoSettings = camera.videoWriterSettings ?? [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: 1280,
                AVVideoHeightKey: 720
            ]
            try engine.startWriting(to: outputURL(), videoSettings: videoSettings, audioFormat: audioFormat)
        } catch {
            engine.cancel()
            print("Failed to start recording: \(error)")
            return
        }

        state = .recording
    }

    func stop() {
        guard state != .idle else { return }
        state = .idle
        engine.finish { [weak self] url in
            DispatchQueue.main.async {
                self?.lastRecordedURL = url
            }
        }
    }

    // MARK: - Helpers

    /// Prepares and starts the system-audio tap so the level meter is live at
    /// all times. Recording reuses the same continuous tap and lets the engine
    /// gate which samples reach the writer.
    private func startAudioMonitoring() {
        do {
            _ = try audioCapturer.prepare()
            audioCapturer.onSampleBuffer = { [weak self] buffer in
                DispatchQueue.main.async {
                    self?.handleAudio(buffer)
                }
            }
            audioCapturer.onLevel = { [weak self] level in
                DispatchQueue.main.async {
                    self?.audioLevel = level
                }
            }
            try audioCapturer.start()
        } catch {
            print("System audio monitoring unavailable: \(error)")
        }
    }

    private func outputURL() -> URL {
        let folder = URL(fileURLWithPath: appSettings.settings.savePath)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let name = "AVRecorder-\(formatter.string(from: Date())).mov"
        return folder.appendingPathComponent(name)
    }
}