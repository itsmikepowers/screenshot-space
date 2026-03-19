import Foundation
import AppKit
import os.log

// MARK: - Model

struct ScreenshotItem: Identifiable, Equatable {
    var id: URL { url }
    let url: URL
    let filename: String
    let date: Date
    let thumbnail: NSImage
    var extractedText: String?
    var wordCount: Int?

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    var dateString: String {
        Self.dateFormatter.string(from: date)
    }

    static func == (lhs: ScreenshotItem, rhs: ScreenshotItem) -> Bool {
        lhs.url == rhs.url
    }
}

// MARK: - Store

class ScreenshotStore: ObservableObject {
    /// Shared instance so Gallery and Search use the same store.
    static let shared = ScreenshotStore()
    
    private static let logger = Logger(subsystem: "com.screenshotspace", category: "ScreenshotStore")

    @Published var screenshots: [ScreenshotItem] = []
    @Published var isLoading = false

    private let directory = ScreenshotManager.saveDirectory
    private var directoryMonitor: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1
    private var isBackfilling = false
    private var pendingReload: DispatchWorkItem?
    private let reloadDebounceInterval: TimeInterval = 0.3

    init() {
        loadScreenshots()
        startWatching()
        backfillOCR()
    }

    deinit {
        stopWatching()
    }
    
    private func stopWatching() {
        directoryMonitor?.cancel()
        directoryMonitor = nil
        if fileDescriptor >= 0 {
            close(fileDescriptor)
            fileDescriptor = -1
        }
    }

    // MARK: - Loading

    func loadScreenshots() {
        DispatchQueue.main.async { [weak self] in
            self?.isLoading = true
        }
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let fm = FileManager.default

            do {
                try fm.createDirectory(at: self.directory, withIntermediateDirectories: true)
            } catch {
                Self.logger.error("Failed to create directory: \(error.localizedDescription)")
            }

            let files: [URL]
            do {
                files = try fm.contentsOfDirectory(
                    at: self.directory,
                    includingPropertiesForKeys: [.creationDateKey, .fileSizeKey],
                    options: [.skipsHiddenFiles]
                )
            } catch {
                Self.logger.error("Failed to list directory: \(error.localizedDescription)")
                DispatchQueue.main.async { self.isLoading = false }
                return
            }

            let items: [ScreenshotItem] = files
                .filter { $0.pathExtension.lowercased() == "png" }
                .compactMap { url -> ScreenshotItem? in
                    autoreleasepool {
                        guard let values = try? url.resourceValues(forKeys: [.creationDateKey, .fileSizeKey]),
                              let date = values.creationDate else {
                            Self.logger.debug("Skipping file without creation date: \(url.lastPathComponent)")
                            return nil
                        }
                        
                        if let size = values.fileSize, size == 0 {
                            Self.logger.debug("Skipping empty file: \(url.lastPathComponent)")
                            return nil
                        }
                        
                        guard let thumbnail = Self.loadThumbnail(from: url) else {
                            Self.logger.debug("Failed to load thumbnail: \(url.lastPathComponent)")
                            return nil
                        }

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
                }
                .sorted { $0.date > $1.date }

            DispatchQueue.main.async {
                self.screenshots = items
                self.isLoading = false
            }
        }
    }

    // MARK: - Directory Watching

    private func startWatching() {
        let fd = open(directory.path, O_EVTONLY)
        guard fd >= 0 else {
            Self.logger.error("Failed to open directory for watching")
            return
        }
        fileDescriptor = fd

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename],
            queue: .main
        )

        source.setEventHandler { [weak self] in
            self?.scheduleReload()
        }

        source.setCancelHandler { [weak self] in
            if let fd = self?.fileDescriptor, fd >= 0 {
                close(fd)
                self?.fileDescriptor = -1
            }
        }

        source.resume()
        directoryMonitor = source
    }
    
    private func scheduleReload() {
        guard !isBackfilling else { return }
        
        pendingReload?.cancel()
        
        let workItem = DispatchWorkItem { [weak self] in
            self?.loadScreenshots()
        }
        pendingReload = workItem
        
        DispatchQueue.main.asyncAfter(deadline: .now() + reloadDebounceInterval, execute: workItem)
    }

    // MARK: - OCR Backfill

    private func backfillOCR() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }

            DispatchQueue.main.async { self.isBackfilling = true }

            let fm = FileManager.default
            let files: [URL]
            do {
                files = try fm.contentsOfDirectory(
                    at: self.directory,
                    includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles]
                )
            } catch {
                Self.logger.error("Failed to list directory for OCR backfill: \(error.localizedDescription)")
                DispatchQueue.main.async { self.isBackfilling = false }
                return
            }

            let unprocessed = files
                .filter { $0.pathExtension.lowercased() == "png" }
                .filter { !OCRProcessor.hasSidecar(for: $0) }
            
            Self.logger.info("OCR backfill: \(unprocessed.count) files to process")

            for (index, png) in unprocessed.enumerated() {
                autoreleasepool {
                    OCRProcessor.processSync(url: png)
                }
                
                if index > 0 && index % 10 == 0 {
                    Self.logger.debug("OCR backfill progress: \(index)/\(unprocessed.count)")
                }
            }

            DispatchQueue.main.async {
                self.isBackfilling = false
                self.loadScreenshots()
            }
        }
    }

    // MARK: - Single-Item Actions

    func deleteScreenshot(_ item: ScreenshotItem) {
        let fm = FileManager.default
        do {
            try fm.removeItem(at: item.url)
            let sidecar = OCRProcessor.sidecarURL(for: item.url)
            try? fm.removeItem(at: sidecar)
            screenshots.removeAll { $0.url == item.url }
        } catch {
            Self.logger.error("Failed to delete screenshot: \(error.localizedDescription)")
        }
    }

    func copyToClipboard(_ item: ScreenshotItem) {
        autoreleasepool {
            guard let image = NSImage(contentsOf: item.url) else {
                Self.logger.warning("Failed to load image for clipboard: \(item.url.lastPathComponent)")
                return
            }
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.writeObjects([image])
        }
    }

    func revealInFinder(_ item: ScreenshotItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    // MARK: - Bulk Actions

    func deleteScreenshots(_ items: Set<URL>) {
        let fm = FileManager.default
        var deletedURLs = Set<URL>()
        
        for url in items {
            do {
                try fm.removeItem(at: url)
                let sidecar = OCRProcessor.sidecarURL(for: url)
                try? fm.removeItem(at: sidecar)
                deletedURLs.insert(url)
            } catch {
                Self.logger.error("Failed to delete: \(url.lastPathComponent) - \(error.localizedDescription)")
            }
        }
        
        screenshots.removeAll { deletedURLs.contains($0.url) }
    }

    func copyToClipboard(_ items: Set<URL>) {
        autoreleasepool {
            let images: [NSImage] = screenshots
                .filter { items.contains($0.url) }
                .sorted { $0.date > $1.date }
                .compactMap { NSImage(contentsOf: $0.url) }
            guard !images.isEmpty else { return }
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.writeObjects(images)
        }
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
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCache: false
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
}
