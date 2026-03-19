import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

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

            VStack(spacing: 12) {
                onboardingStatusCard(
                    title: "Accessibility Access",
                    symbolName: appState.accessibilityStatus.symbolName,
                    tint: appState.hasPermission ? .green : .orange,
                    status: appState.accessibilityStatus.title,
                    detail: appState.accessibilityStatus.detail
                )

                onboardingStatusCard(
                    title: "Hotkey Listener",
                    symbolName: hotkeySymbolName,
                    tint: hotkeyTintColor,
                    status: appState.hotkeyStatusTitle,
                    detail: appState.hotkeyStatusDetail
                )
            }

            Text(onboardingMessage)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)

            if appState.hasPermission && appState.monitorStatus.isActive {
                Button(appState.hasCompletedOnboarding ? "Done" : "Get Started") {
                    appState.completeOnboarding()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            } else {
                HStack(spacing: 12) {
                    if !appState.hasPermission {
                        Button("Grant Access") {
                            appState.requestPermission()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)

                        Button("Open Settings") {
                            appState.openAccessibilitySettings()
                        }
                        .controlSize(.large)
                    } else {
                        Button("Check Again") {
                            appState.refreshSystemAccess()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    }

                    if appState.hasCompletedOnboarding {
                        Button("Close") {
                            dismiss()
                        }
                        .controlSize(.large)
                    }
                }
            }

            Spacer()
        }
        .padding(30)
        .frame(minWidth: 440, idealWidth: 440, minHeight: 360, idealHeight: 360)
        .onAppear {
            appState.refreshSystemAccess()
        }
    }

    private var onboardingMessage: String {
        if !appState.hasPermission {
            return "Screenshot Space needs Accessibility access to detect the Option key and trigger screenshots. Grant access in System Settings, then return here."
        }

        if appState.monitorStatus.isActive {
            return "Accessibility is granted and the global Option key listener is ready to capture."
        }

        return "Accessibility is granted, but the hotkey listener is not ready yet. Check Again to reconnect it without relaunching the app."
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
    private func onboardingStatusCard(
        title: String,
        symbolName: String,
        tint: Color,
        status: String,
        detail: String
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbolName)
                .foregroundColor(tint)
                .frame(width: 20, height: 20)
                .font(.title3)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(title)
                        .font(.headline)
                    Spacer()
                    Text(status)
                        .foregroundColor(.secondary)
                }

                Text(detail)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(14)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
