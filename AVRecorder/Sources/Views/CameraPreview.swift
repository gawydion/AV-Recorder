import SwiftUI
import AVFoundation

/// Live camera feed rendered through an `AVCaptureVideoPreviewLayer`.
struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession?

    func makeNSView(context: Context) -> CameraPreviewNSView {
        let view = CameraPreviewNSView()
        view.attach(session)
        return view
    }

    func updateNSView(_ nsView: CameraPreviewNSView, context: Context) {
        nsView.attach(session)
    }
}

final class CameraPreviewNSView: NSView {
    private let previewLayer = AVCaptureVideoPreviewLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        previewLayer.videoGravity = .resizeAspectFill
        layer = previewLayer
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func attach(_ session: AVCaptureSession?) {
        previewLayer.session = session
        previewLayer.connection?.automaticallyAdjustsVideoMirroring = false
        previewLayer.connection?.isVideoMirrored = session != nil
    }
}

/// Shown when the user has denied camera access.
struct CameraAccessDenied: View {
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "camera.fill")
                .font(.system(size: 36))
                .foregroundStyle(Color.white.opacity(0.3))
            Text("Camera access is disabled")
                .font(.callout.weight(.medium))
                .foregroundStyle(Color.white.opacity(0.8))
            Text("Enable camera access in System Settings to see the live preview.")
                .font(.caption)
                .foregroundStyle(Color.white.opacity(0.5))
            Button("Retry") {
                retry()
            }
            .buttonStyle(.bordered)
        }
    }
}