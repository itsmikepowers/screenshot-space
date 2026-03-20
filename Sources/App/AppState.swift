import Foundation
import AppKit
import Combine
import ServiceManagement
import CoreGraphics

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

// MARK: - Screenshot Mode Configuration

enum TriggerType: String, CaseIterable, Identifiable {
    case tap = "tap"
    case tapAndHold = "tapAndHold"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .tap: return "Tap"
        case .tapAndHold: return "Tap and Hold"
        }
    }
}

struct ScreenshotModeConfig: Equatable {
    var isEnabled: Bool
    var modifiers: UInt64
    var triggerType: TriggerType
    var holdThreshold: Double
    
    static let defaultFullScreen = ScreenshotModeConfig(
        isEnabled: true,
        modifiers: CGEventFlags.maskAlternate.rawValue,
        triggerType: .tap,
        holdThreshold: 0.25
    )
    
    static let defaultDrag = ScreenshotModeConfig(
        isEnabled: true,
        modifiers: CGEventFlags.maskAlternate.rawValue,
        triggerType: .tapAndHold,
        holdThreshold: 0.25
    )
    
    static let defaultRegion = ScreenshotModeConfig(
        isEnabled: false,
        modifiers: CGEventFlags([.maskSecondaryFn]).rawValue,
        triggerType: .tap,
        holdThreshold: 0.25
    )
    
    func displayString(short: Bool = true) -> String {
        let flags = CGEventFlags(rawValue: modifiers)
        var parts: [String] = []
        if short {
            if flags.contains(.maskSecondaryFn) { parts.append("🌐") }
            if flags.contains(.maskControl) { parts.append("⌃") }
            if flags.contains(.maskShift) { parts.append("⇧") }
            if flags.contains(.maskAlternate) { parts.append("⌥") }
            if flags.contains(.maskCommand) { parts.append("⌘") }
        } else {
            if flags.contains(.maskSecondaryFn) { parts.append("🌐 Fn") }
            if flags.contains(.maskControl) { parts.append("⌃ Control") }
            if flags.contains(.maskShift) { parts.append("⇧ Shift") }
            if flags.contains(.maskAlternate) { parts.append("⌥ Option") }
            if flags.contains(.maskCommand) { parts.append("⌘ Command") }
        }
        return parts.isEmpty ? "None" : parts.joined(separator: short ? "" : " + ")
    }
}

class AppState: ObservableObject {

    // MARK: - Published Properties
    
    // Screenshot Mode Configurations
    @Published var fullScreenMode: ScreenshotModeConfig {
        didSet { saveFullScreenMode() }
    }
    
    @Published var dragMode: ScreenshotModeConfig {
        didSet { saveDragMode() }
    }
    
    @Published var regionMode: ScreenshotModeConfig {
        didSet { saveRegionMode() }
    }

    // Legacy properties for backward compatibility (computed from new modes)
    var holdThreshold: Double {
        get { dragMode.holdThreshold }
        set { dragMode.holdThreshold = newValue }
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

    // Legacy computed property - maps to fullScreenMode for backward compatibility
    var hotkeyModifiers: UInt64 {
        get { fullScreenMode.modifiers }
        set { fullScreenMode.modifiers = newValue }
    }

    @Published var screenshotDirectory: String {
        didSet { UserDefaults.standard.set(screenshotDirectory, forKey: "screenshotDirectory") }
    }

    @Published var lastCapturedRegion: CGRect? {
        didSet {
            if let r = lastCapturedRegion {
                UserDefaults.standard.set(
                    "\(r.origin.x),\(r.origin.y),\(r.size.width),\(r.size.height)",
                    forKey: "lastCapturedRegion"
                )
            } else {
                UserDefaults.standard.removeObject(forKey: "lastCapturedRegion")
            }
        }
    }

    // Legacy computed property - maps to regionMode for backward compatibility
    var recaptureHotkeyModifiers: UInt64 {
        get { regionMode.modifiers }
        set { regionMode.modifiers = newValue }
    }

    @Published private(set) var accessibilityStatus: AccessibilityPermissionStatus
    @Published private(set) var monitorStatus: MonitorStatus = .inactive
    @Published private(set) var systemAccessRefreshID = UUID()
    /// `nil` until the user taps **Check access** in Settings — avoids `CGWindowListCreateImage` and the
    /// Screen Recording prompt until they explicitly choose to test.
    @Published private(set) var screenRecordingPermissionGranted: Bool? = nil

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

    var hotkeyDisplayString: String {
        fullScreenMode.displayString(short: true)
    }

    var hotkeyDisplayStringLong: String {
        fullScreenMode.displayString(short: false)
    }

    var recaptureHotkeyDisplayString: String {
        regionMode.displayString(short: true)
    }

    var recaptureHotkeyDisplayStringLong: String {
        regionMode.displayString(short: false)
    }
    
    // MARK: - Conflict Detection
    
    struct HotkeyConflict {
        let mode1: String
        let mode2: String
        let reason: String
    }
    
    func detectConflicts() -> [HotkeyConflict] {
        var conflicts: [HotkeyConflict] = []
        
        let modes: [(String, ScreenshotModeConfig)] = [
            ("Full Screen", fullScreenMode),
            ("Drag", dragMode),
            ("Region", regionMode)
        ]
        
        for i in 0..<modes.count {
            guard modes[i].1.isEnabled else { continue }
            for j in (i+1)..<modes.count {
                guard modes[j].1.isEnabled else { continue }
                
                let m1 = modes[i]
                let m2 = modes[j]
                
                if m1.1.modifiers == m2.1.modifiers {
                    if m1.1.triggerType == m2.1.triggerType {
                        conflicts.append(HotkeyConflict(
                            mode1: m1.0,
                            mode2: m2.0,
                            reason: "Same hotkey and trigger type — \(m2.0) will be ignored"
                        ))
                    }
                }
            }
        }
        
        return conflicts
    }

    var lastCapturedRegionDisplay: String {
        guard let r = lastCapturedRegion else { return "No region defined" }
        return "\(Int(r.width))×\(Int(r.height)) at (\(Int(r.origin.x)), \(Int(r.origin.y)))"
    }

    var screenshotDirectoryDisplay: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if screenshotDirectory.hasPrefix(home) {
            return "~" + screenshotDirectory.dropFirst(home.count)
        }
        return screenshotDirectory
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

        // Load screenshot mode configurations
        self.fullScreenMode = Self.loadModeConfig(defaults: defaults, key: "fullScreenMode", legacy: (
            modifiersKey: "hotkeyModifiers",
            defaultConfig: .defaultFullScreen
        ))
        
        self.dragMode = Self.loadModeConfig(defaults: defaults, key: "dragMode", legacy: (
            modifiersKey: "hotkeyModifiers",
            defaultConfig: .defaultDrag
        ))
        
        // For region mode, also check legacy holdThreshold
        var regionConfig = Self.loadModeConfig(defaults: defaults, key: "regionMode", legacy: (
            modifiersKey: "recaptureHotkeyModifiers",
            defaultConfig: .defaultRegion
        ))
        // If we loaded from legacy, check if a region was defined (which means it should be enabled)
        if defaults.object(forKey: "regionMode") == nil && defaults.string(forKey: "lastCapturedRegion") != nil {
            regionConfig.isEnabled = true
        }
        self.regionMode = regionConfig

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

        self.screenshotDirectory = defaults.string(forKey: "screenshotDirectory")
            ?? ScreenshotManager.defaultDirectoryPath

        // Restore recapture region
        if let regionString = defaults.string(forKey: "lastCapturedRegion") {
            let parts = regionString.split(separator: ",").compactMap { Double($0) }
            if parts.count == 4 {
                self.lastCapturedRegion = CGRect(x: parts[0], y: parts[1], width: parts[2], height: parts[3])
            } else {
                self.lastCapturedRegion = nil
            }
        } else {
            self.lastCapturedRegion = nil
        }

        self.accessibilityStatus = AXIsProcessTrusted() ? .granted : .missing
        self.hasCompletedOnboarding = defaults.bool(forKey: "hasCompletedOnboarding")
        self.skipAccessibilityCheck = defaults.bool(forKey: "skipAccessibilityCheck")

        if SMAppService.mainApp.status == .enabled {
            self.launchAtLogin = true
        }

        observeAppActivation()
        startPermissionPolling()
        
        // Migrate legacy holdThreshold to dragMode if present (must be after all properties initialized)
        if defaults.object(forKey: "dragMode") == nil && defaults.object(forKey: "holdThreshold") != nil {
            self.dragMode.holdThreshold = defaults.double(forKey: "holdThreshold")
        }
    }
    
    // MARK: - Mode Config Persistence
    
    private static func loadModeConfig(
        defaults: UserDefaults,
        key: String,
        legacy: (modifiersKey: String, defaultConfig: ScreenshotModeConfig)
    ) -> ScreenshotModeConfig {
        if let data = defaults.data(forKey: key),
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return ScreenshotModeConfig(
                isEnabled: dict["isEnabled"] as? Bool ?? legacy.defaultConfig.isEnabled,
                modifiers: (dict["modifiers"] as? NSNumber)?.uint64Value ?? legacy.defaultConfig.modifiers,
                triggerType: TriggerType(rawValue: dict["triggerType"] as? String ?? "") ?? legacy.defaultConfig.triggerType,
                holdThreshold: dict["holdThreshold"] as? Double ?? legacy.defaultConfig.holdThreshold
            )
        }
        
        // Fall back to legacy settings
        var config = legacy.defaultConfig
        if defaults.object(forKey: legacy.modifiersKey) != nil {
            config.modifiers = UInt64(defaults.integer(forKey: legacy.modifiersKey))
        }
        return config
    }
    
    private func saveModeConfig(_ config: ScreenshotModeConfig, key: String) {
        let dict: [String: Any] = [
            "isEnabled": config.isEnabled,
            "modifiers": NSNumber(value: config.modifiers),
            "triggerType": config.triggerType.rawValue,
            "holdThreshold": config.holdThreshold
        ]
        if let data = try? JSONSerialization.data(withJSONObject: dict) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
    
    private func saveFullScreenMode() {
        saveModeConfig(fullScreenMode, key: "fullScreenMode")
    }
    
    private func saveDragMode() {
        saveModeConfig(dragMode, key: "dragMode")
    }
    
    private func saveRegionMode() {
        saveModeConfig(regionMode, key: "regionMode")
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

    /// Probes Screen Recording with a 1×1 capture. Only call from an explicit user action (e.g. Check access).
    func refreshScreenRecordingPermission() {
        let testRect = CGRect(x: 0, y: 0, width: 1, height: 1)
        let img = CGWindowListCreateImage(testRect, .optionOnScreenOnly, kCGNullWindowID, .nominalResolution)
        screenRecordingPermissionGranted = (img != nil)
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
