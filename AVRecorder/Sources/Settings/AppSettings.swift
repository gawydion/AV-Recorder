import Foundation
import SwiftUI

// MARK: - Enums

enum Resolution: String, CaseIterable, Identifiable {
    case hd720p = "720p"
    case hd1080p = "1080p"
    case hd1440p = "1440p"

    var id: String { rawValue }
}

enum FrameRate: Int, CaseIterable, Identifiable {
    case fps24 = 24
    case fps30 = 30
    case fps60 = 60

    var id: Int { rawValue }
}

enum Orientation: String, CaseIterable, Identifiable {
    case vertical
    case horizontal

    var id: String { rawValue }
}

// MARK: - Settings Model

struct AppSettings: Equatable {
    static let defaultSavePath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Desktop").path
    static let legacySavePath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Movies/AVRecorder").path

    var resolution: Resolution = .hd1080p
    var frameRate: FrameRate = .fps30
    var orientation: Orientation = .horizontal
    var savePath: String = AppSettings.defaultSavePath
    var diff: Int = 3
}