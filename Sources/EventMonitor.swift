import Cocoa

/// Monitors the Option key globally via a CGEvent tap.
/// Calls `onTap` for a quick tap and `onHold` when held past the threshold.
class EventMonitor {

    enum StartResult: Equatable {
        case started
        case alreadyRunning
        case permissionDenied
        case failedToCreateTap
    }

    // MARK: - Configuration

    var holdThreshold: TimeInterval = 0.25
    var triggerModifiers: CGEventFlags = [.maskAlternate]
    var onTap: (() -> Void)?
    var onHold: (() -> Void)?
    var onTapDisabled: (() -> Void)?

    // MARK: - Internal State

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var holdTimer: DispatchSourceTimer?
    private var optionDown = false
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
            optionDown = false
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
        stateQueue.sync {
            guard optionDown, !holdTriggered, !isProcessingAction else { return }
            holdTriggered = true
            isProcessingAction = true
        }
        
        onHold?()
        
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

        // Check if exactly the configured modifier combination is pressed
        let allModifiers: CGEventFlags = [.maskCommand, .maskControl, .maskShift, .maskAlternate]
        let activeModifiers = flags.intersection(allModifiers)
        let isOptionDown = activeModifiers == triggerModifiers
        
        // Debounce rapid events (within 10ms)
        if eventTime > 0 && lastEventTime > 0 {
            let timeDelta = Double(eventTime - lastEventTime) / 1_000_000_000.0
            if timeDelta < 0.010 {
                return
            }
        }
        lastEventTime = eventTime

        var shouldTriggerTap = false
        var shouldStartTimer = false
        let threshold = holdThreshold
        
        stateQueue.sync {
            // ── Option key DOWN ──
            if isOptionDown && !self.optionDown {
                self.optionDown = true
                self.holdTriggered = false
                shouldStartTimer = true
            }

            // ── Option key UP ──
            if !isOptionDown && self.optionDown {
                self.optionDown = false
                
                if !self.holdTriggered && !self.isProcessingAction {
                    shouldTriggerTap = true
                    self.isProcessingAction = true
                }
            }
        }
        
        if shouldStartTimer {
            DispatchQueue.main.async { [weak self] in
                self?.scheduleHoldTimer(threshold: threshold)
            }
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.cancelHoldTimer()
            }
        }
        
        if shouldTriggerTap {
            DispatchQueue.main.async { [weak self] in
                self?.onTap?()
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
