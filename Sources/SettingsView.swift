import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Form {
            // ── General ──
            Section {
                Toggle("Enable Screenshot Shortcuts", isOn: $appState.isEnabled)

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Hold Threshold")
                        Spacer()
                        Text(String(format: "%.2fs", appState.holdThreshold))
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $appState.holdThreshold, in: 0.10...1.0, step: 0.05)
                }

                Text("Tap Option \u{2192} full-screen screenshot to clipboard\nHold Option \u{2192} drag to select area to clipboard")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text("General")
            }

            // ── Screenshots ──
            Section {
                HStack {
                    Image(systemName: "folder.fill")
                        .foregroundColor(.accentColor)
                    Text("~/Pictures/ScreenshotSpace/")
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Open in Finder") {
                        ScreenshotManager.revealInFinder()
                    }
                }

                Text("All screenshots are saved here and copied to your clipboard.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text("Screenshots")
            }

            // ── System ──
            Section {
                Toggle("Launch at Login", isOn: $appState.launchAtLogin)
            } header: {
                Text("System")
            }

            // ── Permissions ──
            Section {
                HStack {
                    Image(systemName: appState.hasPermission
                          ? "checkmark.circle.fill"
                          : "xmark.circle.fill")
                        .foregroundColor(appState.hasPermission ? .green : .red)

                    Text("Accessibility")

                    Spacer()

                    if !appState.hasPermission {
                        Button("Grant Access") {
                            appState.requestPermission()
                        }
                    } else {
                        Text("Granted")
                            .foregroundColor(.secondary)
                    }
                }

                if !appState.hasPermission {
                    Button("Check Again") {
                        appState.checkPermission()
                    }
                }
            } header: {
                Text("Permissions")
            }
        }
        .formStyle(.grouped)
        .onAppear {
            appState.checkPermission()
        }
    }
}
