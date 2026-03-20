import Foundation
import AppKit
import os.log

// MARK: - Notifications

extension Notification.Name {
    static let screenshotOCRCompleted = Notification.Name("screenshotOCRCompleted")
}

// MARK: - Model

struct ScreenshotItem: Identifiable, Equatable {
    var id: URL { url }
    let url: URL
    let filename: String
    let date: Date
    let thumbnail: NSImage
    var extractedText: String?
    var wordCount: Int?
    var isProcessingOCR: Bool

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
    /// True while a directory scan / thumbnail pass is in flight. Starts true so the gallery does not flash “empty” on cold launch.
    @Published var isLoading = true

    private var directory: URL { ScreenshotManager.saveDirectory }
    private var directoryMonitor: DispatchSourceFileSystemObject?
    private var isBackfilling = false
    private var pendingReload: DispatchWorkItem?
    private let reloadDebounceInterval: TimeInterval = 0.3
    private var isFirstLoad = true

    init() {
        loadScreenshots(streaming: true)
        startWatching()
        backfillOCR()
        observeOCRCompletion()
    }
    
    private func observeOCRCompletion() {
        NotificationCenter.default.addObserver(
            forName: .screenshotOCRCompleted,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self,
                  let url = notification.userInfo?["url"] as? URL else { return }
            self.updateItemAfterOCR(url: url)
        }
    }
    
    private func updateItemAfterOCR(url: URL) {
        guard let index = screenshots.firstIndex(where: { $0.url == url }) else { return }
        
        let metadata = OCRProcessor.loadMetadata(for: url)
        screenshots[index].extractedText = metadata?.extractedText
        screenshots[index].wordCount = metadata?.wordCount
        screenshots[index].isProcessingOCR = false
        
        Self.logger.debug("Updated OCR for: \(url.lastPathComponent)")
    }

    deinit {
        stopWatching()
    }

    /// Re-initialize for a new screenshot directory.
    func reloadForNewDirectory() {
        stopWatching()
        loadScreenshots(streaming: false)
        startWatching()
        backfillOCR()
    }
    
    private func stopWatching() {
        directoryMonitor?.cancel()
        directoryMonitor = nil
        // Don't close fd here — the cancel handler owns it.
    }

    // MARK: - Loading

    /// Load screenshots from the directory.
    /// - Parameter streaming: If true, streams items to UI in batches (for first load). If false, loads all at once.
    func loadScreenshots(streaming: Bool = false) {
        let shouldStream = streaming && isFirstLoad
        
        DispatchQueue.main.async { [weak self] in
            self?.isLoading = true
            if shouldStream {
                self?.screenshots = []
            }
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

            // Get file info and sort by date (newest first) BEFORE loading thumbnails
            let sortedFiles: [(url: URL, date: Date)] = files
                .filter { $0.pathExtension.lowercased() == "png" }
                .compactMap { url -> (URL, Date)? in
                    guard let values = try? url.resourceValues(forKeys: [.creationDateKey, .fileSizeKey]),
                          let date = values.creationDate else {
                        return nil
                    }
                    if let size = values.fileSize, size == 0 {
                        return nil
                    }
                    return (url, date)
                }
                .sorted { $0.1 > $1.1 }
            
            Self.logger.debug("Found \(sortedFiles.count) screenshots to load (streaming: \(shouldStream))")
            
            if shouldStream {
                // Stream items to UI in batches for first load
                let batchSize = 12
                var batch: [ScreenshotItem] = []
                batch.reserveCapacity(batchSize)
                
                for (index, file) in sortedFiles.enumerated() {
                    autoreleasepool {
                        guard let thumbnail = Self.loadThumbnail(from: file.url) else {
                            Self.logger.debug("Failed to load thumbnail: \(file.url.lastPathComponent)")
                            return
                        }
                        
                        let metadata = OCRProcessor.loadMetadata(for: file.url)
                        
                        let item = ScreenshotItem(
                            url: file.url,
                            filename: file.url.deletingPathExtension().lastPathComponent,
                            date: file.date,
                            thumbnail: thumbnail,
                            extractedText: metadata?.extractedText,
                            wordCount: metadata?.wordCount,
                            isProcessingOCR: metadata == nil
                        )
                        batch.append(item)
                    }
                    
                    // Publish batch when full or at end
                    let isLastItem = index == sortedFiles.count - 1
                    if batch.count >= batchSize || isLastItem {
                        let itemsToPublish = batch
                        batch = []
                        batch.reserveCapacity(batchSize)
                        
                        DispatchQueue.main.async { [weak self] in
                            self?.screenshots.append(contentsOf: itemsToPublish)
                        }
                    }
                }
                
                DispatchQueue.main.async { [weak self] in
                    self?.isFirstLoad = false
                    self?.isLoading = false
                    Self.logger.debug("Finished streaming all screenshots")
                }
            } else {
                // Load all at once for subsequent reloads
                let items: [ScreenshotItem] = sortedFiles.compactMap { file in
                    autoreleasepool {
                        guard let thumbnail = Self.loadThumbnail(from: file.url) else {
                            return nil
                        }
                        let metadata = OCRProcessor.loadMetadata(for: file.url)
                        return ScreenshotItem(
                            url: file.url,
                            filename: file.url.deletingPathExtension().lastPathComponent,
                            date: file.date,
                            thumbnail: thumbnail,
                            extractedText: metadata?.extractedText,
                            wordCount: metadata?.wordCount,
                            isProcessingOCR: metadata == nil
                        )
                    }
                }
                
                DispatchQueue.main.async { [weak self] in
                    self?.screenshots = items
                    self?.isLoading = false
                    Self.logger.debug("Finished loading all screenshots")
                }
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
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename],
            queue: .main
        )

        source.setEventHandler { [weak self] in
            self?.scheduleReload()
        }

        source.setCancelHandler {
            close(fd)
        }

        source.resume()
        directoryMonitor = source
    }
    
    private func scheduleReload() {
        guard !isBackfilling else { return }
        
        pendingReload?.cancel()
        
        let workItem = DispatchWorkItem { [weak self] in
            self?.loadScreenshots(streaming: false)
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
                self.loadScreenshots(streaming: false)
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

    func renameScreenshot(_ item: ScreenshotItem, to newName: String) -> Bool {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != item.filename else { return false }

        let fm = FileManager.default
        let directory = item.url.deletingLastPathComponent()
        let newURL = directory.appendingPathComponent(trimmed + ".png")

        guard !fm.fileExists(atPath: newURL.path) else {
            Self.logger.warning("Rename failed: file already exists at \(newURL.lastPathComponent)")
            return false
        }

        do {
            try fm.moveItem(at: item.url, to: newURL)

            let oldSidecar = OCRProcessor.sidecarURL(for: item.url)
            if fm.fileExists(atPath: oldSidecar.path) {
                let newSidecar = OCRProcessor.sidecarURL(for: newURL)
                try fm.moveItem(at: oldSidecar, to: newSidecar)
            }

            return true
        } catch {
            Self.logger.error("Rename failed: \(error.localizedDescription)")
            return false
        }
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
