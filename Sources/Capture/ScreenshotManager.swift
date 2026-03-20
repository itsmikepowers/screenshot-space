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
    private static var isRegionCaptureInProgress = false
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
        var shouldProceed = false
        captureQueue.sync {
            // Don't block if only region capture is in progress (it uses different mechanism)
            guard !isCaptureInProgress else {
                logger.debug("Capture already in progress, ignoring full screen request")
                return
            }
            isCaptureInProgress = true
            shouldProceed = true
        }
        
        guard shouldProceed else { return }
        
        logger.info("Starting full screen capture")
        let previousChangeCount = NSPasteboard.general.changeCount

        DispatchQueue.global(qos: .userInteractive).async {
            postKeyStroke(keyCode: kVK_ANSI_3, flags: [.maskCommand, .maskShift, .maskControl])
        }

        pollAndSave(
            previousChangeCount: previousChangeCount,
            attempt: 0,
            maxAttempts: 30,
            interval: 0.1,
            onComplete: { 
                captureQueue.sync { isCaptureInProgress = false }
                logger.debug("Full screen capture complete")
            }
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

    /// Capture a specific region by taking a full-screen screenshot and cropping.
    /// Uses native screencapture command so no Screen Recording permission needed.
    /// The rect is in CG coordinates (top-left origin).
    static func captureAndSaveRegion(_ rect: CGRect) {
        var shouldProceed = false
        captureQueue.sync {
            // Region capture uses its own flag - doesn't block other captures
            guard !isRegionCaptureInProgress else {
                logger.debug("Region capture already in progress, ignoring")
                return
            }
            isRegionCaptureInProgress = true
            shouldProceed = true
        }
        
        guard shouldProceed else { return }
        
        logger.info("Starting region capture")
        
        // Use screencapture command to capture full screen to a temp file (no clipboard)
        // This avoids any interference with clipboard-based polling
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("screenshot_temp_\(UUID().uuidString).png")
        
        DispatchQueue.global(qos: .userInteractive).async {
            defer {
                captureQueue.sync {
                    isRegionCaptureInProgress = false
                }
                logger.debug("Region capture complete")
            }
            
            // Capture full screen to temp file (silent, no clipboard)
            let captureProcess = Process()
            captureProcess.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            captureProcess.arguments = ["-x", tempFile.path]  // -x = silent
            
            do {
                try captureProcess.run()
                captureProcess.waitUntilExit()
                
                guard captureProcess.terminationStatus == 0,
                      FileManager.default.fileExists(atPath: tempFile.path) else {
                    logger.warning("screencapture failed or file not created")
                    return
                }
                
                // Load the full screenshot
                guard let fullImageData = try? Data(contentsOf: tempFile),
                      let fullImage = NSImage(data: fullImageData),
                      let fullCGImage = fullImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                    logger.warning("Failed to load screenshot for cropping")
                    try? FileManager.default.removeItem(at: tempFile)
                    return
                }
                
                // Clean up temp file
                try? FileManager.default.removeItem(at: tempFile)
                
                // Account for screen scale (Retina displays)
                let scale = NSScreen.main?.backingScaleFactor ?? 1.0
                let scaledRect = CGRect(
                    x: rect.origin.x * scale,
                    y: rect.origin.y * scale,
                    width: rect.width * scale,
                    height: rect.height * scale
                )
                
                // Crop the image
                guard let croppedCGImage = fullCGImage.cropping(to: scaledRect) else {
                    logger.warning("Failed to crop image to region")
                    return
                }
                
                // Convert to PNG data
                let croppedImage = NSImage(cgImage: croppedCGImage, size: NSSize(width: rect.width, height: rect.height))
                guard let tiffData = croppedImage.tiffRepresentation,
                      let bitmap = NSBitmapImageRep(data: tiffData),
                      let pngData = bitmap.representation(using: .png, properties: [:]) else {
                    logger.warning("Failed to convert cropped image to PNG")
                    return
                }
                
                // Save to file
                let fileURL = generateUniqueFileURL()
                try pngData.write(to: fileURL, options: .atomic)
                logger.info("Region screenshot saved: \(fileURL.lastPathComponent)")
                
                // Play screenshot sound
                if let soundURL = URL(string: "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system/Screen Capture.aif") {
                    NSSound(contentsOf: soundURL, byReference: true)?.play()
                }
                
                // Copy cropped image to clipboard
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setData(pngData, forType: .png)
                
                // Add to gallery
                DispatchQueue.main.async {
                    ScreenshotStore.shared.addNewScreenshot(url: fileURL)
                }
                
                // OCR processing
                DispatchQueue.global(qos: .utility).async {
                    OCRProcessor.process(url: fileURL)
                }
            } catch {
                logger.error("Failed region capture: \(error.localizedDescription)")
                try? FileManager.default.removeItem(at: tempFile)
            }
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
            
            // Instantly add to gallery
            ScreenshotStore.shared.addNewScreenshot(url: fileURL)
            
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
