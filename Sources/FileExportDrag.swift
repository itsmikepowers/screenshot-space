import AppKit
import SwiftUI

// MARK: - Multi-file export drag (AppKit)

/// Drag one or many existing files to Finder, browsers, etc. as **copy**.
///
/// SwiftUI’s `onDrag` + `NSItemProvider` only exposes **one** file when multiple
/// `registerFileRepresentation` callbacks are used. `NSDraggingSession` with one
/// `NSDraggingItem` per URL is required for multi-file drags.
///
/// This view sits above SwiftUI content, so **single clicks** must be forwarded via
/// `onLeftClick` (synthetic `sendEvent` / `hit.mouseDown` does not reach SwiftUI gestures reliably).
struct FileDragExportHost: NSViewRepresentable {
    let urls: [URL]
    /// Called when the user releases the left button without starting a file drag (use for select / double-click open).
    var onLeftClick: ((NSEvent) -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(urls: urls)
    }

    func makeNSView(context: Context) -> FileDragExportHostView {
        let v = FileDragExportHostView()
        v.coordinator = context.coordinator
        return v
    }

    func updateNSView(_ nsView: FileDragExportHostView, context: Context) {
        context.coordinator.urls = urls
        nsView.coordinator = context.coordinator
        nsView.onLeftClick = onLeftClick
    }

    final class Coordinator: NSObject, NSDraggingSource {
        var urls: [URL]

        init(urls: [URL]) {
            self.urls = urls
        }

        func draggingSession(
            _ session: NSDraggingSession,
            sourceOperationMaskFor context: NSDraggingContext
        ) -> NSDragOperation {
            .copy
        }
    }
}

final class FileDragExportHostView: NSView {
    weak var coordinator: FileDragExportHost.Coordinator?

    /// Invoked from `mouseUp` when the gesture was a click, not a file drag.
    var onLeftClick: ((NSEvent) -> Void)?

    private var mouseDownLocation: NSPoint?
    private var beganFileDrag = false

    override var isOpaque: Bool { false }
    
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    
    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {}
    
    override func hitTest(_ point: NSPoint) -> NSView? {
        return frame.contains(point) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownLocation = event.locationInWindow
        beganFileDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard !beganFileDrag, let start = mouseDownLocation else { return }
        let p = event.locationInWindow
        let dx = p.x - start.x
        let dy = p.y - start.y
        guard (dx * dx + dy * dy) > 36 else { return }

        let urls = coordinator?.urls.filter { FileManager.default.isReadableFile(atPath: $0.path) } ?? []
        guard !urls.isEmpty, let coordinator else { return }
        beganFileDrag = true

        let items: [NSDraggingItem] = urls.map { url in
            let item = NSDraggingItem(pasteboardWriter: url as NSURL)
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            let size = NSSize(width: 32, height: 32)
            item.setDraggingFrame(NSRect(origin: .zero, size: size), contents: icon)
            return item
        }

        beginDraggingSession(with: items, event: event, source: coordinator)
    }

    override func mouseUp(with event: NSEvent) {
        let forwardTap = !beganFileDrag && mouseDownLocation != nil
        defer {
            mouseDownLocation = nil
            beganFileDrag = false
        }
        guard forwardTap else { return }

        if let onLeftClick {
            onLeftClick(event)
            return
        }

        // Preview image (no tap handler): redispatch for any SwiftUI hit-testing needs.
        guard let window = window else { return }
        isHidden = true
        layoutSubtreeIfNeeded()
        window.contentView?.layoutSubtreeIfNeeded()
        defer { isHidden = false }

        guard let down = NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: event.locationInWindow,
            modifierFlags: event.modifierFlags,
            timestamp: event.timestamp,
            windowNumber: event.windowNumber,
            context: nil,
            eventNumber: event.eventNumber,
            clickCount: event.clickCount,
            pressure: event.pressure
        ) else { return }

        window.sendEvent(down)
        window.sendEvent(event)
    }

    override func rightMouseDown(with event: NSEvent) {
        isHidden = true
        layoutSubtreeIfNeeded()
        window?.contentView?.layoutSubtreeIfNeeded()
        defer { isHidden = false }
        window?.sendEvent(event)
    }
}
