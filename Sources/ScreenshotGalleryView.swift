import SwiftUI

enum ViewMode: String {
    case grid, list
}

// MARK: - Marquee selection (item bounds in gallery content space)

private struct GalleryItemFramesKey: PreferenceKey {
    static var defaultValue: [URL: CGRect] { [:] }

    static func reduce(value: inout [URL: CGRect], nextValue: () -> [URL: CGRect]) {
        let next = nextValue()
        for (k, v) in next {
            value[k] = v
        }
    }
}

struct ScreenshotGalleryView: View {
    @ObservedObject private var store = ScreenshotStore.shared
    @State private var selection = Set<URL>()
    @State private var lastClickedID: URL?
    @State private var showDeleteConfirm = false
    @State private var isRenaming = false
    @State private var renamingItem: ScreenshotItem?
    @State private var renameText = ""
    @State private var lastTapTime = Date.distantPast
    @State private var lastTapURL: URL?
    @AppStorage("galleryViewMode") private var viewMode: String = "grid"
    /// Latest layout frames for visible items (lazy views: only on-screen rows/cells report).
    @State private var itemFrames: [URL: CGRect] = [:]
    /// Rubber-band rect in `galleryMarquee` space while dragging.
    @State private var marqueeRect: CGRect?

    private var mode: ViewMode { ViewMode(rawValue: viewMode) ?? .grid }
    private let columns = [GridItem(.adaptive(minimum: 200, maximum: 280), spacing: 16)]

    var body: some View {
        Group {
            if store.isLoading && store.screenshots.isEmpty {
                loadingState
            } else if store.screenshots.isEmpty {
                emptyState
            } else {
                galleryGrid
            }
        }
        .alert(
            "Delete \(selection.count) Screenshot\(selection.count == 1 ? "" : "s")?",
            isPresented: $showDeleteConfirm
        ) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                store.deleteScreenshots(selection)
                selection.removeAll()
            }
        } message: {
            Text("This will permanently delete the selected screenshot\(selection.count == 1 ? "" : "s") from disk.")
        }
        .alert("Rename Screenshot", isPresented: $isRenaming) {
            TextField("New name", text: $renameText)
            Button("Cancel", role: .cancel) {}
            Button("Rename") {
                if let item = renamingItem {
                    let _ = store.renameScreenshot(item, to: renameText)
                }
            }
        } message: {
            Text("Enter a new name for this screenshot.")
        }
    }

    // MARK: - Loading State

    private var loadingState: some View {
        VStack(spacing: 16) {
            Spacer()

            ProgressView()
                .scaleEffect(1.1)
                .controlSize(.large)

            Text("Loading…")
                .font(.title2.bold())
                .foregroundColor(.secondary)

            Text("Reading your screenshots folder.")
                .font(.body)
                .foregroundColor(.secondary.opacity(0.8))
                .multilineTextAlignment(.center)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "camera.viewfinder")
                .font(.system(size: 56))
                .foregroundColor(.secondary.opacity(0.5))

            Text("No Screenshots Yet")
                .font(.title2.bold())
                .foregroundColor(.secondary)

            Text("Tap the Option key for a full-screen screenshot,\nor hold it to drag-select an area.")
                .font(.body)
                .foregroundColor(.secondary.opacity(0.8))
                .multilineTextAlignment(.center)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Gallery Grid

    private var galleryGrid: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()

            ScrollView {
                ZStack(alignment: .topLeading) {
                    Group {
                        if mode == .grid {
                            LazyVGrid(columns: columns, spacing: 20) {
                                ForEach(store.screenshots) { item in
                                    gridItem(for: item)
                                        .background(itemFrameReporter(for: item.url))
                                }
                            }
                            .padding(20)
                        } else {
                            LazyVStack(spacing: 1) {
                                ForEach(store.screenshots) { item in
                                    listRow(for: item)
                                        .background(itemFrameReporter(for: item.url))
                                }
                            }
                        }
                    }
                    .background {
                        GeometryReader { geo in
                            Color.clear
                                .contentShape(Rectangle())
                                .frame(width: geo.size.width, height: geo.size.height)
                                .gesture(marqueeSelectGesture)
                        }
                    }

                    marqueeSelectionOverlay
                }
                .coordinateSpace(name: "galleryMarquee")
                .onPreferenceChange(GalleryItemFramesKey.self) { itemFrames = $0 }
            }
        }
        .background(KeyEventHandler(
            onSelectAll: {
                withAnimation(.easeInOut(duration: 0.2)) { selectAll() }
            },
            onEscape: {
                withAnimation(.easeInOut(duration: 0.2)) { clearSelection() }
            },
            onDelete: {
                if !selection.isEmpty {
                    showDeleteConfirm = true
                }
            },
            onCopy: {
                if !selection.isEmpty {
                    store.copyToClipboard(selection)
                }
            }
        ))
    }

    // MARK: - Grid Item

    private func gridItem(for item: ScreenshotItem) -> some View {
        ScreenshotCard(
            item: item,
            isSelected: selection.contains(item.url)
        )
        .contentShape(Rectangle())
        .onDrag {
            FileExportDrag.itemProvider(for: urlsToExport(for: item))
        }
        .onTapGesture {
            let now = Date()
            let isDoubleClick = (lastTapURL == item.url)
                && now.timeIntervalSince(lastTapTime) < 0.35
            lastTapTime = now
            lastTapURL = item.url

            if isDoubleClick {
                ScreenshotPreviewWindowPresenter.present(item: item, store: store)
            } else {
                withAnimation(.easeInOut(duration: 0.15)) {
                    handleClick(item: item, event: NSApp.currentEvent)
                }
            }
        }
        .contextMenu {
            contextMenuItems(for: item)
        }
    }

    // MARK: - List Row

    private func listRow(for item: ScreenshotItem) -> some View {
        ScreenshotListRow(
            item: item,
            isSelected: selection.contains(item.url)
        )
            .contentShape(Rectangle())
            .onDrag {
                FileExportDrag.itemProvider(for: urlsToExport(for: item))
            }
            .onTapGesture {
                let now = Date()
                let isDoubleClick = (lastTapURL == item.url)
                    && now.timeIntervalSince(lastTapTime) < 0.35
                lastTapTime = now
                lastTapURL = item.url

                if isDoubleClick {
                    ScreenshotPreviewWindowPresenter.present(item: item, store: store)
                } else {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        handleClick(item: item, event: NSApp.currentEvent)
                    }
                }
            }
            .contextMenu {
                contextMenuItems(for: item)
            }
    }

    // MARK: - Marquee selection

    private func itemFrameReporter(for url: URL) -> some View {
        GeometryReader { geo in
            Color.clear.preference(
                key: GalleryItemFramesKey.self,
                value: [url: geo.frame(in: .named("galleryMarquee"))]
            )
        }
    }

    private var marqueeSelectGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("galleryMarquee"))
            .onChanged { value in
                let dx = value.location.x - value.startLocation.x
                let dy = value.location.y - value.startLocation.y
                if (dx * dx + dy * dy) > 16 {
                    marqueeRect = normalizedMarqueeRect(
                        start: value.startLocation,
                        end: value.location
                    )
                } else {
                    marqueeRect = nil
                }
            }
            .onEnded { value in
                marqueeRect = nil
                let dx = value.location.x - value.startLocation.x
                let dy = value.location.y - value.startLocation.y
                if (dx * dx + dy * dy) <= 16 {
                    let flags = NSEvent.modifierFlags
                    if !flags.contains(.command) && !flags.contains(.shift) {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selection.removeAll()
                        }
                    }
                    return
                }
                let rect = normalizedMarqueeRect(
                    start: value.startLocation,
                    end: value.location
                )
                applyMarqueeSelection(rect: rect)
            }
    }

    @ViewBuilder
    private var marqueeSelectionOverlay: some View {
        if let r = marqueeRect, r.width >= 1, r.height >= 1 {
            Rectangle()
                .fill(Color.accentColor.opacity(0.12))
                .overlay(
                    Rectangle()
                        .strokeBorder(Color.accentColor.opacity(0.75), lineWidth: 1)
                )
                .frame(width: r.width, height: r.height)
                .position(x: r.midX, y: r.midY)
                .allowsHitTesting(false)
        }
    }

    private func normalizedMarqueeRect(start: CGPoint, end: CGPoint) -> CGRect {
        let x = min(start.x, end.x)
        let y = min(start.y, end.y)
        let w = max(abs(end.x - start.x), 1)
        let h = max(abs(end.y - start.y), 1)
        return CGRect(x: x, y: y, width: w, height: h)
    }

    private func applyMarqueeSelection(rect: CGRect) {
        let hits = Set(
            itemFrames.compactMap { url, frame -> URL? in
                rect.intersects(frame) ? url : nil
            }
        )

        let flags = NSEvent.modifierFlags
        withAnimation(.easeInOut(duration: 0.15)) {
            if flags.contains(.command) || flags.contains(.shift) {
                selection.formUnion(hits)
            } else {
                selection = hits
            }
        }
    }

    /// Files to attach when starting a drag from this tile: full selection if it includes this item, otherwise this file only.
    private func urlsToExport(for item: ScreenshotItem) -> [URL] {
        if selection.contains(item.url) {
            return store.screenshots.filter { selection.contains($0.url) }.map(\.url)
        }
        return [item.url]
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 12) {
            if selection.isEmpty {
                Text("\(store.screenshots.count) screenshot\(store.screenshots.count == 1 ? "" : "s")")
                    .font(.headline)
                    .foregroundColor(.secondary)
            } else {
                Text("\(selection.count) of \(store.screenshots.count) selected")
                    .font(.headline)
                    .foregroundColor(.accentColor)
            }

            Spacer()

            if !selection.isEmpty {
                if selection.count == 1,
                   let item = store.screenshots.first(where: { selection.contains($0.url) }) {
                    Button {
                        renameText = item.filename
                        renamingItem = item
                        isRenaming = true
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }
                    .buttonStyle(.borderless)
                    .help("Rename screenshot")
                }

                Button {
                    store.copyToClipboard(selection)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("Copy selected to clipboard")

                Button {
                    store.revealInFinder(selection)
                } label: {
                    Label("Reveal", systemImage: "folder")
                }
                .buttonStyle(.borderless)
                .help("Reveal selected in Finder")

                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .buttonStyle(.borderless)
                .foregroundColor(.red)
                .help("Delete selected")

                Divider()
                    .frame(height: 16)

                Button("Deselect All") {
                    withAnimation(.easeInOut(duration: 0.2)) { clearSelection() }
                }
                .buttonStyle(.borderless)
                .foregroundColor(.secondary)
            }

            if selection.isEmpty {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { selectAll() }
                } label: {
                    Label("Select All", systemImage: "checkmark.circle")
                }
                .buttonStyle(.borderless)
            }

            Button {
                ScreenshotManager.revealInFinder()
            } label: {
                Label("Open in Finder", systemImage: "folder")
            }
            .buttonStyle(.borderless)

            Divider()
                .frame(height: 16)

            // View mode toggle
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
        .padding(.vertical, 12)
        .animation(.easeInOut(duration: 0.2), value: selection.isEmpty)
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func contextMenuItems(for item: ScreenshotItem) -> some View {
        let isPartOfSelection = selection.contains(item.url) && selection.count > 1

        if isPartOfSelection {
            // Bulk context menu
            Button("Copy \(selection.count) Screenshots") {
                store.copyToClipboard(selection)
            }
            Button("Reveal \(selection.count) in Finder") {
                store.revealInFinder(selection)
            }
            Divider()
            Button("Delete \(selection.count) Screenshots", role: .destructive) {
                showDeleteConfirm = true
            }
        } else {
            // Single-item context menu
            Button("Open Preview") {
                ScreenshotPreviewWindowPresenter.present(item: item, store: store)
            }
            Divider()
            Button("Copy to Clipboard") {
                store.copyToClipboard(item)
            }
            Button("Reveal in Finder") {
                store.revealInFinder(item)
            }
            Button("Rename") {
                renameText = item.filename
                renamingItem = item
                isRenaming = true
            }
            Divider()
            Button("Delete", role: .destructive) {
                store.deleteScreenshot(item)
                selection.remove(item.url)
            }
        }
    }

    // MARK: - Selection Logic

    private func handleClick(item: ScreenshotItem, event: NSEvent?) {
        let modifiers = event?.modifierFlags ?? []

        if modifiers.contains(.command) || modifiers.contains(.shift) {
            // Cmd+click or Shift+click: toggle this item in selection
            if selection.contains(item.url) {
                selection.remove(item.url)
            } else {
                selection.insert(item.url)
            }
        } else {
            // Plain click: if this row is already selected, remove it; otherwise select only this item
            if selection.contains(item.url) {
                selection.remove(item.url)
            } else {
                selection = [item.url]
            }
        }
    }

    private func selectAll() {
        selection = Set(store.screenshots.map { $0.url })
    }

    private func clearSelection() {
        selection.removeAll()
        lastClickedID = nil
    }
}

// MARK: - Screenshot Card

struct ScreenshotCard: View {
    let item: ScreenshotItem
    let isSelected: Bool
    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topLeading) {
                Image(nsImage: item.thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 160)
                    .frame(maxWidth: .infinity)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(8)
                    .shadow(
                        color: .black.opacity(isSelected ? 0.25 : (isHovering ? 0.2 : 0.1)),
                        radius: isSelected ? 10 : (isHovering ? 8 : 4)
                    )
                    .scaleEffect(isSelected ? 0.97 : (isHovering ? 1.02 : 1.0))

                // Selection checkmark
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Color.accentColor)
                        .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                        .padding(8)
                        .transition(.scale.combined(with: .opacity))
                }
                
                // OCR processing indicator
                if item.isProcessingOCR {
                    HStack(spacing: 4) {
                        ProgressView()
                            .scaleEffect(0.6)
                        Text("OCR")
                            .font(.system(size: 9, weight: .medium))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .transition(.opacity)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(item.filename)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(item.dateString)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 4)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isSelected
                      ? Color.accentColor.opacity(0.10)
                      : Color(nsColor: .controlBackgroundColor).opacity(isHovering ? 1 : 0))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color.accentColor.opacity(0.6) : Color.clear, lineWidth: 2)
        )
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
        .animation(.easeInOut(duration: 0.2), value: item.isProcessingOCR)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
    }
}

// MARK: - Screenshot List Row

struct ScreenshotListRow: View {
    let item: ScreenshotItem
    let isSelected: Bool
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 14) {
            // Selection checkmark
            ZStack {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Color.accentColor)
                        .transition(.scale.combined(with: .opacity))
                } else {
                    Circle()
                        .strokeBorder(Color.secondary.opacity(isHovering ? 0.4 : 0), lineWidth: 1.5)
                        .frame(width: 18, height: 18)
                }
            }
            .frame(width: 20)
            .animation(.easeInOut(duration: 0.15), value: isSelected)

            // Thumbnail
            Image(nsImage: item.thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 56, height: 42)
                .cornerRadius(6)
                .clipped()

            // Info
            VStack(alignment: .leading, spacing: 2) {
                Text(item.filename)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(item.dateString)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer()

            // OCR status or word count
            if item.isProcessingOCR {
                HStack(spacing: 4) {
                    ProgressView()
                        .scaleEffect(0.5)
                    Text("Processing...")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            } else if let wc = item.wordCount, wc > 0 {
                Text("\(wc) words")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary.opacity(0.7))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(
            isSelected
                ? Color.accentColor.opacity(0.10)
                : (isHovering ? Color(nsColor: .controlBackgroundColor) : Color.clear)
        )
        .animation(.easeInOut(duration: 0.1), value: isHovering)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
        .animation(.easeInOut(duration: 0.2), value: item.isProcessingOCR)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

// MARK: - Key Event Handler (Cmd+A, Escape, Delete)

struct KeyEventHandler: NSViewRepresentable {
    var onSelectAll: () -> Void
    var onEscape: () -> Void
    var onDelete: () -> Void
    var onCopy: () -> Void

    func makeNSView(context: Context) -> KeyCatcherView {
        let view = KeyCatcherView()
        view.onSelectAll = onSelectAll
        view.onEscape = onEscape
        view.onDelete = onDelete
        view.onCopy = onCopy
        return view
    }

    func updateNSView(_ nsView: KeyCatcherView, context: Context) {
        nsView.onSelectAll = onSelectAll
        nsView.onEscape = onEscape
        nsView.onDelete = onDelete
        nsView.onCopy = onCopy
    }
}

class KeyCatcherView: NSView {
    var onSelectAll: (() -> Void)?
    var onEscape: (() -> Void)?
    var onDelete: (() -> Void)?
    var onCopy: (() -> Void)?
    private var localMonitor: Any?

    override var acceptsFirstResponder: Bool { true }
    
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        
        // Remove any existing monitor
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
        
        // Add a local monitor for key events when we have a window
        if window != nil {
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self = self else { return event }
                
                // Only handle if our window is key
                guard self.window?.isKeyWindow == true else { return event }
                
                let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                
                if (modifiers == .command || modifiers == .control) && event.charactersIgnoringModifiers == "a" {
                    self.onSelectAll?()
                    return nil // Consume the event
                } else if modifiers == .command && event.charactersIgnoringModifiers == "c" {
                    self.onCopy?()
                    return nil
                } else if (modifiers == .command || modifiers == .control) && event.charactersIgnoringModifiers == "q" {
                    NSApp.terminate(nil)
                    return nil
                } else if event.keyCode == 53 { // Escape
                    self.onEscape?()
                    return nil
                } else if event.keyCode == 51 || event.keyCode == 117 { // Backspace or Forward Delete
                    self.onDelete?()
                    return nil
                }
                
                return event
            }
        }
    }
    
    deinit {
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        if (modifiers == .command || modifiers == .control) && event.charactersIgnoringModifiers == "a" {
            onSelectAll?()
        } else if modifiers == .command && event.charactersIgnoringModifiers == "c" {
            onCopy?()
        } else if event.keyCode == 53 { // Escape
            onEscape?()
        } else if event.keyCode == 51 || event.keyCode == 117 { // Backspace or Forward Delete
            onDelete?()
        } else {
            super.keyDown(with: event)
        }
    }
}

// MARK: - Screenshot Preview

struct ScreenshotPreviewView: View {
    let item: ScreenshotItem
    let store: ScreenshotStore
    let onClose: () -> Void
    @State private var fullImage: NSImage?
    @State private var showDeleteConfirm = false

    var body: some View {
        VStack(spacing: 0) {
            // Info + Actions (toolbar at top)
            VStack(spacing: 12) {
                HStack {
                    Text(item.filename)
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Text(item.dateString)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                HStack(spacing: 16) {
                    Button {
                        store.copyToClipboard(item)
                    } label: {
                        Label("Copy to Clipboard", systemImage: "doc.on.doc")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)

                    Button {
                        store.revealInFinder(item)
                    } label: {
                        Label("Reveal in Finder", systemImage: "folder")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)

                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
            }
            .padding(16)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            // Image
            Group {
                if let image = fullImage {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
            .contentShape(Rectangle())
            .onDrag {
                FileExportDrag.itemProvider(for: [item.url])
            }
        }
        .frame(minWidth: 600, idealWidth: 800, minHeight: 450, idealHeight: 600)
        .onAppear {
            DispatchQueue.global(qos: .userInitiated).async {
                let image = NSImage(contentsOf: item.url)
                DispatchQueue.main.async {
                    fullImage = image
                }
            }
        }
        .alert("Delete Screenshot?", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                store.deleteScreenshot(item)
                onClose()
            }
        } message: {
            Text("This will permanently delete \"\(item.filename)\" from disk.")
        }
    }
}
