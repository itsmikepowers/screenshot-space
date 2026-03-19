import Foundation
import AppKit
import Combine
import ServiceManagement

enum AccessibilityPermissionStatus: Equatable {
    case granted
    case missing

    var isGranted: Bool {
        self == .granted
    }

    var title: String {
        isGranted ? "Granted" : "Not Granted"
    }

    var detail: String {
        isGranted
            ? "Screenshot Space can monitor the Option key."
            : "Grant Accessibility access in System Settings to enable the Option key shortcut."
    }

    var symbolName: String {
        isGranted ? "checkmark.circle.fill" : "xmark.circle.fill"
    }
}

enum MonitorStatus: Equatable {
    case inactive
    case active
    case failedToStart(String)

    var isActive: Bool {
        if case .active = self {
            return true
        }

        return false
    }
}

class AppState: ObservableObject {

    // MARK: - Published Properties

    @Published var holdThreshold: Double {
        didSet { UserDefaults.standard.set(holdThreshold, forKey: "holdThreshold") }
    }

    @Published var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: "isEnabled") }
    }

    @Published var launchAtLogin: Bool = false {
        didSet {
            do {
                if launchAtLogin {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                print("Launch at Login error: \(error.localizedDescription)")
            }
        }
    }

    @Published var showInMenuBar: Bool {
        didSet { UserDefaults.standard.set(showInMenuBar, forKey: "showInMenuBar") }
    }

    @Published var showInDock: Bool {
        didSet { UserDefaults.standard.set(showInDock, forKey: "showInDock") }
    }

    @Published private(set) var accessibilityStatus: AccessibilityPermissionStatus
    @Published private(set) var monitorStatus: MonitorStatus = .inactive
    @Published private(set) var systemAccessRefreshID = UUID()

    @Published var hasCompletedOnboarding: Bool {
        didSet { UserDefaults.standard.set(hasCompletedOnboarding, forKey: "hasCompletedOnboarding") }
    }

    @Published var skipAccessibilityCheck: Bool {
        didSet { UserDefaults.standard.set(skipAccessibilityCheck, forKey: "skipAccessibilityCheck") }
    }

    private var cancellables = Set<AnyCancellable>()
    private var permissionPollTimer: Timer?

    var hasPermission: Bool {
        accessibilityStatus.isGranted
    }

    var shouldShowSetupGuidance: Bool {
        if skipAccessibilityCheck {
            return false
        }
        
        if !hasCompletedOnboarding {
            return true
        }

        return false
    }
    
    func skipSetup() {
        skipAccessibilityCheck = true
        hasCompletedOnboarding = true
    }
    
    func resetSkipAccessibilityCheck() {
        skipAccessibilityCheck = false
    }

    var hotkeyStatusTitle: String {
        if !isEnabled {
            return "Disabled"
        }

        if !hasPermission {
            return "Waiting For Accessibility"
        }

        switch monitorStatus {
        case .active:
            return "Active"
        case .inactive:
            return "Inactive"
        case .failedToStart:
            return "Failed to Start"
        }
    }

    var hotkeyStatusDetail: String {
        if !isEnabled {
            return "Screenshot shortcuts are disabled in Settings."
        }

        if !hasPermission {
            return "Grant Accessibility access, then click Check Again or return to the app."
        }

        switch monitorStatus {
        case .active:
            return "The global Option key listener is ready to capture."
        case .inactive:
            return "Accessibility is granted, but the listener is not running yet."
        case .failedToStart(let message):
            return message
        }
    }

    // MARK: - Init

    init() {
        let defaults = UserDefaults.standard

        if defaults.object(forKey: "holdThreshold") != nil {
            self.holdThreshold = defaults.double(forKey: "holdThreshold")
        } else {
            self.holdThreshold = 0.25
        }

        if defaults.object(forKey: "isEnabled") != nil {
            self.isEnabled = defaults.bool(forKey: "isEnabled")
        } else {
            self.isEnabled = true
        }

        if defaults.object(forKey: "showInMenuBar") != nil {
            self.showInMenuBar = defaults.bool(forKey: "showInMenuBar")
        } else {
            self.showInMenuBar = true
        }

        if defaults.object(forKey: "showInDock") != nil {
            self.showInDock = defaults.bool(forKey: "showInDock")
        } else {
            self.showInDock = true
        }

        self.accessibilityStatus = AXIsProcessTrusted() ? .granted : .missing
        self.hasCompletedOnboarding = defaults.bool(forKey: "hasCompletedOnboarding")
        self.skipAccessibilityCheck = defaults.bool(forKey: "skipAccessibilityCheck")

        if SMAppService.mainApp.status == .enabled {
            self.launchAtLogin = true
        }

        observeAppActivation()
        startPermissionPolling()
    }
    
    deinit {
        stopPermissionPolling()
    }

    // MARK: - Accessibility Permission

    @discardableResult
    func refreshSystemAccess(prompt: Bool = false) -> Bool {
        if prompt {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
        }

        let trusted = AXIsProcessTrusted()
        applyAccessibilityTrust(trusted)
        systemAccessRefreshID = UUID()
        return trusted
    }

    /// Triggers the macOS system prompt for Accessibility permission and opens
    /// System Settings to the correct pane.
    func requestPermission() {
        _ = refreshSystemAccess(prompt: true)
    }

    func applyAccessibilityTrust(_ trusted: Bool) {
        accessibilityStatus = trusted ? .granted : .missing

        if !trusted {
            monitorStatus = .inactive
        }
    }

    func updateMonitorStatus(_ status: MonitorStatus) {
        if hasPermission {
            monitorStatus = status
        } else {
            monitorStatus = .inactive
        }
    }

    func completeOnboarding() {
        hasCompletedOnboarding = true
    }

    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    private func observeAppActivation() {
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                _ = self?.refreshSystemAccess()
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Permission Polling
    
    /// Polls for accessibility permission changes every second.
    /// This is necessary because macOS doesn't notify apps when permission is granted.
    private func startPermissionPolling() {
        stopPermissionPolling()
        
        permissionPollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            let currentlyTrusted = AXIsProcessTrusted()
            let wasGranted = self.accessibilityStatus.isGranted
            
            if currentlyTrusted != wasGranted {
                self.applyAccessibilityTrust(currentlyTrusted)
                self.systemAccessRefreshID = UUID()
            }
        }
    }
    
    private func stopPermissionPolling() {
        permissionPollTimer?.invalidate()
        permissionPollTimer = nil
    }
}
