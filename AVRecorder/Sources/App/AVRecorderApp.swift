import SwiftUI

@main
struct AVRecorderApp: App {
    @StateObject private var appSettings: AppSettingsStore
    @StateObject private var recorder: RecorderViewModel

    init() {
        let settings = AppSettingsStore()
        _appSettings = StateObject(wrappedValue: settings)
        _recorder = StateObject(wrappedValue: RecorderViewModel(appSettings: settings))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appSettings)
                .environmentObject(recorder)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 900, height: 620)
    }
}