import Foundation
import Vision
import AppKit
import os.log

/// Processes screenshots with Apple's Vision OCR and saves metadata as JSON sidecar files.
enum OCRProcessor {
    
    private static let logger = Logger(subsystem: "com.screenshotspace", category: "OCRProcessor")
    
    private static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
    
    private static let jsonEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()
    
    private static let maxImageDimension: CGFloat = 8192
    private static let ocrTimeoutSeconds: TimeInterval = 30

    // MARK: - Metadata Model

    struct ScreenshotMetadata: Codable {
        let extractedText: String
        let wordCount: Int
        let lineCount: Int
        let characterCount: Int
        let width: Int
        let height: Int
        let processedAt: String
    }

    // MARK: - Public API

    /// Process a screenshot on a background queue (for new screenshots).
    static func process(url: URL) {
        DispatchQueue.global(qos: .userInitiated).async {
            processSync(url: url)
        }
    }

    /// Process a screenshot synchronously on the current thread (for serial backfill).
    static func processSync(url: URL) {
        autoreleasepool {
            guard FileManager.default.fileExists(atPath: url.path) else {
                logger.warning("File does not exist: \(url.lastPathComponent)")
                return
            }
            
            guard let cgImage = loadCGImage(from: url) else {
                logger.warning("Failed to load image: \(url.lastPathComponent)")
                return
            }
            
            if CGFloat(cgImage.width) > maxImageDimension || CGFloat(cgImage.height) > maxImageDimension {
                logger.warning("Image too large for OCR: \(cgImage.width)x\(cgImage.height)")
            }

            let text = extractText(from: cgImage)
            let words = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            let lines = text.components(separatedBy: .newlines).filter { !$0.isEmpty }

            let metadata = ScreenshotMetadata(
                extractedText: text,
                wordCount: words.count,
                lineCount: lines.count,
                characterCount: text.count,
                width: cgImage.width,
                height: cgImage.height,
                processedAt: iso8601Formatter.string(from: Date())
            )

            let jsonURL = sidecarURL(for: url)

            do {
                let data = try jsonEncoder.encode(metadata)
                try data.write(to: jsonURL, options: .atomic)
                logger.debug("OCR complete: \(url.lastPathComponent) (\(words.count) words)")
                
                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: .screenshotOCRCompleted,
                        object: nil,
                        userInfo: ["url": url]
                    )
                }
            } catch {
                logger.error("Failed to save OCR metadata: \(error.localizedDescription)")
            }
        }
    }

    /// Load metadata from the JSON sidecar for a given screenshot URL.
    /// Returns `nil` if no sidecar exists yet.
    static func loadMetadata(for imageURL: URL) -> ScreenshotMetadata? {
        let jsonURL = sidecarURL(for: imageURL)
        guard let data = try? Data(contentsOf: jsonURL) else { return nil }
        do {
            return try JSONDecoder().decode(ScreenshotMetadata.self, from: data)
        } catch {
            logger.debug("Failed to decode metadata for \(imageURL.lastPathComponent): \(error.localizedDescription)")
            return nil
        }
    }

    /// Returns the `.json` sidecar URL for a given image URL.
    static func sidecarURL(for imageURL: URL) -> URL {
        imageURL.deletingPathExtension().appendingPathExtension("json")
    }

    /// Check whether a sidecar already exists for the given image.
    static func hasSidecar(for imageURL: URL) -> Bool {
        FileManager.default.fileExists(atPath: sidecarURL(for: imageURL).path)
    }

    // MARK: - Vision OCR

    private static func extractText(from image: CGImage) -> String {
        var resultText = ""
        let semaphore = DispatchSemaphore(value: 0)
        
        let request = VNRecognizeTextRequest { request, error in
            defer { semaphore.signal() }
            
            if let error = error {
                logger.error("OCR request error: \(error.localizedDescription)")
                return
            }
            
            guard let observations = request.results as? [VNRecognizedTextObservation] else { return }
            
            resultText = observations
                .compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: "\n")
        }
        
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.revision = VNRecognizeTextRequestRevision3

        let handler = VNImageRequestHandler(cgImage: image, options: [:])

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try handler.perform([request])
            } catch {
                logger.error("OCR handler error: \(error.localizedDescription)")
                semaphore.signal()
            }
        }
        
        let result = semaphore.wait(timeout: .now() + ocrTimeoutSeconds)
        if result == .timedOut {
            logger.warning("OCR timed out after \(ocrTimeoutSeconds)s")
            request.cancel()
        }

        return resultText
    }

    // MARK: - Image Loading

    private static func loadCGImage(from url: URL) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceShouldCache: false,
            kCGImageSourceShouldAllowFloat: true
        ]
        
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options as CFDictionary) else {
            return nil
        }
        
        return CGImageSourceCreateImageAtIndex(source, 0, options as CFDictionary)
    }
}
