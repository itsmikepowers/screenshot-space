import SwiftUI

struct MainWindowView: View {
    @EnvironmentObject var appState: AppState
    @State private var showOnboarding = false

    var body: some View {
        TabView {
            ScreenshotGalleryView()
                .tabItem {
                    Label("Screenshots", systemImage: "photo.on.rectangle.angled")
                }

            SearchView()
                .tabItem {
                    Label("Search", systemImage: "magnifyingglass")
                }

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
        }
        .frame(minWidth: 700, minHeight: 500)
        .sheet(isPresented: $showOnboarding) {
            OnboardingView()
                .environmentObject(appState)
        }
        .onAppear {
            updateOnboardingPresentation()
        }
        .onChange(of: appState.accessibilityStatus) { _ in
            updateOnboardingPresentation()
        }
        .onChange(of: appState.monitorStatus) { _ in
            updateOnboardingPresentation()
        }
        .onChange(of: appState.hasCompletedOnboarding) { _ in
            updateOnboardingPresentation()
        }
        .onChange(of: appState.isEnabled) { _ in
            updateOnboardingPresentation()
        }
    }

    private func updateOnboardingPresentation() {
        showOnboarding = appState.shouldShowSetupGuidance
    }
}
