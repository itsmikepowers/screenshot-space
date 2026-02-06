import Foundation
import AppKit

// MARK: - Model

struct ScreenshotItem: Identifiable, Equatable {
    var id: URL { url }
    let url: URL
    let filename: String
    let date: Date
    let thumbnail: NSImage
    var extractedText: String?
    var wordCount: Int?

    var dateString: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    static func == (lhs: ScreenshotItem, rhs: ScreenshotItem) -> Bool {
        lhs.url == rhs.url
    }
}

// MARK: - Store

class ScreenshotStore: ObservableObject {
    /// Shared instance so Gallery and Search use the same store.
    static let shared = ScreenshotStore()

    @Published var screenshots: [ScreenshotItem] = []

    private let directory = ScreenshotManager.saveDirectory
    private var directoryMonitor: DispatchSourceFileSystemObject?
    private var isBackfilling = false

    init() {
        loadScreenshots()
        startWatching()
        backfillOCR()
    }

    deinit {
        directoryMonitor?.cancel()
    }

    // MARK: - Loading

    func loadScreenshots() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let fm = FileManager.default

            // Make sure the directory exists
            try? fm.createDirectory(at: self.directory, withIntermediateDirectories: true)

            guard let files = try? fm.contentsOfDirectory(
                at: self.directory,
                includingPropertiesForKeys: [.creationDateKey],
                options: [.skipsHiddenFiles]
            ) else { return }

            let items = files
                .filter { $0.pathExtension.lowercased() == "png" }
                .compactMap { url -> ScreenshotItem? in
                    guard let values = try? url.resourceValues(forKeys: [.creationDateKey]),
                          let date = values.creationDate,
                          let thumbnail = Self.loadThumbnail(from: url) else { return nil }

                    let metadata = OCRProcessor.loadMetadata(for: url)

                    return ScreenshotItem(
                        url: url,
                        filename: url.deletingPathExtension().lastPathComponent,
                        date: date,
                        thumbnail: thumbnail,
                        extractedText: metadata?.extractedText,
                        wordCount: metadata?.wordCount
                    )
                }
                .sorted { $0.date > $1.date }

            DispatchQueue.main.async {
                self.screenshots = items
            }
        }
    }

    // MARK: - Directory Watching

    private func startWatching() {
        let fd = open(directory.path, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: .write,
            queue: .main
        )

        source.setEventHandler { [weak self] in
            guard let self = self, !self.isBackfilling else { return }
            self.loadScreenshots()
        }

        source.setCancelHandler {
            close(fd)
        }

        source.resume()
        directoryMonitor = source
    }

    // MARK: - OCR Backfill

    /// Process existing screenshots that don't have a JSON sidecar yet,
    /// one at a time so we don't flood the CPU.
    private func backfillOCR() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }

            DispatchQueue.main.async { self.isBackfilling = true }

            let fm = FileManager.default
            guard let files = try? fm.contentsOfDirectory(
                at: self.directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else {
                DispatchQueue.main.async { self.isBackfilling = false }
                return
            }

            let unprocessed = files
                .filter { $0.pathExtension.lowercased() == "png" }
                .filter { !OCRProcessor.hasSidecar(for: $0) }

            // Process serially — one at a time
            for png in unprocessed {
                OCRProcessor.processSync(url: png)
            }

            DispatchQueue.main.async {
                self.isBackfilling = false
                self.loadScreenshots()
            }
        }
    }

    // MARK: - Single-Item Actions

    func deleteScreenshot(_ item: ScreenshotItem) {
        try? FileManager.default.removeItem(at: item.url)
        // Also remove the JSON sidecar
        let sidecar = OCRProcessor.sidecarURL(for: item.url)
        try? FileManager.default.removeItem(at: sidecar)
        screenshots.removeAll { $0.url == item.url }
    }

    func copyToClipboard(_ item: ScreenshotItem) {
        guard let image = NSImage(contentsOf: item.url) else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
    }

    func revealInFinder(_ item: ScreenshotItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    // MARK: - Bulk Actions

    func deleteScreenshots(_ items: Set<URL>) {
        for url in items {
            try? FileManager.default.removeItem(at: url)
            let sidecar = OCRProcessor.sidecarURL(for: url)
            try? FileManager.default.removeItem(at: sidecar)
        }
        screenshots.removeAll { items.contains($0.url) }
    }

    func copyToClipboard(_ items: Set<URL>) {
        let images: [NSImage] = screenshots
            .filter { items.contains($0.url) }
            .sorted { $0.date > $1.date }
            .compactMap { NSImage(contentsOf: $0.url) }
        guard !images.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects(images)
    }

    func revealInFinder(_ items: Set<URL>) {
        let urls = screenshots
            .filter { items.contains($0.url) }
            .map { $0.url }
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    // MARK: - Thumbnail Generation

    private static func loadThumbnail(from url: URL, maxSize: CGFloat = 400) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }

        let options: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize: maxSize,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
}
