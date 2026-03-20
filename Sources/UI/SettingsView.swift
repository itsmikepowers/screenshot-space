import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var updater = Updater.shared

    var body: some View {
        Form {
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
            } header: {
                Text("Screenshots")
            }

            // ── Appearance ──
            Section {
                Toggle("Show in Menu Bar", isOn: $appState.showInMenuBar)
                Toggle("Show in Dock", isOn: $appState.showInDock)
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
                // Accessibility Access
                permissionStatusRow(
                    title: "Accessibility Access",
                    symbolName: appState.hasPermission ? "checkmark.circle.fill" : "xmark.circle.fill",
                    tint: appState.hasPermission ? .green : .red,
                    status: appState.hasPermission ? "Granted" : "Not Granted",
                    detail: nil
                )

                if !appState.hasPermission {
                    Button("Grant Access") {
                        appState.requestPermission()
                    }
                }

                // Screen Recording
                permissionStatusRow(
                    title: "Screen Recording",
                    symbolName: appState.screenRecordingPermissionGranted == true ? "checkmark.circle.fill" : "xmark.circle.fill",
                    tint: appState.screenRecordingPermissionGranted == true ? .green : .red,
                    status: appState.screenRecordingPermissionGranted == true ? "Granted" : "Not Granted",
                    detail: nil
                )

                if appState.screenRecordingPermissionGranted != true {
                    Button("Grant Access") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            } header: {
                Text("Permissions")
            }
            
            // ── Updates ──
            Section {
                HStack {
                    Text("Current Version")
                    Spacer()
                    Text(updater.currentVersion)
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    updateActionButton
                    Spacer()
                    updateStatusView
                }
            } header: {
                Text("Updates")
            }
        }
        .formStyle(.grouped)
        .onAppear {
            appState.refreshSystemAccess()
            appState.refreshScreenRecordingPermission()
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
