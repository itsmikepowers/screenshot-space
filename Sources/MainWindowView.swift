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
            let hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
            if !appState.hasPermission && !hasCompletedOnboarding {
                showOnboarding = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .onboardingComplete)) { _ in
            showOnboarding = false
        }
    }
}
