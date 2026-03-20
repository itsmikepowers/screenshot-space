import SwiftUI

enum SidebarTab: String, CaseIterable, Identifiable {
    case screenshots = "Screenshots"
    case search = "Search"
    case shortcuts = "Shortcuts"
    case settings = "Settings"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .screenshots: return "photo.on.rectangle.angled"
        case .search: return "magnifyingglass"
        case .shortcuts: return "keyboard"
        case .settings: return "gear"
        }
    }
}

struct MainWindowView: View {
    @EnvironmentObject var appState: AppState
    @State private var showOnboarding = false
    @State private var selectedTab: SidebarTab = .screenshots

    var body: some View {
        HStack(spacing: 0) {
            // Custom sidebar
            VStack(spacing: 0) {
                List(SidebarTab.allCases, selection: $selectedTab) { tab in
                    Label(tab.rawValue, systemImage: tab.icon)
                        .tag(tab)
                }
                .listStyle(.sidebar)
            }
            .frame(width: 160)
            .background(VisualEffectView(material: .sidebar, blendingMode: .behindWindow))
            
            // Main content
            detailView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 800, minHeight: 500)
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
    
    @ViewBuilder
    private var detailView: some View {
        switch selectedTab {
        case .screenshots:
            ScreenshotGalleryView()
        case .search:
            SearchView()
        case .shortcuts:
            ShortcutsView()
        case .settings:
            SettingsView()
        }
    }

    private func updateOnboardingPresentation() {
        showOnboarding = appState.shouldShowSetupGuidance
    }
}

// MARK: - Visual Effect View for sidebar background

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
