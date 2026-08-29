import SwiftUI
import AppKit

struct SettingsSheet: View {
    @EnvironmentObject private var store: AppSettingsStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                Text("Settings")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Close settings")
            }

            GroupBox("Video") {
                VStack(alignment: .leading, spacing: 14) {
                    settingRow("Resolution") {
                        Picker("Resolution", selection: $store.settings.resolution) {
                            ForEach(Resolution.allCases) { r in
                                Text(r.rawValue).tag(r)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }
                    settingRow("Frame Rate") {
                        Picker("Frame Rate", selection: $store.settings.frameRate) {
                            ForEach(FrameRate.allCases) { fps in
                                Text("\(fps.rawValue) fps").tag(fps)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }
                    settingRow("Orientation") {
                        Picker("Orientation", selection: $store.settings.orientation) {
                            ForEach(Orientation.allCases) { o in
                                Text(o == .horizontal ? "Horizontal" : "Vertical").tag(o)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }
                    settingRow("Diff") {
                        TextField("0-100", value: diffBinding, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                    }
                }
                .padding(12)
            }

            GroupBox("Save Location") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "folder")
                            .foregroundStyle(.secondary)
                        Text(store.settings.savePath)
                            .font(.callout.monospaced())
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Choose…") {
                            chooseFolder()
                        }
                        .controlSize(.small)
                    }
                }
                .padding(12)
            }

            HStack {
                Button {
                    resetToDefaults()
                } label: {
                    Label("Reset", systemImage: "arrow.clockwise")
                }
                .controlSize(.small)
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 4)
        }
        .padding(20)
        .frame(width: 540)
    }

    private var diffBinding: Binding<Int> {
        Binding(
            get: { store.settings.diff },
            set: { store.settings.diff = min(max($0, 0), 100) }
        )
    }

    private func settingRow(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        HStack(spacing: 16) {
            Text(title)
                .font(.callout)
                .frame(width: 110, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url {
            store.settings.savePath = url.path
        }
    }

    private func resetToDefaults() {
        store.settings = AppSettings()
    }
}