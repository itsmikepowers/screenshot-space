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
    private var holdTimer: Timer?
    private var optionDown = false
    private var holdTriggered = false

    // MARK: - Start / Stop

    /// Starts the event tap. Returns `true` on success, `false` if the tap
    /// could not be created (usually because Accessibility permission is missing).
    func start() -> Bool {
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
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        holdTimer?.invalidate()
        holdTimer = nil
    }

    deinit {
        stop()
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
        let isOptionDown = flags.contains(.maskAlternate)

        // ── Option key DOWN ──
        if isOptionDown && !optionDown {
            optionDown = true
            holdTriggered = false

            let threshold = holdThreshold
            holdTimer = Timer.scheduledTimer(withTimeInterval: threshold, repeats: false) { [weak self] _ in
                guard let self = self else { return }
                self.holdTriggered = true
                self.onHold?()
            }
        }

        // ── Option key UP ──
        if !isOptionDown && optionDown {
            optionDown = false
            holdTimer?.invalidate()
            holdTimer = nil

            if !holdTriggered {
                onTap?()
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
