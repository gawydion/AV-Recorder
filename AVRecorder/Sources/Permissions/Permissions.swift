import Foundation
import AppKit

/// Permission request scaffolding. Phase 2/3 will wire the real
/// `AVCaptureDevice` / Core Audio Process Tap permission APIs.
enum PermissionStatus: Equatable {
    case notDetermined
    case granted
    case denied
}

enum Permissions {
    static func cameraStatus() -> PermissionStatus {
        .notDetermined
    }

    static func requestCamera() async -> PermissionStatus {
        .notDetermined
    }

    static func systemAudioStatus() -> PermissionStatus {
        .notDetermined
    }

    static func requestSystemAudio() async -> PermissionStatus {
        .notDetermined
    }

    static func openSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")!
        NSWorkspace.shared.open(url)
    }
}