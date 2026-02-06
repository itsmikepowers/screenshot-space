import Foundation
import AppKit
import Combine
import ServiceManagement

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

    @Published var hasPermission: Bool = false

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

        self.hasPermission = AXIsProcessTrusted()

        if SMAppService.mainApp.status == .enabled {
            self.launchAtLogin = true
        }
    }

    // MARK: - Accessibility Permission

    @discardableResult
    func checkPermission() -> Bool {
        let trusted = AXIsProcessTrusted()
        hasPermission = trusted
        return trusted
    }

    /// Triggers the macOS system prompt for Accessibility permission and opens
    /// System Settings to the correct pane.
    func requestPermission() {
        // This call triggers the system prompt to add the app to Accessibility
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
