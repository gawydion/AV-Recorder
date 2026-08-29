import Foundation
import Combine

/// UserDefaults-backed store for app settings.
@MainActor
final class AppSettingsStore: ObservableObject {
    @Published var settings: AppSettings {
        didSet { persist() }
    }

    private let defaults = UserDefaults.standard
    private let resolutionKey = "settings.resolution"
    private let frameRateKey = "settings.frameRate"
    private let orientationKey = "settings.orientation"
    private let savePathKey = "settings.savePath"
    private let diffKey = "settings.diff"

    init() {
        var loaded = AppSettings()

        if let raw = defaults.string(forKey: resolutionKey),
           let value = Resolution(rawValue: raw) {
            loaded.resolution = value
        }
        if let value = defaults.value(forKey: frameRateKey) as? Int,
           let fps = FrameRate(rawValue: value) {
            loaded.frameRate = fps
        }
        if let raw = defaults.string(forKey: orientationKey),
           let value = Orientation(rawValue: raw) {
            loaded.orientation = value
        }
        if let path = defaults.string(forKey: savePathKey),
           path != AppSettings.legacySavePath {
            loaded.savePath = path
        }
        if defaults.object(forKey: diffKey) != nil {
            loaded.diff = min(max(defaults.integer(forKey: diffKey), 0), 100)
        }

        settings = loaded
    }

    /// Updates the orientation with a hop off the current run-loop pass so
    /// the `@Published` change isn't fired from inside a view update
    /// (which SwiftUI flags as undefined behavior).
    func setOrientation(_ value: Orientation) {
        DispatchQueue.main.async { [weak self] in
            self?.settings.orientation = value
        }
    }

    private func persist() {
        defaults.set(settings.resolution.rawValue, forKey: resolutionKey)
        defaults.set(settings.frameRate.rawValue, forKey: frameRateKey)
        defaults.set(settings.orientation.rawValue, forKey: orientationKey)
        defaults.set(settings.savePath, forKey: savePathKey)
        defaults.set(settings.diff, forKey: diffKey)
    }
}