import Foundation
import Vision
import AppKit

/// Processes screenshots with Apple's Vision OCR and saves metadata as JSON sidecar files.
enum OCRProcessor {

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
        guard let cgImage = loadCGImage(from: url) else { return }

        let text = extractText(from: cgImage)
        let words = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
        let lines = text.components(separatedBy: .newlines).filter { !$0.isEmpty }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        let metadata = ScreenshotMetadata(
            extractedText: text,
            wordCount: words.count,
            lineCount: lines.count,
            characterCount: text.count,
            width: cgImage.width,
            height: cgImage.height,
            processedAt: formatter.string(from: Date())
        )

        let jsonURL = sidecarURL(for: url)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        if let data = try? encoder.encode(metadata) {
            try? data.write(to: jsonURL, options: .atomic)
        }
    }

    /// Load metadata from the JSON sidecar for a given screenshot URL.
    /// Returns `nil` if no sidecar exists yet.
    static func loadMetadata(for imageURL: URL) -> ScreenshotMetadata? {
        let jsonURL = sidecarURL(for: imageURL)
        guard let data = try? Data(contentsOf: jsonURL) else { return nil }
        return try? JSONDecoder().decode(ScreenshotMetadata.self, from: data)
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
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: image, options: [:])

        do {
            try handler.perform([request])
        } catch {
            print("OCR error: \(error.localizedDescription)")
            return ""
        }

        guard let observations = request.results else { return "" }

        return observations
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
    }

    // MARK: - Image Loading

    private static func loadCGImage(from url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}
