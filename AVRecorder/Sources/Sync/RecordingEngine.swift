import AVFoundation
import CoreMedia
import Foundation

/// Muxes the camera video and tapped system audio into a single `.mov` file
/// using `AVAssetWriter`.
///
/// Video and audio samples arrive on different queues but are serialized onto
/// `writerQueue`. The first sample that arrives defines the timeline anchor:
/// every later sample is placed relative to it, so video and audio stay in
/// sync. An internal gate drops samples that arrive before recording starts
/// or after it finishes.
final class RecordingEngine {
    private static let timescale: CMTimeScale = 1_000_000

    private let writerQueue = DispatchQueue(label: "AVRecorder.RecordingEngine.Writer", qos: .userInitiated)
    private let pausedLock = NSLock()

    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var anchorSeconds: Double?
    private var sessionStarted = false
    private var paused = true
    private var audioLeadSeconds: Double = 0

    init() {}

    // MARK: - Control (main thread)

    func startWriting(to url: URL, videoSettings: [String: Any], audioFormat: AudioFormatInfo?, audioLeadMilliseconds: Int = 0) throws {
        let newWriter = try AVAssetWriter(outputURL: url, fileType: .mov)

        let newVideoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        newVideoInput.expectsMediaDataInRealTime = true
        if newWriter.canAdd(newVideoInput) {
            newWriter.add(newVideoInput)
        }

        var newAudioInput: AVAssetWriterInput?
        if let audioFormat {
            let audioInput = AVAssetWriterInput(
                mediaType: .audio,
                outputSettings: [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVSampleRateKey: audioFormat.sampleRate,
                    AVNumberOfChannelsKey: audioFormat.channelCount,
                    AVEncoderBitRateKey: 192_000
                ],
                sourceFormatHint: audioFormat.formatDescription
            )
            audioInput.expectsMediaDataInRealTime = true
            if newWriter.canAdd(audioInput) {
                newWriter.add(audioInput)
                newAudioInput = audioInput
            }
        }

        newWriter.startWriting()

        writer = newWriter
        videoInput = newVideoInput
        audioInput = newAudioInput
        anchorSeconds = nil
        sessionStarted = false
        audioLeadSeconds = Double(audioLeadMilliseconds) / 1000.0
        setPaused(false)
    }

    /// Finalizes the file and reports the saved URL (or nil on failure).
    func finish(completion: @escaping (URL?) -> Void) {
        writerQueue.async { [weak self] in
            guard let self else {
                completion(nil)
                return
            }
            self.setPaused(true)

            guard let writer = self.writer, writer.status == .writing else {
                let url = self.writer?.outputURL
                self.reset()
                if let url { try? FileManager.default.removeItem(at: url) }
                completion(nil)
                return
            }

            let url = writer.outputURL
            self.videoInput?.markAsFinished()
            self.audioInput?.markAsFinished()
            writer.finishWriting { [weak self] in
                if writer.status != .completed {
                    try? FileManager.default.removeItem(at: url)
                }
                self?.reset()
                completion(writer.status == .completed ? url : nil)
            }
        }
    }

    /// Aborts an in-progress recording without producing a file.
    func cancel() {
        writerQueue.async { [weak self] in
            guard let self else { return }
            if let writer = self.writer, writer.status == .writing {
                writer.cancelWriting()
            }
            let url = self.writer?.outputURL
            self.reset()
            if let url { try? FileManager.default.removeItem(at: url) }
        }
    }

    // MARK: - Sample intake (any queue)

    func handleVideo(_ buffer: CMSampleBuffer, hostTimeSeconds: Double) {
        guard isRecordingActive() else { return }
        writerQueue.async { [weak self] in
            guard let self else { return }
            guard self.isRecordingActive(),
                let writer = self.writer, writer.status == .writing,
                let input = self.videoInput, input.isReadyForMoreMediaData else { return }
            guard let time = self.sessionTime(absoluteSeconds: hostTimeSeconds),
                  let sample = self.retimed(buffer, at: time) else { return }
            input.append(sample)
        }
    }

    func handleAudio(_ buffer: CMSampleBuffer) {
        guard isRecordingActive() else { return }
        let seconds = CMTimeGetSeconds(buffer.presentationTimeStamp)
        writerQueue.async { [weak self] in
            guard let self else { return }
            guard self.isRecordingActive(),
                let writer = self.writer, writer.status == .writing,
                let input = self.audioInput, input.isReadyForMoreMediaData else { return }
            guard let time = self.sessionTime(absoluteSeconds: seconds) else { return }
            let shifted = CMTimeSubtract(time, CMTime(seconds: self.audioLeadSeconds, preferredTimescale: Self.timescale))
            guard let sample = self.retimed(buffer, at: shifted) else { return }
            input.append(sample)
        }
    }

    // MARK: - Timeline

    /// Replaces a sample buffer's presentation timestamp with the anchored
    /// session time so both streams share one start-of-file clock.
    private func retimed(_ buffer: CMSampleBuffer, at time: CMTime) -> CMSampleBuffer? {
        var timing = CMSampleTimingInfo()
        guard CMSampleBufferGetSampleTimingInfo(buffer, at: 0, timingInfoOut: &timing) == noErr else { return nil }
        timing.presentationTimeStamp = time
        timing.decodeTimeStamp = .invalid
        var out: CMSampleBuffer?
        let status = CMSampleBufferCreateCopyWithNewTiming(
            allocator: kCFAllocatorDefault,
            sampleBuffer: buffer,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleBufferOut: &out
        )
        return status == noErr ? out : nil
    }

    private func sessionTime(absoluteSeconds: Double) -> CMTime? {
        if let anchorSeconds {
            let seconds = max(0, absoluteSeconds - anchorSeconds)
            return CMTime(value: CMTimeValue((seconds * 1_000_000).rounded()), timescale: Self.timescale)
        }
        guard let writer, writer.status == .writing, !sessionStarted else { return nil }

        anchorSeconds = absoluteSeconds
        sessionStarted = true
        writer.startSession(atSourceTime: .zero)
        return .zero
    }

    // MARK: - State

    private func isRecordingActive() -> Bool {
        pausedLock.lock()
        defer { pausedLock.unlock() }
        return !paused
    }

    private func setPaused(_ value: Bool) {
        pausedLock.lock()
        paused = value
        pausedLock.unlock()
    }

    private func reset() {
        writer = nil
        videoInput = nil
        audioInput = nil
        anchorSeconds = nil
        sessionStarted = false
        audioLeadSeconds = 0
        setPaused(true)
    }
}