import Blooming8Core
import AppKit
import SwiftUI

struct LibraryGrid: View {
    @ObservedObject var library: LibraryModel
    @ObservedObject var settings: AppSettings
    @ObservedObject var controller: PhotoController
    let thumbnailSize: Double

    /// A video the user tapped, awaiting the frame-picker sheet. Videos
    /// aren't sent directly — there's no single "the" frame to upload — so a
    /// tap here bypasses `library.selection`/Send entirely.
    @State private var videoForFramePicker: LibraryItem?

    var body: some View {
        Group {
            if library.isLoading {
                loading
            } else if let error = library.loadError, library.items.isEmpty {
                message(error, symbol: "exclamationmark.triangle")
            } else if library.filteredItems.isEmpty {
                message("Nothing matches “\(library.searchText)”.", symbol: "magnifyingglass")
            } else {
                grid
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .searchable(text: $library.searchText, placement: .toolbar, prompt: "Filter by filename")
        .safeAreaInset(edge: .bottom) { countBar }
        .sheet(item: $videoForFramePicker) { item in
            if let url = item.url {
                VideoFramePickerSheet(videoURL: url, controller: controller)
            }
        }
    }

    private var grid: some View {
        ScrollView {
            // LazyVGrid only materialises visible cells, and each cell loads
            // its own thumbnail on appear — the combination is what makes a
            // folder of 10k+ photos scroll without stalling.
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: thumbnailSize), spacing: 10)],
                spacing: 10
            ) {
                ForEach(library.filteredItems) { item in
                    LibraryCell(
                        item: item,
                        size: thumbnailSize,
                        isSelected: library.selection == item.id,
                        settings: settings
                    )
                    .onTapGesture {
                        if item.isVideo {
                            videoForFramePicker = item
                        } else {
                            library.selection = item.id
                        }
                    }
                    .contextMenu { contextMenu(for: item) }
                }
            }
            .padding(12)
        }
    }

    @ViewBuilder
    private func contextMenu(for item: LibraryItem) -> some View {
        if item.isVideo {
            Button("Pick a Frame to Send…") { videoForFramePicker = item }
        } else {
            Button("Send to Frame") { send(item) }
        }

        if let url = item.url {
            Divider()
            Button("Reveal in Finder") {
                NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: url.deletingLastPathComponent().path)
            }
            Button("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(url.path, forType: .string)
            }
            if !item.isVideo {
                Divider()
                if settings.favoriteImagePaths.contains(url.path) {
                    Button("Remove from Favorites", role: .destructive) {
                        settings.favoriteImagePaths.removeAll { $0 == url.path }
                    }
                } else {
                    Button("Add to Favorites") {
                        settings.favoriteImagePaths.append(url.path)
                    }
                }
            }
        }
    }

    private func send(_ item: LibraryItem) {
        Task {
            if let url = item.url {
                controller.prepareBrowsedImage(url: url)
                // prepareBrowsedImage renders off the main thread and parks the
                // result in localFolderCandidates; send the one it produced.
                while controller.localFolderCandidates.isEmpty && controller.isBusy {
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }
                if let candidate = controller.localFolderCandidates.first {
                    await controller.confirmLocalFolderCandidate(candidate)
                    controller.cancelLocalFolderCandidate()
                }
            } else if let devicePath = item.devicePath {
                await controller.showImageAtPath(devicePath)
            }
        }
    }

    private var loading: some View {
        VStack(spacing: 10) {
            ProgressView()
            Text("Scanning…")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func message(_ text: String, symbol: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 34))
                .foregroundStyle(.tertiary)
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var countBar: some View {
        HStack {
            Text(countLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(.bar)
    }

    private var countLabel: String {
        let shown = library.filteredItems.count
        let total = library.items.count
        let videoCount = library.items.filter(\.isVideo).count
        let imageCount = total - videoCount
        let videoSuffix = videoCount > 0 ? ", \(videoCount) video\(videoCount == 1 ? "" : "s")" : ""
        if shown == total {
            return "\(imageCount) image\(imageCount == 1 ? "" : "s")\(videoSuffix)"
        }
        return "\(shown) of \(total) shown\(videoSuffix)"
    }
}

/// A single grid cell. Loads its thumbnail on appear via the shared store, so
/// scrolling past a cell never blocks and revisiting one is cached.
private struct LibraryCell: View {
    let item: LibraryItem
    let size: Double
    let isSelected: Bool
    @ObservedObject var settings: AppSettings

    @State private var image: NSImage?
    @State private var didAttemptLoad = false

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.gray.opacity(0.15))

                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                } else if didAttemptLoad {
                    Image(systemName: item.isVideo ? "film" : (item.isLocal ? "questionmark.square.dashed" : "photo"))
                        .font(.system(size: 20))
                        .foregroundStyle(.tertiary)
                } else {
                    ProgressView().controlSize(.small)
                }

                if isFavorite {
                    Image(systemName: "star.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.yellow)
                        .padding(4)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                }

                if item.isVideo {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.white, .black.opacity(0.4))
                }
            }
            .frame(height: size)
            .clipped()
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? Color.accentColor : .clear, lineWidth: 3)
            )

            Text(item.name)
                .font(.caption2)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(isSelected ? .primary : .secondary)
        }
        .help(item.url?.path ?? item.devicePath ?? item.name)
        .task(id: item.id) {
            guard image == nil else { return }
            if item.isVideo, let url = item.url {
                image = await VideoFrameExtractor.previewFrame(from: url, maxPixelSize: 400)
            } else if let url = item.url {
                image = await ThumbnailStore.shared.thumbnail(for: url, maxPixelSize: 400)
            } else if let devicePath = item.devicePath {
                // The frame has no thumbnail endpoint, so this is a real
                // full-size fetch — DeviceThumbnailStore caps how many run
                // at once so a big gallery doesn't hammer the frame's HTTP
                // server while the grid scrolls past dozens of cells.
                image = await DeviceThumbnailStore.shared.thumbnail(
                    ip: settings.deviceIP,
                    path: devicePath,
                    maxPixelSize: 400
                )
            }
            didAttemptLoad = true
        }
    }

    private var isFavorite: Bool {
        guard let path = item.url?.path else { return false }
        return settings.favoriteImagePaths.contains(path)
    }
}
