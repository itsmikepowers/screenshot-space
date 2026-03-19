import Foundation
import AppKit
import os.log

/// Triggers native macOS screenshot shortcuts via CGEvent (no Screen Recording needed).
/// Screenshots go to the clipboard via the system shortcut, then we also save a copy
/// to the local screenshots folder.
enum ScreenshotManager {
    
    private static let logger = Logger(subsystem: "com.screenshotspace", category: "ScreenshotManager")
    
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' h.mm.ss a"
        return formatter
    }()
    
    private static var isCaptureInProgress = false
    private static let captureQueue = DispatchQueue(label: "com.screenshotspace.capture")

    /// Default screenshot directory path.
    static let defaultDirectoryPath: String = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Pictures")
            .appendingPathComponent("ScreenshotSpace")
            .path
    }()

    /// Directory where screenshots are stored.
    static var saveDirectory: URL = {
        let path = UserDefaults.standard.string(forKey: "screenshotDirectory") ?? defaultDirectoryPath
        let dir = URL(fileURLWithPath: path)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// Update the save directory at runtime and ensure it exists.
    static func updateSaveDirectory(to path: String) {
        let url = URL(fileURLWithPath: path)
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        } catch {
            logger.error("Failed to create screenshot directory: \(error.localizedDescription)")
        }
        saveDirectory = url
    }

    // Key codes for the number keys
    private static let kVK_ANSI_3: CGKeyCode = 0x14
    private static let kVK_ANSI_4: CGKeyCode = 0x15

    // MARK: - Public API

    /// Full-screen screenshot to clipboard (Cmd+Shift+Ctrl+3), then save to folder.
    static func captureFullScreen() {
        captureQueue.sync {
            guard !isCaptureInProgress else {
                logger.debug("Capture already in progress, ignoring request")
                return
            }
            isCaptureInProgress = true
        }
        
        let previousChangeCount = NSPasteboard.general.changeCount

        DispatchQueue.global(qos: .userInteractive).async {
            postKeyStroke(keyCode: kVK_ANSI_3, flags: [.maskCommand, .maskShift, .maskControl])
        }

        pollAndSave(
            previousChangeCount: previousChangeCount,
            attempt: 0,
            maxAttempts: 30,
            interval: 0.1,
            onComplete: { captureQueue.sync { isCaptureInProgress = false } }
        )
    }

    /// Interactive drag-to-select to clipboard (Cmd+Shift+Ctrl+4), then save to folder.
    static func captureSelection() {
        captureQueue.sync {
            guard !isCaptureInProgress else {
                logger.debug("Capture already in progress, ignoring request")
                return
            }
            isCaptureInProgress = true
        }
        
        let previousChangeCount = NSPasteboard.general.changeCount

        DispatchQueue.global(qos: .userInteractive).async {
            postKeyStroke(keyCode: kVK_ANSI_4, flags: [.maskCommand, .maskShift, .maskControl])
        }

        pollAndSave(
            previousChangeCount: previousChangeCount,
            attempt: 0,
            maxAttempts: 60,
            interval: 0.5,
            onComplete: { captureQueue.sync { isCaptureInProgress = false } }
        )
    }

    /// Capture a specific screen region via CGWindowListCreateImage. Returns PNG data.
    /// Requires Screen Recording permission.
    static func captureRegion(_ rect: CGRect) -> Data? {
        guard let cgImage = CGWindowListCreateImage(
            rect,
            .optionOnScreenOnly,
            kCGNullWindowID,
            .bestResolution
        ) else {
            logger.warning("CGWindowListCreateImage returned nil")
            return nil
        }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        return rep.representation(using: .png, properties: [:])
    }

    /// Capture a specific region, save to disk, copy to clipboard, and trigger OCR.
    static func captureAndSaveRegion(_ rect: CGRect) {
        captureQueue.sync {
            guard !isCaptureInProgress else {
                logger.debug("Capture already in progress, ignoring region recapture")
                return
            }
            isCaptureInProgress = true
        }

        defer { captureQueue.sync { isCaptureInProgress = false } }

        guard let data = captureRegion(rect) else {
            logger.warning("Region capture failed — Screen Recording permission may be missing")
            return
        }

        let fileURL = generateUniqueFileURL()

        do {
            try data.write(to: fileURL, options: .atomic)
            logger.info("Region screenshot saved: \(fileURL.lastPathComponent)")

            // Copy to clipboard
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setData(data, forType: .png)

            DispatchQueue.global(qos: .utility).async {
                OCRProcessor.process(url: fileURL)
            }
        } catch {
            logger.error("Failed to save region screenshot: \(error.localizedDescription)")
        }
    }

    /// Check whether a CG-coordinate rect is visible on any connected screen.
    static func isRegionOnScreen(_ rect: CGRect) -> Bool {
        guard let primaryHeight = NSScreen.screens.first?.frame.height else { return false }
        for screen in NSScreen.screens {
            // Convert Cocoa screen frame to CG coordinates (flip Y)
            let cgScreenRect = CGRect(
                x: screen.frame.origin.x,
                y: primaryHeight - screen.frame.maxY,
                width: screen.frame.width,
                height: screen.frame.height
            )
            if cgScreenRect.intersects(rect) {
                return true
            }
        }
        return false
    }

    /// Open the screenshot folder in Finder.
    static func revealInFinder() {
        NSWorkspace.shared.open(saveDirectory)
    }

    // MARK: - Key Event Posting

    private static func postKeyStroke(keyCode: CGKeyCode, flags: CGEventFlags) {
        guard let source = CGEventSource(stateID: .privateState) else {
            logger.error("Failed to create CGEventSource")
            return
        }

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true) else {
            logger.error("Failed to create keyDown event")
            return
        }
        keyDown.flags = flags
        keyDown.post(tap: .cghidEventTap)

        usleep(10_000)

        guard let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            logger.error("Failed to create keyUp event")
            return
        }
        keyUp.flags = flags
        keyUp.post(tap: .cghidEventTap)
    }

    // MARK: - Clipboard Monitoring & File Saving

    private static func pollAndSave(
        previousChangeCount: Int,
        attempt: Int,
        maxAttempts: Int,
        interval: TimeInterval,
        onComplete: @escaping () -> Void
    ) {
        guard attempt < maxAttempts else {
            logger.debug("Polling timed out after \(maxAttempts) attempts")
            onComplete()
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + interval) {
            if NSPasteboard.general.changeCount != previousChangeCount {
                saveClipboardImage(previousChangeCount: previousChangeCount)
                onComplete()
            } else {
                pollAndSave(
                    previousChangeCount: previousChangeCount,
                    attempt: attempt + 1,
                    maxAttempts: maxAttempts,
                    interval: interval,
                    onComplete: onComplete
                )
            }
        }
    }

    private static func saveClipboardImage(previousChangeCount: Int) {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != previousChangeCount else { return }

        var pngData: Data?

        if let data = pasteboard.data(forType: .png) {
            pngData = data
        } else if let data = pasteboard.data(forType: .tiff) {
            autoreleasepool {
                if let rep = NSBitmapImageRep(data: data),
                   let converted = rep.representation(using: .png, properties: [:]) {
                    pngData = converted
                }
            }
        }

        guard let data = pngData else {
            logger.warning("No image data found in clipboard")
            return
        }

        let fileURL = generateUniqueFileURL()
        
        do {
            try data.write(to: fileURL, options: .atomic)
            logger.info("Screenshot saved: \(fileURL.lastPathComponent)")
            
            DispatchQueue.global(qos: .utility).async {
                OCRProcessor.process(url: fileURL)
            }
        } catch {
            logger.error("Failed to save screenshot: \(error.localizedDescription)")
        }
    }

    private static func generateUniqueFileURL() -> URL {
        let timestamp = dateFormatter.string(from: Date())
        let baseFilename = "Screenshot \(timestamp)"
        var fileURL = saveDirectory.appendingPathComponent("\(baseFilename).png")
        
        var counter = 1
        let fm = FileManager.default
        while fm.fileExists(atPath: fileURL.path) {
            fileURL = saveDirectory.appendingPathComponent("\(baseFilename) (\(counter)).png")
            counter += 1
            if counter > 100 {
                logger.error("Too many filename collisions")
                break
            }
        }
        
        return fileURL
    }
}
