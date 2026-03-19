import AppKit
import os.log
import SwiftUI

private let logger = Logger(subsystem: "com.screenshotspace", category: "PreviewWindow")

/// Opens `ScreenshotPreviewView` in a standalone window (not a sheet).
enum ScreenshotPreviewWindowPresenter {
    /// Strong retention until window closes — otherwise nothing keeps the delegate + window pair alive.
    private static var hosts: [ObjectIdentifier: PreviewWindowHost] = [:]
    private static let lock = NSLock()

    fileprivate static func releaseHost(_ host: PreviewWindowHost) {
        lock.lock()
        defer { lock.unlock() }
        logger.debug("Releasing host: \(ObjectIdentifier(host).debugDescription)")
        hosts.removeValue(forKey: ObjectIdentifier(host))
        logger.debug("Hosts remaining: \(hosts.count)")
    }

    static func present(item: ScreenshotItem, store: ScreenshotStore) {
        logger.debug("Presenting preview for: \(item.filename)")
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = item.filename
        window.center()
        window.setFrameAutosaveName("ScreenshotPreviewWindow")
        
        // CRITICAL: Set to false so WE control the window lifecycle, not AppKit.
        // When true, AppKit releases the window during close which races with our
        // SwiftUI contentView deallocation and causes EXC_BAD_ACCESS.
        window.isReleasedWhenClosed = false
        
        // Disable close animation to avoid Core Animation races during deallocation
        window.animationBehavior = .none

        let host = PreviewWindowHost(window: window)
        logger.debug("Created host: \(ObjectIdentifier(host).debugDescription)")

        lock.lock()
        hosts[ObjectIdentifier(host)] = host
        lock.unlock()

        let rootView = ScreenshotPreviewView(
            item: item,
            store: store,
            onClose: { }  // No-op: user closes via window X button only
        )
        window.contentView = NSHostingView(rootView: rootView)
        window.delegate = host

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        logger.debug("Preview window presented")
    }
}

/// Owns a strong ref to the window and acts as its delegate.
private final class PreviewWindowHost: NSObject, NSWindowDelegate {
    private var window: NSWindow?

    init(window: NSWindow) {
        self.window = window
        super.init()
        logger.debug("PreviewWindowHost.init")
    }

    deinit {
        logger.debug("PreviewWindowHost.deinit")
    }
    
    // MARK: - NSWindowDelegate
    
    func windowWillClose(_ notification: Notification) {
        logger.debug("windowWillClose called")
        
        guard let window = self.window else {
            logger.warning("windowWillClose: window already nil")
            return
        }
        
        // Clear contentView BEFORE the window fully closes to ensure SwiftUI
        // views are deallocated in a controlled manner, not during window dealloc.
        // This prevents the race condition where NSHostingView's ivar_destroyer
        // runs while the window is being released.
        logger.debug("Clearing contentView")
        window.contentView = nil
        
        // Clear our reference
        self.window = nil
        
        // Schedule host release for next run loop to ensure all cleanup is done
        DispatchQueue.main.async { [self] in
            logger.debug("Releasing host from main queue")
            ScreenshotPreviewWindowPresenter.releaseHost(self)
        }
    }
}
