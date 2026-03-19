import Cocoa

/// Presents a fullscreen overlay on each display for the user to drag-select a region.
/// Returns the selected rectangle in Core Graphics coordinates (top-left origin), or nil if cancelled.
class RegionSelector {

    /// Prevents deallocation while the overlay is active.
    private static var activeInstance: RegionSelector?

    private var windows: [NSWindow] = []
    private var completion: ((CGRect?) -> Void)?

    /// Show the overlay and call `completion` with the selected region (CG coords) or nil.
    func selectRegion(completion: @escaping (CGRect?) -> Void) {
        Self.activeInstance = self
        self.completion = completion

        for screen in NSScreen.screens {
            let window = NSWindow(
                contentRect: screen.frame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false
            )
            window.level = .screenSaver
            window.isOpaque = false
            window.backgroundColor = .clear
            window.ignoresMouseEvents = false
            window.acceptsMouseMovedEvents = true
            window.hasShadow = false

            let view = RegionSelectionView(frame: screen.frame)
            view.onComplete = { [weak self] cocoaRect in
                self?.finishWithRect(cocoaRect)
            }
            view.onCancel = { [weak self] in
                self?.finishWithRect(nil)
            }
            window.contentView = view
            window.makeKeyAndOrderFront(nil)
            windows.append(window)
        }

        // Ensure one of the windows is key so we receive keyboard events
        windows.first?.makeKey()
        NSCursor.crosshair.push()
    }

    private func finishWithRect(_ cocoaRect: NSRect?) {
        NSCursor.pop()
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()

        guard let rect = cocoaRect, rect.width >= 2, rect.height >= 2 else {
            completion?(nil)
            completion = nil
            Self.activeInstance = nil
            return
        }

        // Convert Cocoa coordinates (bottom-left origin) to CG coordinates (top-left origin)
        let primaryHeight = NSScreen.screens.first?.frame.height ?? rect.maxY
        let cgRect = CGRect(
            x: rect.origin.x,
            y: primaryHeight - rect.maxY,
            width: rect.width,
            height: rect.height
        )
        completion?(cgRect)
        completion = nil
        Self.activeInstance = nil
    }
}

// MARK: - Selection View

private class RegionSelectionView: NSView {

    var onComplete: ((NSRect) -> Void)?
    var onCancel: (() -> Void)?

    private var dragOrigin: NSPoint?
    private var currentRect: NSRect = .zero

    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        // Semi-transparent overlay
        NSColor.black.withAlphaComponent(0.3).setFill()
        bounds.fill()

        guard currentRect.width > 0, currentRect.height > 0 else { return }

        // Clear cutout for selected region
        NSColor.clear.setFill()
        currentRect.fill(using: .copy)

        // Border around selection
        NSColor.white.withAlphaComponent(0.8).setStroke()
        let border = NSBezierPath(rect: currentRect)
        border.lineWidth = 1.0
        border.stroke()

        // Dimension label
        let label = "\(Int(currentRect.width)) × \(Int(currentRect.height))"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white,
            .backgroundColor: NSColor.black.withAlphaComponent(0.6)
        ]
        let size = (label as NSString).size(withAttributes: attrs)
        let labelOrigin = NSPoint(
            x: currentRect.midX - size.width / 2,
            y: currentRect.maxY + 4
        )
        (label as NSString).draw(at: labelOrigin, withAttributes: attrs)
    }

    override func mouseDown(with event: NSEvent) {
        dragOrigin = convert(event.locationInWindow, from: nil)
        currentRect = .zero
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let origin = dragOrigin else { return }
        let current = convert(event.locationInWindow, from: nil)
        currentRect = NSRect(
            x: min(origin.x, current.x),
            y: min(origin.y, current.y),
            width: abs(current.x - origin.x),
            height: abs(current.y - origin.y)
        )
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard dragOrigin != nil else { return }
        dragOrigin = nil

        // Convert view-local rect to screen coordinates
        let screenRect = NSRect(
            x: window!.frame.origin.x + currentRect.origin.x,
            y: window!.frame.origin.y + currentRect.origin.y,
            width: currentRect.width,
            height: currentRect.height
        )
        onComplete?(screenRect)
    }

    override func keyDown(with event: NSEvent) {
        // Escape key cancels
        if event.keyCode == 53 {
            onCancel?()
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        onCancel?()
    }
}
