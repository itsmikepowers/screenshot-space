import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var appState: AppState
    @State private var permissionTimer: Timer?
    @State private var didRequestPermission = false

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "camera.viewfinder")
                .font(.system(size: 48))
                .foregroundColor(.accentColor)

            Text("Screenshot Space")
                .font(.title.bold())

            Text("Take screenshots with just the Option key.\nTap for full screen \u{2022} Hold to select an area.\nEverything goes straight to your clipboard.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .lineSpacing(3)

            Divider()
                .padding(.horizontal, 40)

            // ── Permission Status ──
            HStack(spacing: 8) {
                Image(systemName: appState.hasPermission
                      ? "checkmark.circle.fill"
                      : "exclamationmark.triangle.fill")
                    .foregroundColor(appState.hasPermission ? .green : .orange)
                    .font(.title3)

                Text(appState.hasPermission
                     ? "Permission Granted"
                     : "Accessibility Permission Required")
                    .font(.headline)
            }

            if appState.hasPermission {
                Button("Get Started") {
                    NotificationCenter.default.post(name: .onboardingComplete, object: nil)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            } else if !didRequestPermission {
                Text("Screenshot Space needs Accessibility access to\ndetect the Option key and trigger screenshots.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)

                Button("Grant Permission") {
                    appState.requestPermission()
                    didRequestPermission = true
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            } else {
                Text("Toggle ScreenshotSpace ON in System Settings,\nthen come back and click Continue.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)

                HStack(spacing: 12) {
                    Button("Continue") {
                        appState.checkPermission()
                        if appState.hasPermission {
                            NotificationCenter.default.post(name: .onboardingComplete, object: nil)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Button("Open Settings") {
                        appState.openAccessibilitySettings()
                    }
                    .controlSize(.large)
                }
            }

            Spacer()
        }
        .padding(30)
        .frame(minWidth: 440, idealWidth: 440, minHeight: 360, idealHeight: 360)
        .onAppear { startPolling() }
        .onDisappear { stopPolling() }
    }

    // MARK: - Permission Polling

    private func startPolling() {
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            if appState.checkPermission() {
                stopPolling()
            }
        }
    }

    private func stopPolling() {
        permissionTimer?.invalidate()
        permissionTimer = nil
    }
}
