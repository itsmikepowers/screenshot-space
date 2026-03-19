import Cocoa

/// Monitors the Option key globally via a CGEvent tap.
/// Calls `onTap` for a quick tap and `onHold` when held past the threshold.
class EventMonitor {

    // MARK: - Configuration

    var holdThreshold: TimeInterval = 0.25
    var onTap: (() -> Void)?
    var onHold: (() -> Void)?

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

    /// Starts the event tap. Returns `true` on success, `false` if the tap
    /// could not be created (usually because Accessibility permission is missing).
    func start() -> Bool {
        guard eventTap == nil else { return true }
        
        let eventMask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: eventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        return true
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

    fileprivate func handleEvent(type: CGEventType, event: CGEvent) {
        // Re-enable the tap if macOS disabled it due to timeout
        if type == .tapDisabledByTimeout {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return
        }

        guard type == .flagsChanged else { return }

        let flags = event.flags
        let eventTime = event.timestamp
        
        // Ignore if Option is combined with other modifiers (Cmd, Ctrl, Shift)
        let otherModifiers: CGEventFlags = [.maskCommand, .maskControl, .maskShift]
        let hasOtherModifiers = !flags.intersection(otherModifiers).isEmpty
        
        let isOptionDown = flags.contains(.maskAlternate) && !hasOtherModifiers
        
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
