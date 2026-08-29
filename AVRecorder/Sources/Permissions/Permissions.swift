import Foundation
import AppKit
import AVFoundation

/// Camera and system-audio permission state.
enum PermissionStatus: Equatable {
    case notDetermined
    case granted
    case denied
}

enum Permissions {
    static func cameraStatus() -> PermissionStatus {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return .granted
        case .denied, .restricted: return .denied
        case .notDetermined: return .notDetermined
        @unknown default: return .notDetermined
        }
    }

    static func requestCamera() async -> PermissionStatus {
        await AVCaptureDevice.requestAccess(for: .video) ? .granted : .denied
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