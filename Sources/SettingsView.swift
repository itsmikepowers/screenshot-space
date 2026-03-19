import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var updater = Updater.shared

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

                Text("Tap \(appState.hotkeyDisplayString) \u{2192} full-screen screenshot to clipboard\nHold \(appState.hotkeyDisplayString) \u{2192} drag to select area to clipboard")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text("General")
            }

            // ── Hotkey ──
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Current: \(appState.hotkeyDisplayStringLong)")
                        .foregroundColor(.secondary)

                    HStack(spacing: 12) {
                        modifierToggle("⌃ Control", flag: .maskControl)
                        modifierToggle("⇧ Shift", flag: .maskShift)
                        modifierToggle("⌥ Option", flag: .maskAlternate)
                        modifierToggle("⌘ Command", flag: .maskCommand)
                    }
                }

                Text("Select one or more modifier keys. The screenshot triggers when exactly these keys are pressed together.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text("Hotkey")
            }

            // ── Screenshots ──
            Section {
                HStack {
                    Image(systemName: "folder.fill")
                        .foregroundColor(.accentColor)
                    Text(appState.screenshotDirectoryDisplay)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("Choose\u{2026}") {
                        chooseScreenshotDirectory()
                    }
                    Button("Open in Finder") {
                        ScreenshotManager.revealInFinder()
                    }
                }

                if appState.screenshotDirectory != ScreenshotManager.defaultDirectoryPath {
                    Button("Reset to Default") {
                        appState.screenshotDirectory = ScreenshotManager.defaultDirectoryPath
                    }
                    .font(.caption)
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
                    detail: appState.hasPermission ? nil : appState.accessibilityStatus.detail
                )

                HStack {
                    if !appState.hasPermission {
                        Button("Grant Access") {
                            appState.requestPermission()
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
            
            // ── Updates ──
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Current Version")
                        Text(updater.currentVersion)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    updateStatusView
                }
                
                updateActionButton
            } header: {
                Text("Updates")
            }
        }
        .formStyle(.grouped)
        .onAppear {
            appState.refreshSystemAccess()
        }
    }

    @ViewBuilder
    private var updateStatusView: some View {
        switch updater.status {
        case .idle:
            EmptyView()
        case .checking:
            HStack(spacing: 6) {
                ProgressView()
                    .scaleEffect(0.7)
                Text("Checking...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        case .available(let version):
            HStack(spacing: 4) {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundColor(.blue)
                Text("v\(version) available")
                    .font(.caption)
                    .foregroundColor(.blue)
            }
        case .downloading:
            HStack(spacing: 6) {
                ProgressView()
                    .scaleEffect(0.7)
                Text("Downloading...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        case .installing:
            HStack(spacing: 6) {
                ProgressView()
                    .scaleEffect(0.7)
                Text("Installing...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        case .upToDate:
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("Up to date")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        case .error(let message):
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundColor(.red)
                Text(message)
                    .font(.caption)
                    .foregroundColor(.red)
                    .lineLimit(1)
            }
        }
    }
    
    @ViewBuilder
    private var updateActionButton: some View {
        switch updater.status {
        case .available:
            Button("Download & Install") {
                Task {
                    await updater.downloadAndInstall()
                }
            }
            .buttonStyle(.borderedProminent)
        case .idle, .upToDate, .error:
            Button("Check for Updates") {
                Task {
                    await updater.checkForUpdates()
                }
            }
            .disabled(updater.status.isLoading)
        case .checking, .downloading, .installing:
            Button("Updating...") {}
                .disabled(true)
        }
    }
    
    // MARK: - Hotkey Helpers

    private func modifierBinding(_ flag: CGEventFlags) -> Binding<Bool> {
        Binding<Bool>(
            get: {
                CGEventFlags(rawValue: appState.hotkeyModifiers).contains(flag)
            },
            set: { enabled in
                var flags = CGEventFlags(rawValue: appState.hotkeyModifiers)
                if enabled {
                    flags.insert(flag)
                } else {
                    flags.remove(flag)
                }
                let relevant: CGEventFlags = [.maskCommand, .maskControl, .maskShift, .maskAlternate]
                guard !flags.intersection(relevant).isEmpty else { return }
                appState.hotkeyModifiers = flags.rawValue
            }
        )
    }

    @ViewBuilder
    private func modifierToggle(_ label: String, flag: CGEventFlags) -> some View {
        Toggle(label, isOn: modifierBinding(flag))
            .toggleStyle(.checkbox)
    }

    // MARK: - Directory Picker

    private func chooseScreenshotDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.message = "Select a folder for saving screenshots"

        if panel.runModal() == .OK, let url = panel.url {
            appState.screenshotDirectory = url.path
        }
    }

    @ViewBuilder
    private func permissionStatusRow(
        title: String,
        symbolName: String,
        tint: Color,
        status: String,
        detail: String?
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

                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}
