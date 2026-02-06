import Foundation
import AppKit

/// Triggers native macOS screenshot shortcuts via CGEvent (no Screen Recording needed).
/// Screenshots go to the clipboard via the system shortcut, then we also save a copy
/// to the local screenshots folder.
enum ScreenshotManager {

    /// Directory where screenshots are stored.
    static var saveDirectory: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Pictures")
            .appendingPathComponent("ScreenshotSpace")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    // Key codes for the number keys
    private static let kVK_ANSI_3: CGKeyCode = 0x14
    private static let kVK_ANSI_4: CGKeyCode = 0x15

    // MARK: - Public API

    /// Full-screen screenshot to clipboard (Cmd+Shift+Ctrl+3), then save to folder.
    static func captureFullScreen() {
        let previousChangeCount = NSPasteboard.general.changeCount

        // Post on a background thread to avoid blocking the main run loop
        DispatchQueue.global(qos: .userInteractive).async {
            postKeyStroke(keyCode: kVK_ANSI_3, flags: [.maskCommand, .maskShift, .maskControl])
        }

        // Check clipboard after a short delay and save
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            saveClipboardImage(previousChangeCount: previousChangeCount)
        }
    }

    /// Interactive drag-to-select to clipboard (Cmd+Shift+Ctrl+4), then save to folder.
    static func captureSelection() {
        let previousChangeCount = NSPasteboard.general.changeCount

        // Post on a background thread to avoid blocking the main run loop
        DispatchQueue.global(qos: .userInteractive).async {
            postKeyStroke(keyCode: kVK_ANSI_4, flags: [.maskCommand, .maskShift, .maskControl])
        }

        // User needs time to drag-select — poll clipboard until it changes (up to 30s)
        pollAndSave(previousChangeCount: previousChangeCount, attempt: 0)
    }

    /// Open the screenshot folder in Finder.
    static func revealInFinder() {
        NSWorkspace.shared.open(saveDirectory)
    }

    // MARK: - Key Event Posting

    /// Posts a synthetic key stroke to the HID event tap (where the system screenshot
    /// handler listens). Uses a private event source so the physical Option key
    /// (still held down) does not contaminate the modifiers.
    private static func postKeyStroke(keyCode: CGKeyCode, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .privateState)

        // Key Down
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true) else { return }
        keyDown.flags = flags
        keyDown.post(tap: .cghidEventTap)

        // Brief pause to mimic a real keystroke
        usleep(80_000) // 80ms

        // Key Up
        guard let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else { return }
        keyUp.flags = flags
        keyUp.post(tap: .cghidEventTap)
    }

    // MARK: - Clipboard Monitoring & File Saving

    private static func pollAndSave(previousChangeCount: Int, attempt: Int) {
        guard attempt < 60 else { return } // stop after 30 seconds

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if NSPasteboard.general.changeCount != previousChangeCount {
                saveClipboardImage(previousChangeCount: previousChangeCount)
            } else {
                pollAndSave(previousChangeCount: previousChangeCount, attempt: attempt + 1)
            }
        }
    }

    private static func saveClipboardImage(previousChangeCount: Int) {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != previousChangeCount else { return }

        // Try to get image data from the clipboard
        var pngData: Data?

        if let data = pasteboard.data(forType: .png) {
            pngData = data
        } else if let data = pasteboard.data(forType: .tiff),
                  let rep = NSBitmapImageRep(data: data),
                  let converted = rep.representation(using: .png, properties: [:]) {
            pngData = converted
        }

        guard let data = pngData else { return }

        let filePath = generateFilePath()
        let fileURL = URL(fileURLWithPath: filePath)
        try? data.write(to: fileURL)

        // Run OCR on the new screenshot in the background
        OCRProcessor.process(url: fileURL)
    }

    private static func generateFilePath() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' h.mm.ss a"
        let timestamp = formatter.string(from: Date())
        let filename = "Screenshot \(timestamp).png"
        return saveDirectory.appendingPathComponent(filename).path
    }
}
