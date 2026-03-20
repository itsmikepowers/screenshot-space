import Cocoa

/// Configuration for a single screenshot mode's hotkey
struct HotkeyConfig {
    var isEnabled: Bool
    var modifiers: CGEventFlags
    var isTapAndHold: Bool
    var holdThreshold: TimeInterval
    var action: (() -> Void)?
}

/// Monitors modifier keys globally via a CGEvent tap.
/// Supports multiple screenshot modes, each with its own hotkey and tap/hold behavior.
class EventMonitor {

    enum StartResult: Equatable {
        case started
        case alreadyRunning
        case permissionDenied
        case failedToCreateTap
    }

    // MARK: - Configuration
    
    var fullScreenConfig = HotkeyConfig(isEnabled: true, modifiers: [.maskAlternate], isTapAndHold: false, holdThreshold: 0.25, action: nil)
    var dragConfig = HotkeyConfig(isEnabled: true, modifiers: [.maskAlternate], isTapAndHold: true, holdThreshold: 0.25, action: nil)
    var regionConfig = HotkeyConfig(isEnabled: false, modifiers: [.maskSecondaryFn], isTapAndHold: false, holdThreshold: 0.25, action: nil)
    
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

    private enum ActiveMode { case none, fullScreen, drag, region }

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var holdTimer: DispatchSourceTimer?
    private var activeMode: ActiveMode = .none
    private var activeModifiers: CGEventFlags = []
    private var holdTriggered = false
    private var isProcessingAction = false
    private var lastEventTime: UInt64 = 0
    
    private let stateQueue = DispatchQueue(label: "com.screenshotspace.eventmonitor.state")

    // MARK: - Start / Stop

    /// Starts the event tap and reports whether startup failed because
    /// permission is missing or because macOS could not create the tap.
    func start() -> StartResult {
        guard eventTap == nil else { return .alreadyRunning }

        guard AXIsProcessTrusted() else {
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
            return .failedToCreateTap
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

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
            holdTriggered = false
            isProcessingAction = false
        }
    }

    deinit {
        stop()
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
        
        stateQueue.sync {
            guard !holdTriggered, !isProcessingAction else { return }
            
            switch activeMode {
            case .fullScreen where fullScreenConfig.isTapAndHold:
                holdTriggered = true
                isProcessingAction = true
                actionToRun = fullScreenConfig.action
            case .drag where dragConfig.isTapAndHold:
                holdTriggered = true
                isProcessingAction = true
                actionToRun = dragConfig.action
            case .region where regionConfig.isTapAndHold:
                holdTriggered = true
                isProcessingAction = true
                actionToRun = regionConfig.action
            default:
                break
            }
        }

        actionToRun?()

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
        }
    }

    fileprivate func handleEvent(type: CGEventType, event: CGEvent) {
        // Re-enable the tap if macOS disabled it due to timeout or user action
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
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

        // Check which modifier combination is pressed
        let allModifiers: CGEventFlags = [.maskCommand, .maskControl, .maskShift, .maskAlternate, .maskSecondaryFn]
        let currentModifiers = flags.intersection(allModifiers)

        // Debounce rapid events (within 10ms)
        if eventTime > 0 && lastEventTime > 0 {
            let timeDelta = Double(eventTime - lastEventTime) / 1_000_000_000.0
            if timeDelta < 0.010 {
                return
            }
        }
        lastEventTime = eventTime

        // Find which mode matches the current modifiers
        // Priority: check tap-and-hold modes first (they need timers), then tap modes
        let matchedMode: ActiveMode
        let matchedConfig: HotkeyConfig?
        
        if dragConfig.isEnabled && dragConfig.isTapAndHold && currentModifiers == dragConfig.modifiers {
            matchedMode = .drag
            matchedConfig = dragConfig
        } else if fullScreenConfig.isEnabled && fullScreenConfig.isTapAndHold && currentModifiers == fullScreenConfig.modifiers {
            matchedMode = .fullScreen
            matchedConfig = fullScreenConfig
        } else if regionConfig.isEnabled && regionConfig.isTapAndHold && currentModifiers == regionConfig.modifiers {
            matchedMode = .region
            matchedConfig = regionConfig
        } else if fullScreenConfig.isEnabled && !fullScreenConfig.isTapAndHold && currentModifiers == fullScreenConfig.modifiers {
            matchedMode = .fullScreen
            matchedConfig = fullScreenConfig
        } else if dragConfig.isEnabled && !dragConfig.isTapAndHold && currentModifiers == dragConfig.modifiers {
            matchedMode = .drag
            matchedConfig = dragConfig
        } else if regionConfig.isEnabled && !regionConfig.isTapAndHold && currentModifiers == regionConfig.modifiers {
            matchedMode = .region
            matchedConfig = regionConfig
        } else {
            matchedMode = .none
            matchedConfig = nil
        }

        var actionToTrigger: (() -> Void)?
        var shouldStartTimer = false
        var timerThreshold: TimeInterval = 0.25

        stateQueue.sync {
            let previousMode = self.activeMode
            let previousModifiers = self.activeModifiers
            
            // ── Modifier DOWN (new mode activated) ──
            if previousMode == .none && matchedMode != .none {
                self.activeMode = matchedMode
                self.activeModifiers = currentModifiers
                self.holdTriggered = false
                
                if let config = matchedConfig, config.isTapAndHold {
                    shouldStartTimer = true
                    timerThreshold = config.holdThreshold
                }
            }
            
            // ── Modifier UP (mode deactivated) ──
            if previousMode != .none && currentModifiers != previousModifiers {
                let wasMode = previousMode
                self.activeMode = .none
                self.activeModifiers = []
                
                if !self.holdTriggered && !self.isProcessingAction {
                    // Trigger tap action for the mode that was active
                    switch wasMode {
                    case .fullScreen:
                        if !fullScreenConfig.isTapAndHold {
                            self.isProcessingAction = true
                            actionToTrigger = fullScreenConfig.action
                        }
                    case .drag:
                        if !dragConfig.isTapAndHold {
                            self.isProcessingAction = true
                            actionToTrigger = dragConfig.action
                        }
                    case .region:
                        if !regionConfig.isTapAndHold {
                            self.isProcessingAction = true
                            actionToTrigger = regionConfig.action
                        }
                    case .none:
                        break
                    }
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
