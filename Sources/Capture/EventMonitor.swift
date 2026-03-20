import Cocoa
import os.log

/// Configuration for a single screenshot mode's hotkey
struct HotkeyConfig {
    var isEnabled: Bool
    var modifiers: CGEventFlags
    var isTapAndHold: Bool
    var holdThreshold: TimeInterval
    var action: (() -> Void)?
    
    /// Returns the relevant modifier flags only (strips device-specific bits)
    var relevantModifiers: CGEventFlags {
        modifiers.intersection(EventMonitor.relevantModifierMask)
    }
}

/// Monitors modifier keys globally via a CGEvent tap.
/// Supports multiple screenshot modes, each with its own hotkey and tap/hold behavior.
class EventMonitor {
    
    private static let logger = Logger(subsystem: "com.screenshotspace", category: "EventMonitor")
    
    /// The modifier flags we care about - strips out device-specific bits
    static let relevantModifierMask: CGEventFlags = [
        .maskCommand, .maskControl, .maskShift, .maskAlternate, .maskSecondaryFn
    ]

    enum StartResult: Equatable {
        case started
        case alreadyRunning
        case permissionDenied
        case failedToCreateTap
    }

    // MARK: - Configuration
    
    var fullScreenConfig = HotkeyConfig(isEnabled: true, modifiers: [.maskAlternate], isTapAndHold: false, holdThreshold: 0.35, action: nil)
    var dragConfig = HotkeyConfig(isEnabled: true, modifiers: [.maskAlternate], isTapAndHold: true, holdThreshold: 0.35, action: nil)
    var regionConfig = HotkeyConfig(isEnabled: false, modifiers: [.maskSecondaryFn], isTapAndHold: false, holdThreshold: 0.35, action: nil)
    
    var onTapDisabled: (() -> Void)?
    
    // Legacy properties for backward compatibility
    var holdThreshold: TimeInterval {
        get { dragConfig.holdThreshold }
        set { dragConfig.holdThreshold = newValue }
    }
    var triggerModifiers: CGEventFlags {
        get { fullScreenConfig.modifiers }
        set {
            fullScreenConfig.modifiers = newValue
            dragConfig.modifiers = newValue
        }
    }
    var recaptureTriggerModifiers: CGEventFlags {
        get { regionConfig.modifiers }
        set { regionConfig.modifiers = newValue }
    }
    var onTap: (() -> Void)? {
        get { fullScreenConfig.action }
        set { fullScreenConfig.action = newValue }
    }
    var onHold: (() -> Void)? {
        get { dragConfig.action }
        set { dragConfig.action = newValue }
    }
    var onRecaptureTap: (() -> Void)? {
        get { regionConfig.action }
        set { regionConfig.action = newValue }
    }

    // MARK: - Internal State

    private enum ActiveMode: String { case none, fullScreen, drag, region }

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var holdTimer: DispatchSourceTimer?
    private var activeMode: ActiveMode = .none
    private var activeModifiers: CGEventFlags = []
    private var activationTime: CFAbsoluteTime = 0
    private var holdTriggered = false
    private var isProcessingAction = false
    private var lastEventTime: UInt64 = 0
    
    /// When a tap-and-hold mode is active, this stores a fallback tap action
    /// (e.g., fullScreen tap when drag tap-and-hold is active with same modifiers)
    private var tapFallbackAction: (() -> Void)?
    
    /// Minimum time (seconds) a modifier must be held before release triggers tap action
    /// This prevents accidental triggers from very quick key bounces
    private let minimumTapDuration: TimeInterval = 0.03
    
    /// Debounce interval for rapid events (seconds)
    private let debounceInterval: TimeInterval = 0.015
    
    private let stateQueue = DispatchQueue(label: "com.screenshotspace.eventmonitor.state")

    // MARK: - Start / Stop

    /// Starts the event tap and reports whether startup failed because
    /// permission is missing or because macOS could not create the tap.
    func start() -> StartResult {
        guard eventTap == nil else { return .alreadyRunning }

        guard AXIsProcessTrusted() else {
            Self.logger.warning("Cannot start: Accessibility permission not granted")
            return .permissionDenied
        }
        
        let eventMask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: eventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            Self.logger.error("Failed to create CGEvent tap")
            return .failedToCreateTap
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        
        Self.logger.info("Event tap started successfully")
        logCurrentConfig()

        return .started
    }

    func stop() {
        cancelHoldTimer()
        
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        
        stateQueue.sync {
            activeMode = .none
            activeModifiers = []
            activationTime = 0
            holdTriggered = false
            isProcessingAction = false
            tapFallbackAction = nil
        }
        
        Self.logger.info("Event tap stopped")
    }

    deinit {
        stop()
    }
    
    private func logCurrentConfig() {
        Self.logger.debug("Config - FullScreen: enabled=\(self.fullScreenConfig.isEnabled), mods=\(self.describeModifiers(self.fullScreenConfig.modifiers)), tapAndHold=\(self.fullScreenConfig.isTapAndHold)")
        Self.logger.debug("Config - Drag: enabled=\(self.dragConfig.isEnabled), mods=\(self.describeModifiers(self.dragConfig.modifiers)), tapAndHold=\(self.dragConfig.isTapAndHold)")
        Self.logger.debug("Config - Region: enabled=\(self.regionConfig.isEnabled), mods=\(self.describeModifiers(self.regionConfig.modifiers)), tapAndHold=\(self.regionConfig.isTapAndHold)")
    }
    
    private func describeModifiers(_ flags: CGEventFlags) -> String {
        var parts: [String] = []
        if flags.contains(.maskSecondaryFn) { parts.append("Fn") }
        if flags.contains(.maskControl) { parts.append("⌃") }
        if flags.contains(.maskShift) { parts.append("⇧") }
        if flags.contains(.maskAlternate) { parts.append("⌥") }
        if flags.contains(.maskCommand) { parts.append("⌘") }
        return parts.isEmpty ? "none" : parts.joined(separator: "+")
    }
    
    // MARK: - Timer Management
    
    private func cancelHoldTimer() {
        holdTimer?.cancel()
        holdTimer = nil
    }
    
    private func scheduleHoldTimer(threshold: TimeInterval) {
        cancelHoldTimer()
        
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + threshold)
        timer.setEventHandler { [weak self] in
            self?.handleHoldTimeout()
        }
        holdTimer = timer
        timer.resume()
    }
    
    private func handleHoldTimeout() {
        var actionToRun: (() -> Void)?
        var modeName: String = ""
        
        stateQueue.sync {
            guard !holdTriggered, !isProcessingAction else { return }
            
            switch activeMode {
            case .fullScreen where fullScreenConfig.isTapAndHold:
                holdTriggered = true
                isProcessingAction = true
                actionToRun = fullScreenConfig.action
                modeName = "fullScreen"
            case .drag where dragConfig.isTapAndHold:
                holdTriggered = true
                isProcessingAction = true
                actionToRun = dragConfig.action
                modeName = "drag"
            case .region where regionConfig.isTapAndHold:
                holdTriggered = true
                isProcessingAction = true
                actionToRun = regionConfig.action
                modeName = "region"
            default:
                break
            }
        }

        if let action = actionToRun {
            Self.logger.info("Hold triggered for mode: \(modeName)")
            action()
        }

        stateQueue.sync {
            isProcessingAction = false
        }
    }

    // MARK: - Event Handling

    /// Check if the event tap is currently enabled and valid
    var isRunning: Bool {
        guard let tap = eventTap else { return false }
        return CGEvent.tapIsEnabled(tap: tap)
    }
    
    /// Attempt to re-enable the tap if it was disabled
    func reactivate() {
        guard let tap = eventTap else { return }
        if !CGEvent.tapIsEnabled(tap: tap) {
            CGEvent.tapEnable(tap: tap, enable: true)
            Self.logger.info("Event tap reactivated")
        }
    }
    
    /// Check if the given modifiers match a config's modifiers
    /// Uses subset checking to be more lenient with extra system flags
    private func modifiersMatch(_ current: CGEventFlags, _ config: HotkeyConfig) -> Bool {
        let currentRelevant = current.intersection(Self.relevantModifierMask)
        let configRelevant = config.relevantModifiers
        
        // Exact match on relevant modifiers only
        return currentRelevant == configRelevant && !configRelevant.isEmpty
    }

    fileprivate func handleEvent(type: CGEventType, event: CGEvent) {
        // Re-enable the tap if macOS disabled it due to timeout or user action
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            Self.logger.warning("Event tap was disabled by system (type: \(type.rawValue)), re-enabling...")
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            DispatchQueue.main.async { [weak self] in
                self?.onTapDisabled?()
            }
            return
        }

        guard type == .flagsChanged else { return }

        let flags = event.flags
        let eventTime = event.timestamp
        let currentTime = CFAbsoluteTimeGetCurrent()

        // Extract only the relevant modifier flags
        let currentModifiers = flags.intersection(Self.relevantModifierMask)

        // Debounce rapid events
        if eventTime > 0 && lastEventTime > 0 {
            let timeDelta = Double(eventTime - lastEventTime) / 1_000_000_000.0
            if timeDelta < debounceInterval {
                return
            }
        }
        lastEventTime = eventTime

        // Find which mode matches the current modifiers
        // Priority: check tap-and-hold modes first (they need timers), then tap modes
        let matchedMode: ActiveMode
        let matchedConfig: HotkeyConfig?
        
        // Also track if there's a tap mode with the same modifiers (for quick-release fallback)
        var tapFallbackAction: (() -> Void)? = nil
        
        if dragConfig.isEnabled && dragConfig.isTapAndHold && modifiersMatch(currentModifiers, dragConfig) {
            matchedMode = .drag
            matchedConfig = dragConfig
            // Check if fullScreen has same modifiers and is a tap mode - use as fallback
            if fullScreenConfig.isEnabled && !fullScreenConfig.isTapAndHold && modifiersMatch(currentModifiers, fullScreenConfig) {
                tapFallbackAction = fullScreenConfig.action
            }
        } else if fullScreenConfig.isEnabled && fullScreenConfig.isTapAndHold && modifiersMatch(currentModifiers, fullScreenConfig) {
            matchedMode = .fullScreen
            matchedConfig = fullScreenConfig
        } else if regionConfig.isEnabled && regionConfig.isTapAndHold && modifiersMatch(currentModifiers, regionConfig) {
            matchedMode = .region
            matchedConfig = regionConfig
        } else if fullScreenConfig.isEnabled && !fullScreenConfig.isTapAndHold && modifiersMatch(currentModifiers, fullScreenConfig) {
            matchedMode = .fullScreen
            matchedConfig = fullScreenConfig
        } else if dragConfig.isEnabled && !dragConfig.isTapAndHold && modifiersMatch(currentModifiers, dragConfig) {
            matchedMode = .drag
            matchedConfig = dragConfig
        } else if regionConfig.isEnabled && !regionConfig.isTapAndHold && modifiersMatch(currentModifiers, regionConfig) {
            matchedMode = .region
            matchedConfig = regionConfig
        } else {
            matchedMode = .none
            matchedConfig = nil
        }

        var actionToTrigger: (() -> Void)?
        var shouldStartTimer = false
        var timerThreshold: TimeInterval = 0.25
        var triggerModeName: String = ""

        stateQueue.sync {
            let previousMode = self.activeMode
            let previousModifiers = self.activeModifiers
            
            // ── Modifier DOWN (new mode activated) ──
            if previousMode == .none && matchedMode != .none {
                self.activeMode = matchedMode
                self.activeModifiers = currentModifiers
                self.activationTime = currentTime
                self.holdTriggered = false
                self.tapFallbackAction = tapFallbackAction
                
                Self.logger.debug("Mode activated: \(matchedMode.rawValue), modifiers: \(self.describeModifiers(currentModifiers)), hasTapFallback: \(tapFallbackAction != nil)")
                
                if let config = matchedConfig, config.isTapAndHold {
                    shouldStartTimer = true
                    timerThreshold = config.holdThreshold
                }
            }
            
            // ── Modifier UP (mode deactivated) ──
            // Check if modifiers changed from what we were tracking
            if previousMode != .none && currentModifiers != previousModifiers {
                let wasMode = previousMode
                let holdDuration = currentTime - self.activationTime
                let savedTapFallback = self.tapFallbackAction
                
                Self.logger.debug("Mode deactivated: \(wasMode.rawValue), held for \(String(format: "%.3f", holdDuration))s, holdTriggered=\(self.holdTriggered)")
                
                self.activeMode = .none
                self.activeModifiers = []
                self.tapFallbackAction = nil
                
                // Only trigger action if:
                // 1. Hold wasn't already triggered
                // 2. Not currently processing an action
                // 3. The key was held long enough (not a bounce)
                if !self.holdTriggered && !self.isProcessingAction && holdDuration >= self.minimumTapDuration {
                    switch wasMode {
                    case .fullScreen:
                        if !fullScreenConfig.isTapAndHold {
                            // This is a tap mode - trigger it
                            self.isProcessingAction = true
                            actionToTrigger = fullScreenConfig.action
                            triggerModeName = "fullScreen (tap)"
                        }
                    case .drag:
                        if !dragConfig.isTapAndHold {
                            // This is a tap mode - trigger it
                            self.isProcessingAction = true
                            actionToTrigger = dragConfig.action
                            triggerModeName = "drag (tap)"
                        } else if let fallback = savedTapFallback {
                            // Drag is tap-and-hold, but released before threshold
                            // Use the tap fallback (e.g., fullScreen tap)
                            self.isProcessingAction = true
                            actionToTrigger = fallback
                            triggerModeName = "fullScreen (tap fallback)"
                        }
                    case .region:
                        if !regionConfig.isTapAndHold {
                            self.isProcessingAction = true
                            actionToTrigger = regionConfig.action
                            triggerModeName = "region (tap)"
                        }
                    case .none:
                        break
                    }
                } else if holdDuration < self.minimumTapDuration {
                    Self.logger.debug("Tap ignored: duration \(String(format: "%.3f", holdDuration))s < minimum \(self.minimumTapDuration)s")
                }
            }
        }

        if shouldStartTimer {
            DispatchQueue.main.async { [weak self] in
                self?.scheduleHoldTimer(threshold: timerThreshold)
            }
        } else if matchedMode == .none {
            DispatchQueue.main.async { [weak self] in
                self?.cancelHoldTimer()
            }
        }

        if let action = actionToTrigger {
            Self.logger.info("Tap triggered for mode: \(triggerModeName)")
            DispatchQueue.main.async { [weak self] in
                action()
                self?.stateQueue.sync {
                    self?.isProcessingAction = false
                }
            }
        }
    }
}

// MARK: - C Function Callback

private func eventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo = userInfo else {
        return Unmanaged.passUnretained(event)
    }
    let monitor = Unmanaged<EventMonitor>.fromOpaque(userInfo).takeUnretainedValue()
    monitor.handleEvent(type: type, event: event)
    return Unmanaged.passUnretained(event)
}
