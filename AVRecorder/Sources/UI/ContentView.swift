import SwiftUI
import AVFoundation

struct ContentView: View {
    @EnvironmentObject private var recorder: RecorderViewModel
    @EnvironmentObject private var settings: AppSettingsStore
    @State private var isSettingsPresented = false

    var body: some View {
        ZStack {
            Color(red: 0.09, green: 0.10, blue: 0.12)
                .ignoresSafeArea()

            VStack(spacing: 18) {
                header
                cameraPreview
                LevelMeter()
                    .frame(maxWidth: .infinity)
                transportControls
            }
            .padding(20)

            VStack {
                Spacer()
                HStack {
                    Spacer()
                    StatusLabel(state: recorder.state)
                }
            }
            .padding()
        }
        .frame(minWidth: 720, minHeight: 480)
        .sheet(isPresented: $isSettingsPresented) {
            SettingsSheet()
                .environmentObject(settings)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("AV Recorder")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.primary)
            Spacer()
            Button {
                isSettingsPresented = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Open settings")
        }
    }

    // MARK: - Content

    private var cameraPreview: some View {
        CameraPreviewPlaceholder()
            .frame(maxWidth: .infinity)
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            }
    }

    // MARK: - Transport

    private var transportControls: some View {
        HStack(spacing: 24) {
            RecordButton(state: recorder.state) {
                recorder.toggleRecoding()
            }
            PauseButton(state: recorder.state) {
                recorder.togglePause()
            }
        }
    }
}