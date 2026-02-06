import Foundation
import AppKit

// MARK: - Model

struct ScreenshotItem: Identifiable, Equatable {
    var id: URL { url }
    let url: URL
    let filename: String
    let date: Date
    let thumbnail: NSImage

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
    @Published var screenshots: [ScreenshotItem] = []

    private let directory = ScreenshotManager.saveDirectory
    private var directoryMonitor: DispatchSourceFileSystemObject?

    init() {
        loadScreenshots()
        startWatching()
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

                    return ScreenshotItem(
                        url: url,
                        filename: url.deletingPathExtension().lastPathComponent,
                        date: date,
                        thumbnail: thumbnail
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
            self?.loadScreenshots()
        }

        source.setCancelHandler {
            close(fd)
        }

        source.resume()
        directoryMonitor = source
    }

    // MARK: - Actions

    func deleteScreenshot(_ item: ScreenshotItem) {
        try? FileManager.default.removeItem(at: item.url)
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
