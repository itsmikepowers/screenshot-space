import SwiftUI

struct SearchView: View {
    @ObservedObject private var store = ScreenshotStore.shared
    @State private var query = ""
    @AppStorage("searchViewMode") private var viewMode: String = "list"

    private var mode: ViewMode { ViewMode(rawValue: viewMode) ?? .list }
    private let columns = [GridItem(.adaptive(minimum: 200, maximum: 280), spacing: 16)]

    private var results: [ScreenshotItem] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }
        let lowered = trimmed.lowercased()

        return store.screenshots.filter { item in
            if let text = item.extractedText, text.lowercased().contains(lowered) {
                return true
            }
            if item.filename.lowercased().contains(lowered) {
                return true
            }
            return false
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)

                TextField("Search screenshot text...", text: $query)
                    .textFieldStyle(.plain)
                    .font(.title3)

                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.borderless)
                }

                Divider()
                    .frame(height: 16)

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewMode = mode == .grid ? "list" : "grid"
                    }
                } label: {
                    Image(systemName: mode == .grid ? "list.bullet" : "square.grid.2x2")
                }
                .buttonStyle(.borderless)
                .help(mode == .grid ? "Switch to list view" : "Switch to grid view")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider()

            // Results
            if query.trimmingCharacters(in: .whitespaces).isEmpty {
                emptyPrompt
            } else if results.isEmpty {
                noResults
            } else {
                resultsList
            }
        }
    }

    // MARK: - Empty Prompt

    private var emptyPrompt: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "text.magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.4))
            Text("Search Your Screenshots")
                .font(.title2.bold())
                .foregroundColor(.secondary)
            Text("Type to search text found inside your screenshots.\nAll text is extracted automatically using on-device OCR.")
                .font(.body)
                .foregroundColor(.secondary.opacity(0.7))
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - No Results

    private var noResults: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.4))
            Text("No Matches")
                .font(.title2.bold())
                .foregroundColor(.secondary)
            Text("No screenshots contain \"\(query)\".\nNew screenshots are processed automatically.")
                .font(.body)
                .foregroundColor(.secondary.opacity(0.7))
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Results List

    private var resultsList: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(results.count) result\(results.count == 1 ? "" : "s")")
                    .font(.headline)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)

            Divider()

            ScrollView {
                if mode == .grid {
                    LazyVGrid(columns: columns, spacing: 20) {
                        ForEach(results) { item in
                            searchGridItem(for: item)
                        }
                    }
                    .padding(20)
                } else {
                    LazyVStack(spacing: 1) {
                        ForEach(results) { item in
                            searchListItem(for: item)
                        }
                    }
                }
            }
        }
    }

    private func searchGridItem(for item: ScreenshotItem) -> some View {
        ScreenshotCard(item: item, isSelected: false)
            .contentShape(Rectangle())
            .onDrag {
                FileExportDrag.itemProvider(for: [item.url])
            }
            .onTapGesture {
                ScreenshotPreviewWindowPresenter.present(item: item, store: store)
            }
            .contextMenu {
                searchContextMenu(for: item)
            }
    }

    private func searchListItem(for item: ScreenshotItem) -> some View {
        SearchResultRow(item: item, query: query)
            .contentShape(Rectangle())
            .onDrag {
                FileExportDrag.itemProvider(for: [item.url])
            }
            .onTapGesture {
                ScreenshotPreviewWindowPresenter.present(item: item, store: store)
            }
            .contextMenu {
                searchContextMenu(for: item)
            }
    }

    @ViewBuilder
    private func searchContextMenu(for item: ScreenshotItem) -> some View {
        Button("Copy to Clipboard") {
            store.copyToClipboard(item)
        }
        Button("Reveal in Finder") {
            store.revealInFinder(item)
        }
        if let text = item.extractedText, !text.isEmpty {
            Button("Copy Extracted Text") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            }
        }
    }
}

// MARK: - Search Result Row

struct SearchResultRow: View {
    let item: ScreenshotItem
    let query: String
    @State private var isHovering = false

    /// Find a snippet of extracted text around the first match.
    private var matchSnippet: String? {
        guard let text = item.extractedText else { return nil }
        let lowered = text.lowercased()
        let queryLowered = query.lowercased().trimmingCharacters(in: .whitespaces)
        guard !queryLowered.isEmpty,
              let range = lowered.range(of: queryLowered) else { return nil }

        let matchStart = text.distance(from: text.startIndex, to: range.lowerBound)
        let snippetStart = max(0, matchStart - 40)
        let snippetEnd = min(text.count, matchStart + queryLowered.count + 60)

        let startIdx = text.index(text.startIndex, offsetBy: snippetStart)
        let endIdx = text.index(text.startIndex, offsetBy: snippetEnd)
        var snippet = String(text[startIdx..<endIdx])
            .replacingOccurrences(of: "\n", with: " ")

        if snippetStart > 0 { snippet = "..." + snippet }
        if snippetEnd < text.count { snippet = snippet + "..." }

        return snippet
    }

    var body: some View {
        HStack(spacing: 14) {
            // Thumbnail
            Image(nsImage: item.thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 56, height: 42)
                .cornerRadius(6)
                .clipped()

            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(item.filename)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)

                if let snippet = matchSnippet {
                    Text(highlightedSnippet(snippet))
                        .font(.system(size: 12))
                        .lineLimit(2)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Metadata
            VStack(alignment: .trailing, spacing: 4) {
                Text(item.dateString)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                if let wc = item.wordCount, wc > 0 {
                    Text("\(wc) words")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary.opacity(0.7))
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(isHovering ? Color(nsColor: .controlBackgroundColor) : Color.clear)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovering = hovering
            }
        }
    }

    /// Returns an AttributedString with the query highlighted in bold + accent color.
    private func highlightedSnippet(_ snippet: String) -> AttributedString {
        var attributed = AttributedString(snippet)
        let queryLowered = query.lowercased().trimmingCharacters(in: .whitespaces)

        if let range = attributed.range(of: queryLowered, options: .caseInsensitive) {
            attributed[range].foregroundColor = .accentColor
            attributed[range].font = .system(size: 12, weight: .semibold)
        }

        return attributed
    }
}
