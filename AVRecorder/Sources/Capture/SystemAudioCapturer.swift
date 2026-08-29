import AVFoundation
import CoreAudio
import CoreMedia
import Darwin

/// Description of the tapped system-audio format, handed to the recorder
/// so the writer input can be configured before samples start flowing.
struct AudioFormatInfo {
    let sampleRate: Double
    let channelCount: UInt32
    let bytesPerFrame: UInt32
    let formatDescription: CMAudioFormatDescription
}

/// Captures the whole system audio mix (the audio playing to the speakers,
/// e.g. guitar through Neural DSP plus background music) using a Core Audio
/// process tap attached to a private aggregate device (macOS 14.4+).
///
/// The tap's IO proc copies each buffer on the real-time thread, and a drain
/// queue converts the PCM data into `CMSampleBuffer`s with host-time-based
/// presentation timestamps so they can sync with the camera feed.
final class SystemAudioCapturer {
    enum AudioError: Error {
        case tapCreationFailed(OSStatus)
        case formatUnavailable(OSStatus)
        case aggregateCreationFailed(OSStatus)
        case ioSetupFailed(OSStatus)
    }

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    private var isRunning = false

    private var formatInfo: AudioFormatInfo?

    private let ioQueue = DispatchQueue(label: "AVRecorder.SystemAudio.IO", qos: .userInitiated)
    private let drainQueue = DispatchQueue(label: "AVRecorder.SystemAudio.Drain", qos: .userInitiated)

    /// Called on the drain queue with each converted `CMSampleBuffer`.
    var onSampleBuffer: ((CMSampleBuffer) -> Void)?

    /// Called on the main thread with the smoothed audio level in 0...1,
    /// throttled to ~30 Hz for live metering.
    var onLevel: ((Double) -> Void)?

    /// The tap format, available once `prepare()` has succeeded. Used to
    /// configure the writer while the tap keeps running.
    var availableFormat: AudioFormatInfo? { formatInfo }

    private var smoothedLevel: Double = 0
    private var lastLevelEmit: TimeInterval = 0

    private static let timebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    /// Creates the tap + private aggregate device and reads the tap format.
    /// Returns the format so the writer can be configured before IO starts.
    @discardableResult
    func prepare() throws -> AudioFormatInfo {
        stop()

        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        description.name = "AV Recorder System Audio"
        description.uuid = UUID()
        description.isPrivate = true
        description.isMixdown = true
        description.muteBehavior = .unmuted

        var tap = AudioObjectID(kAudioObjectUnknown)
        let tapStatus = AudioHardwareCreateProcessTap(description, &tap)
        guard tapStatus == noErr, tap != kAudioObjectUnknown else {
            throw AudioError.tapCreationFailed(tapStatus)
        }
        tapID = tap

        var asbd = AudioStreamBasicDescription()
        var formatAddress = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var formatSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        let formatStatus = AudioObjectGetPropertyData(tapID, &formatAddress, 0, nil, &formatSize, &asbd)
        guard formatStatus == noErr else {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = kAudioObjectUnknown
            throw AudioError.formatUnavailable(formatStatus)
        }

        var formatDescription: CMAudioFormatDescription?
        if let format = AVAudioFormat(streamDescription: &asbd) {
            formatDescription = format.formatDescription
        }
        guard let formatDescription else {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = kAudioObjectUnknown
            throw AudioError.formatUnavailable(noErr)
        }

        let bytesPerFrame = asbd.mBytesPerFrame != 0
            ? asbd.mBytesPerFrame
            : UInt32(2 * MemoryLayout<Float32>.size)
        formatInfo = AudioFormatInfo(
            sampleRate: asbd.mSampleRate,
            channelCount: asbd.mChannelsPerFrame,
            bytesPerFrame: bytesPerFrame,
            formatDescription: formatDescription
        )

        let aggregateDescription: [String: Any] = [
            kAudioAggregateDeviceNameKey: "AV Recorder System Audio Tap",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapUIDKey: description.uuid.uuidString,
                kAudioSubTapDriftCompensationKey: true
            ]]
        ]

        var aggregate = AudioObjectID(kAudioObjectUnknown)
        let aggregateStatus = AudioHardwareCreateAggregateDevice(aggregateDescription as CFDictionary, &aggregate)
        guard aggregateStatus == noErr, aggregate != kAudioObjectUnknown else {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = kAudioObjectUnknown
            throw AudioError.aggregateCreationFailed(aggregateStatus)
        }
        aggregateID = aggregate

        var ioProc: AudioDeviceIOProcID?
        let ioStatus = AudioDeviceCreateIOProcIDWithBlock(&ioProc, aggregateID, ioQueue) { [weak self] _, inputData, inputTime, _, _ in
            self?.pump(inputData: inputData, hostTime: inputTime.pointee.mHostTime)
        }
        guard ioStatus == noErr, let ioProc else {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = kAudioObjectUnknown
            AudioHardwareDestroyProcessTap(tapID)
            tapID = kAudioObjectUnknown
            throw AudioError.ioSetupFailed(ioStatus)
        }
        ioProcID = ioProc

        return formatInfo!
    }

    /// Starts delivering audio buffers. The first call triggers the system
    /// audio recording permission prompt.
    func start() throws {
        guard !isRunning, aggregateID != kAudioObjectUnknown, let ioProcID else { return }
        let status = AudioDeviceStart(aggregateID, ioProcID)
        guard status == noErr else {
            throw AudioError.ioSetupFailed(status)
        }
        isRunning = true
    }

    func stop() {
        if aggregateID != kAudioObjectUnknown, let ioProcID {
            AudioDeviceStop(aggregateID, ioProcID)
            AudioDeviceDestroyIOProcID(aggregateID, ioProcID)
        }
        ioProcID = nil
        if aggregateID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateID)
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
        }
        aggregateID = kAudioObjectUnknown
        tapID = kAudioObjectUnknown
        isRunning = false
        formatInfo = nil
    }

    // MARK: - Real-time pipeline

    /// Runs on the real-time IO queue: copies the PCM bytes and hands them
    /// off to the drain queue for CMSampleBuffer conversion.
    private func pump(inputData: UnsafePointer<AudioBufferList>, hostTime: UInt64) {
        guard formatInfo != nil else { return }
        let byteSize = Int(inputData.pointee.mBuffers.mDataByteSize)
        guard byteSize > 0, let bytes = inputData.pointee.mBuffers.mData else { return }

        let data = Data(bytes: bytes, count: byteSize)
        let presentationSeconds = Self.hostSeconds(hostTime)

        drainQueue.async { [weak self] in
            guard let self, let info = self.formatInfo else { return }
            self.emitLevel(Self.rmsLevel(data: data))
            guard let sample = Self.makeSampleBuffer(data: data, info: info, presentationSeconds: presentationSeconds) else { return }
            self.onSampleBuffer?(sample)
        }
    }

    // MARK: - Metering

    /// Computes the RMS amplitude of a Float32 PCM buffer, scaled to 0...1.
    private static func rmsLevel(data: Data) -> Double {
        let total = data.count / MemoryLayout<Float32>.size
        guard total > 0 else { return 0 }
        var sum = 0.0
        data.withUnsafeBytes { raw in
            let floats = raw.bindMemory(to: Float32.self)
            for value in floats {
                let s = Double(value)
                sum += s * s
            }
        }
        return min(sqrt(sum / Double(total)), 1.0)
    }

    /// Smooths the level (fast attack, slow release) and throttles main-thread
    /// delivery to ~30 Hz. Called only from the serial drain queue.
    private func emitLevel(_ level: Double) {
        if level > smoothedLevel {
            smoothedLevel += (level - smoothedLevel) * 0.7
        } else {
            smoothedLevel += (level - smoothedLevel) * 0.15
        }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastLevelEmit >= 1.0 / 30 else { return }
        lastLevelEmit = now
        let snapshot = smoothedLevel
        DispatchQueue.main.async { [weak self] in
            self?.onLevel?(snapshot)
        }
    }

    private static func hostSeconds(_ hostTime: UInt64) -> Double {
        Double(hostTime) * Double(timebase.numer) / Double(timebase.denom) / 1_000_000_000
    }

    private static func makeSampleBuffer(data: Data, info: AudioFormatInfo, presentationSeconds: Double) -> CMSampleBuffer? {
        let length = data.count
        let frameCount = length / Int(info.bytesPerFrame)
        guard frameCount > 0 else { return nil }

        var blockBuffer: CMBlockBuffer?
        var status = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: length,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: length,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        guard status == kCMBlockBufferNoErr, let blockBuffer else { return nil }

        status = CMBlockBufferReplaceDataBytes(
            with: (data as NSData).bytes,
            blockBuffer: blockBuffer,
            offsetIntoDestination: 0,
            dataLength: length
        )
        guard status == kCMBlockBufferNoErr else { return nil }

        let presentation = CMTime(value: CMTimeValue((presentationSeconds * 1_000_000).rounded()), timescale: 1_000_000)
        let duration = CMTime(value: CMTimeValue(frameCount), timescale: CMTimeScale(info.sampleRate))
        var timing = CMSampleTimingInfo(duration: duration, presentationTimeStamp: presentation, decodeTimeStamp: .invalid)

        var sample: CMSampleBuffer?
        CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: blockBuffer,
            formatDescription: info.formatDescription,
            sampleCount: frameCount,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 0,
            sampleSizeArray: nil,
            sampleBufferOut: &sample
        )
        return sample
    }
}