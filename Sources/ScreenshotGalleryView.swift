import SwiftUI

struct ScreenshotGalleryView: View {
    @StateObject private var store = ScreenshotStore()
    @State private var selectedScreenshot: ScreenshotItem?

    private let columns = [GridItem(.adaptive(minimum: 200, maximum: 280), spacing: 16)]

    var body: some View {
        Group {
            if store.screenshots.isEmpty {
                emptyState
            } else {
                galleryGrid
            }
        }
        .sheet(item: $selectedScreenshot) { item in
            ScreenshotPreviewView(item: item, store: store)
        }
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
            // Toolbar
            HStack {
                Text("\(store.screenshots.count) screenshot\(store.screenshots.count == 1 ? "" : "s")")
                    .font(.headline)
                    .foregroundColor(.secondary)

                Spacer()

                Button {
                    ScreenshotManager.revealInFinder()
                } label: {
                    Label("Open in Finder", systemImage: "folder")
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            Divider()

            // Grid
            ScrollView {
                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(store.screenshots) { item in
                        ScreenshotCard(item: item)
                            .onTapGesture {
                                selectedScreenshot = item
                            }
                            .contextMenu {
                                Button("Copy to Clipboard") {
                                    store.copyToClipboard(item)
                                }
                                Button("Reveal in Finder") {
                                    store.revealInFinder(item)
                                }
                                Divider()
                                Button("Delete", role: .destructive) {
                                    store.deleteScreenshot(item)
                                }
                            }
                    }
                }
                .padding(20)
            }
        }
    }
}

// MARK: - Screenshot Card

struct ScreenshotCard: View {
    let item: ScreenshotItem
    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(nsImage: item.thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxHeight: 160)
                .frame(maxWidth: .infinity)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(8)
                .shadow(color: .black.opacity(isHovering ? 0.2 : 0.1), radius: isHovering ? 8 : 4)
                .scaleEffect(isHovering ? 1.02 : 1.0)

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
                .fill(Color(nsColor: .controlBackgroundColor).opacity(isHovering ? 1 : 0))
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
    }
}

// MARK: - Screenshot Preview

struct ScreenshotPreviewView: View {
    let item: ScreenshotItem
    let store: ScreenshotStore
    @Environment(\.dismiss) private var dismiss
    @State private var fullImage: NSImage?
    @State private var showDeleteConfirm = false

    var body: some View {
        VStack(spacing: 0) {
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

            Divider()

            // Info + Actions
            VStack(spacing: 12) {
                // Filename and date
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

                // Action buttons — full width row
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

                    Button {
                        dismiss()
                    } label: {
                        Text("Done")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
            .padding(16)
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
                dismiss()
            }
        } message: {
            Text("This will permanently delete \"\(item.filename)\" from disk.")
        }
    }
}
