import AVFoundation
import CoreMedia
import CoreVideo

/// Owns the live front-camera capture session and drives permission state.
@MainActor
final class CameraManager: ObservableObject {
    @Published private(set) var permission: PermissionStatus = .notDetermined

    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "AVRecorder.CameraSession")
    private let videoQueue = DispatchQueue(label: "AVRecorder.Camera.VideoQueue", qos: .userInitiated)
    private let videoOutputDelegate = VideoOutputDelegate()
    private var isConfigured = false
    private var videoDataOutput: AVCaptureVideoDataOutput?

    var isAuthorized: Bool { permission == .granted }

    /// Orientation of the captured/saved video. `.horizontal` keeps the full
    /// landscape frame; `.vertical` crops the center to a 9:16 mobile frame
    /// (keeping the natural, unrotated capture).
    var orientation: Orientation = .horizontal

    /// Compression settings (codec + dimensions) recommended for the camera's
    /// active format, used to configure the `AVAssetWriterInput` at record time.
    /// For vertical output the dimensions are width-cropped to a 9:16 frame so
    /// the file is encoded portrait without rotating the source video.
    var videoWriterSettings: [String: Any]? {
        guard var settings = videoDataOutput?.recommendedVideoSettingsForAssetWriter(writingTo: .mov) else { return nil }
        if orientation == .vertical,
           let width = settings[AVVideoWidthKey] as? Int,
           let height = settings[AVVideoHeightKey] as? Int {
            let cropWidth = max(1, Int(((Double(height) * 9.0) / 16.0).rounded()))
            settings[AVVideoWidthKey] = min(cropWidth, width)
            settings[AVVideoHeightKey] = height
        }
        return settings
    }

    /// Width and height of the vertical crop region in the source pixel buffer
    /// coordinates (only relevant in vertical mode). The source stays
    /// unrotated; we clip out the center 9:16 slice and encode that.
    var videoCropRect: CGRect? {
        guard orientation == .vertical,
              let settings = videoDataOutput?.recommendedVideoSettingsForAssetWriter(writingTo: .mov),
              let width = settings[AVVideoWidthKey] as? Int,
              let height = settings[AVVideoHeightKey] as? Int,
              width > 0, height > 0 else { return nil }
        let cropWidth = Double(height) * 9.0 / 16.0
        return CGRect(x: (Double(width) - cropWidth) / 2.0, y: 0, width: cropWidth, height: Double(height))
    }

    /// Receives each camera frame (plus its host-time-based second offset)
    /// on `videoQueue`, so the recorder can mux the video.
    var videoSampleHandler: ((CMSampleBuffer, Double) -> Void)? {
        get { videoOutputDelegate.handler }
        set { videoOutputDelegate.handler = newValue }
    }

    /// Requests camera access (if needed) and starts the front-camera feed.
    func requestAndStart() async {
        permission = Permissions.cameraStatus()
        if permission == .notDetermined {
            permission = await Permissions.requestCamera()
        }
        if permission == .granted {
            configureAndStart()
        }
    }

    func stop() {
        guard session.isRunning else { return }
        sessionQueue.async { [weak self] in
            self?.session.stopRunning()
        }
    }

    private func configureAndStart() {
        guard !isConfigured else { return }
        isConfigured = true
        let delegate = videoOutputDelegate
        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard let device = Self.frontCameraDevice(),
                  let input = try? AVCaptureDeviceInput(device: device),
                  self.session.canAddInput(input) else { return }
            self.session.addInput(input)
            if self.session.canSetSessionPreset(.hd1280x720) {
                self.session.sessionPreset = .hd1280x720
            }

            let recordOutput = AVCaptureVideoDataOutput()
            recordOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange]
            recordOutput.alwaysDiscardsLateVideoFrames = false
            recordOutput.setSampleBufferDelegate(delegate, queue: self.videoQueue)
            if self.session.canAddOutput(recordOutput) {
                self.session.addOutput(recordOutput)
                self.videoDataOutput = recordOutput
                delegate.synchronizationClock = self.session.synchronizationClock
            }

            self.session.startRunning()
        }
    }

    private static func frontCameraDevice() -> AVCaptureDevice? {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera],
            mediaType: .video,
            position: .front
        )
        return discovery.devices.first
            ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
    }
}

/// Forwards camera frames to the recorder. Runs on `videoQueue`.
private final class VideoOutputDelegate: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    var handler: ((CMSampleBuffer, Double) -> Void)?
    var synchronizationClock: CMClock?

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let seconds: Double
        if let synchronizationClock {
            let hostTime = CMSyncConvertTime(sampleBuffer.presentationTimeStamp, from: synchronizationClock, to: CMClockGetHostTimeClock())
            seconds = CMTimeGetSeconds(hostTime)
        } else {
            seconds = CMTimeGetSeconds(sampleBuffer.presentationTimeStamp)
        }
        handler?(sampleBuffer, seconds)
    }
}