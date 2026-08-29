import SwiftUI

/// Placeholder for the live camera preview (Phase 2 will replace this
/// with an `NSViewRepresentable` wrapping an `AVCaptureVideoPreviewLayer`).
struct CameraPreviewPlaceholder: View {
    var body: some View {
        ZStack {
            Color(red: 0.13, green: 0.14, blue: 0.17)
            Image(systemName: "video.fill")
                .font(.system(size: 44))
                .foregroundStyle(Color.white.opacity(0.25))
            VStack {
                Spacer()
                Text("Camera Preview")
                    .font(.callout)
                    .foregroundStyle(Color.white.opacity(0.5))
                    .padding(.bottom, 12)
            }
        }
    }
}