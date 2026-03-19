import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

enum FileExportDrag {
    /// Drag one or more existing files (e.g. to Finder, browser upload). Originals are not removed by the drag.
    static func itemProvider(for urls: [URL]) -> NSItemProvider {
        let existing = urls.filter { FileManager.default.isReadableFile(atPath: $0.path) }
        guard let first = existing.first else { return NSItemProvider() }
        if existing.count == 1 {
            return NSItemProvider(contentsOf: first) ?? NSItemProvider()
        }
        let provider = NSItemProvider()
        for url in existing {
            let typeId = UTType(filenameExtension: url.pathExtension)?.identifier ?? UTType.data.identifier
            provider.registerFileRepresentation(
                forTypeIdentifier: typeId,
                fileOptions: [],
                visibility: .all
            ) { completion in
                completion(url, false, nil)
                return nil
            }
        }
        return provider
    }
}
