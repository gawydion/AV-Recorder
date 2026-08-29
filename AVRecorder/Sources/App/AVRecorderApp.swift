import SwiftUI

@main
struct AVRecorderApp: App {
    @StateObject private var appSettings = AppSettingsStore()
    @StateObject private var recorder = RecorderViewModel()

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