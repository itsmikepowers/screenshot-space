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

            // ── Appearance ──
            Section {
                Toggle("Show in Menu Bar", isOn: $appState.showInMenuBar)
                Toggle("Show in Dock", isOn: $appState.showInDock)

                Text("You can always reopen the app from Spotlight or Finder.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text("Appearance")
            }

            // ── System ──
            Section {
                Toggle("Launch at Login", isOn: $appState.launchAtLogin)
            } header: {
                Text("System")
            }

            // ── Permissions ──
            Section {
                permissionStatusRow(
                    title: "Accessibility Access",
                    symbolName: appState.accessibilityStatus.symbolName,
                    tint: appState.hasPermission ? .green : .red,
                    status: appState.accessibilityStatus.title,
                    detail: appState.accessibilityStatus.detail
                )

                permissionStatusRow(
                    title: "Hotkey Listener",
                    symbolName: hotkeySymbolName,
                    tint: hotkeyTintColor,
                    status: appState.hotkeyStatusTitle,
                    detail: appState.hotkeyStatusDetail
                )

                HStack {
                    if !appState.hasPermission {
                        Button("Grant Access") {
                            appState.requestPermission()
                        }

                        Button("Open Settings") {
                            appState.openAccessibilitySettings()
                        }
                    }

                    Button("Check Again") {
                        appState.refreshSystemAccess()
                    }
                }
                
                if appState.skipAccessibilityCheck && !appState.hasPermission {
                    Button("Show Setup Guide") {
                        appState.resetSkipAccessibilityCheck()
                    }
                    .font(.caption)
                }
            } header: {
                Text("Permissions")
            }
        }
        .formStyle(.grouped)
        .onAppear {
            appState.refreshSystemAccess()
        }
    }

    private var hotkeySymbolName: String {
        if !appState.isEnabled {
            return "pause.circle.fill"
        }

        if !appState.hasPermission {
            return "lock.slash.fill"
        }

        switch appState.monitorStatus {
        case .active:
            return "bolt.circle.fill"
        case .inactive:
            return "minus.circle.fill"
        case .failedToStart:
            return "xmark.octagon.fill"
        }
    }

    private var hotkeyTintColor: Color {
        if !appState.isEnabled {
            return .secondary
        }

        if !appState.hasPermission {
            return .orange
        }

        switch appState.monitorStatus {
        case .active:
            return .green
        case .inactive:
            return .orange
        case .failedToStart:
            return .red
        }
    }

    @ViewBuilder
    private func permissionStatusRow(
        title: String,
        symbolName: String,
        tint: Color,
        status: String,
        detail: String
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbolName)
                .foregroundColor(tint)
                .frame(width: 18, height: 18)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(title)
                    Spacer()
                    Text(status)
                        .foregroundColor(.secondary)
                }

                Text(detail)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
