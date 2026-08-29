import AVFoundation
import CoreMedia
import CoreVideo
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
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var audioInput: AVAssetWriterInput?
    private var anchorSeconds: Double?
    private var sessionStarted = false
    private var paused = true
    private var audioLeadSeconds: Double = 0
    private var cropRect: CGRect?

    init() {}

    // MARK: - Control (main thread)

    func startWriting(to url: URL, videoSettings: [String: Any], audioFormat: AudioFormatInfo?, videoCropRect: CGRect? = nil, audioLeadMilliseconds: Int = 0) throws {
        // NOTE: AppSettings.resolution / AppSettings.frameRate are displayed in
        // Settings UI but not wired here — the session is fixed at 720p and we
        // use the camera's recommendedVideoSettingsForAssetWriter. Wire them here
        // (override settings + reconfig the session) to make those controls real.
        let newWriter = try AVAssetWriter(outputURL: url, fileType: .mov)

        let newVideoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        newVideoInput.expectsMediaDataInRealTime = true
        if newWriter.canAdd(newVideoInput) {
            newWriter.add(newVideoInput)
        }

        var newAdaptor: AVAssetWriterInputPixelBufferAdaptor?
        if videoCropRect != nil {
            newAdaptor = AVAssetWriterInputPixelBufferAdaptor(
                assetWriterInput: newVideoInput,
                sourcePixelBufferAttributes: [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
                    kCVPixelBufferWidthKey as String: Int(videoCropRect!.width),
                    kCVPixelBufferHeightKey as String: Int(videoCropRect!.height)
                ]
            )
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
        pixelBufferAdaptor = newAdaptor
        audioInput = newAudioInput
        anchorSeconds = nil
        sessionStarted = false
        audioLeadSeconds = Double(audioLeadMilliseconds) / 1000.0
        cropRect = videoCropRect
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
            guard let time = self.sessionTime(absoluteSeconds: hostTimeSeconds) else { return }

            if let adaptor = self.pixelBufferAdaptor, let cropRect = self.cropRect,
               let destBuffer = self.crop(buffer, to: cropRect, from: adaptor) {
                adaptor.append(destBuffer, withPresentationTime: time)
            } else if let sample = self.retimed(buffer, at: time) {
                input.append(sample)
            }
        }
    }

    /// Crops a source sample buffer to `cropRect` (in source coordinates),
    /// drawing into a pooled buffer matching the vertical output dimensions.
    /// Y (luma) is copied for every row; the chroma plane is half-res in both
    /// axes (4:2:0), so it must be copied at half the row count and half the
    /// X offset. BytesPerRow is preserved (no re-pack) — we copy full rows.
    private func crop(_ buffer: CMSampleBuffer, to cropRect: CGRect, from adaptor: AVAssetWriterInputPixelBufferAdaptor) -> CVPixelBuffer? {
        guard let src = CMSampleBufferGetImageBuffer(buffer) else { return nil }
        guard let pool = adaptor.pixelBufferPool else { return nil }

        var dest: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(nil, pool, &dest)
        guard status == kCVReturnSuccess, let dest else { return nil }

        CVPixelBufferLockBaseAddress(src, .readOnly)
        CVPixelBufferLockBaseAddress(dest, [])
        defer {
            CVPixelBufferUnlockBaseAddress(src, .readOnly)
            CVPixelBufferUnlockBaseAddress(dest, [])
        }

        guard let srcBase = CVPixelBufferGetBaseAddress(src),
              let destBase = CVPixelBufferGetBaseAddress(dest) else { return nil }

        let srcBytesPerRow = CVPixelBufferGetBytesPerRow(src)
        let destBytesPerRow = CVPixelBufferGetBytesPerRow(dest)
        let cropX = Int(cropRect.minX.rounded())
        let cropWidth = Int(cropRect.width.rounded())
        let copyHeight = Int(cropRect.height.rounded())

        for row in 0..<copyHeight {
            memcpy(destBase.advanced(by: row * destBytesPerRow),
                   srcBase.advanced(by: row * srcBytesPerRow + cropX),
                   cropWidth)
        }

        if let srcPlane1 = CVPixelBufferGetBaseAddressOfPlane(src, 1),
           let destPlane1 = CVPixelBufferGetBaseAddressOfPlane(dest, 1) {
            let srcBytesPerRow1 = CVPixelBufferGetBytesPerRowOfPlane(src, 1)
            let destBytesPerRow1 = CVPixelBufferGetBytesPerRowOfPlane(dest, 1)
            let halfHeight = copyHeight / 2
            let halfCropWidth = cropWidth / 2
            let srcOffset1 = cropX / 2
            for row in 0..<halfHeight {
                memcpy(destPlane1.advanced(by: row * destBytesPerRow1),
                       srcPlane1.advanced(by: row * srcBytesPerRow1 + srcOffset1),
                       halfCropWidth)
            }
        }

        return dest
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
            // Normal case: shift every sample relative to the anchor, so both
            // streams map onto one start-of-file clock starting at zero.
            let seconds = max(0, absoluteSeconds - anchorSeconds)
            return CMTime(value: CMTimeValue((seconds * 1_000_000).rounded()), timescale: Self.timescale)
        }
        guard let writer, writer.status == .writing, !sessionStarted else { return nil }

        // First sample on either stream establishes the session's t=0 anchor.
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
        pixelBufferAdaptor = nil
        audioInput = nil
        anchorSeconds = nil
        sessionStarted = false
        audioLeadSeconds = 0
        cropRect = nil
        setPaused(true)
    }
}