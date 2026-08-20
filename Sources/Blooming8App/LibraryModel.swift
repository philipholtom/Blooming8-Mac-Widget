import Blooming8Core
import AppKit
import Combine
import SwiftUI
import os

/// What the sidebar can select, and the detail pane can show.
enum LibrarySource: Hashable {
    case currentPhoto
    case localFolder
    case favorites
    case generated
    case gallery(String)

    var title: String {
        switch self {
        case .currentPhoto: return "On the Frame"
        case .localFolder: return "Local Folder"
        case .favorites: return "Favorites"
        case .generated: return "Generated"
        case .gallery(let name): return name
        }
    }

    var symbol: String {
        switch self {
        case .currentPhoto: return "photo.on.rectangle.angled"
        case .localFolder: return "folder"
        case .favorites: return "star"
        case .generated: return "sparkles"
        case .gallery: return "rectangle.stack"
        }
    }
}

/// One browsable item: an image (local file or already on the frame) or a
/// local video, which isn't sent directly — picking one opens a frame picker
/// (`VideoFramePickerSheet`) instead of Send to Frame.
struct LibraryItem: Identifiable, Hashable {
    enum Kind {
        case image
        case video
    }

    let id: String
    let url: URL?
    let devicePath: String?
    let name: String
    let kind: Kind

    init(localURL: URL, kind: Kind = .image) {
        self.id = localURL.path
        self.url = localURL
        self.devicePath = nil
        self.name = localURL.lastPathComponent
        self.kind = kind
    }

    init(devicePath: String) {
        self.id = devicePath
        self.url = nil
        self.devicePath = devicePath
        self.name = (devicePath as NSString).lastPathComponent
        self.kind = .image
    }

    var isLocal: Bool { url != nil }
    var isVideo: Bool { kind == .video }
}

/// Backs the grid: owns the current source's item list and the work of
/// producing it. Enumeration and device fetches both happen off the main
/// thread — a 10k-file folder walk on the main actor freezes the window.
@MainActor
final class LibraryModel: ObservableObject {
    private static let log = Logger(subsystem: "com.pholtom.blooming8app", category: "library")

    @Published var items: [LibraryItem] = []
    @Published var isLoading = false
    @Published var loadError: String?
    @Published var selection: LibraryItem.ID?
    @Published var searchText: String = ""

    private let settings: AppSettings
    private let controller: PhotoController
    private let client = BloominClient()
    private var loadTask: Task<Void, Never>?

    /// Filenames per gallery, from the last successful fetch this session.
    /// Revisiting a gallery you've already opened redisplays instantly from
    /// here instead of re-walking the device's (slow, paginated) `/gallery`
    /// listing endpoint every single click — that listing fetch, not image
    /// data, was the actual source of the "reloads every time" delay, since
    /// DeviceThumbnailStore already caches the thumbnails themselves.
    private var galleryListingCache: [String: [String]] = [:]

    init(settings: AppSettings, controller: PhotoController) {
        self.settings = settings
        self.controller = controller
    }

    var filteredItems: [LibraryItem] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return items }
        return items.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var selectedItem: LibraryItem? {
        guard let selection else { return nil }
        return items.first { $0.id == selection }
    }

    func load(_ source: LibrarySource) {
        Self.log.notice("load: \(source.title, privacy: .public)")
        loadTask?.cancel()
        selection = nil
        loadError = nil

        switch source {
        case .currentPhoto, .generated:
            items = []
            isLoading = false

        case .localFolder:
            let path = settings.randomFolderPath.trimmingCharacters(in: .whitespaces)
            guard !path.isEmpty else {
                items = []
                loadError = "No folder chosen yet."
                return
            }
            loadLocal(folder: URL(fileURLWithPath: path))

        case .favorites:
            items = settings.favoriteImagePaths.map { LibraryItem(localURL: URL(fileURLWithPath: $0)) }
            isLoading = false

        case .gallery(let name):
            loadGallery(named: name)
        }
    }

    private func loadLocal(folder: URL) {
        isLoading = true
        items = []
        loadTask = Task {
            // Off the main actor: walking tens of thousands of files blocks
            // for seconds and would freeze the whole window.
            let (imageURLs, videoURLs) = await Task.detached(priority: .userInitiated) {
                (ImageFolder.enumerateImages(in: folder), VideoFolder.enumerateVideos(in: folder))
            }.value
            guard !Task.isCancelled else { return }
            let combined = imageURLs.map { LibraryItem(localURL: $0, kind: .image) }
                + videoURLs.map { LibraryItem(localURL: $0, kind: .video) }
            items = combined.sorted { $0.url!.path.localizedStandardCompare($1.url!.path) == .orderedAscending }
            Self.log.notice("load: local folder produced \(imageURLs.count) images, \(videoURLs.count) videos")
            isLoading = false
            if items.isEmpty { loadError = "No images or videos found under \(folder.path)." }
        }
    }

    private func loadGallery(named name: String) {
        // Stale-while-revalidate: a cache hit shows instantly with no
        // spinner, then a fresh fetch runs silently underneath and updates
        // `items` again once it lands — so a gallery someone's added photos
        // to since your last visit still catches up, just without making
        // every single click wait on the device's slow listing endpoint.
        if let cachedNames = galleryListingCache[name] {
            items = cachedNames.map { LibraryItem(devicePath: "/gallerys/\(name)/\($0)") }
            isLoading = false
            loadError = items.isEmpty ? "This gallery is empty." : nil
        } else {
            isLoading = true
            items = []
        }

        loadTask = Task {
            do {
                let names = try await client.fetchAllImages(ip: settings.deviceIP, gallery: name)
                guard !Task.isCancelled else { return }
                galleryListingCache[name] = names
                items = names.map { LibraryItem(devicePath: "/gallerys/\(name)/\($0)") }
                isLoading = false
                loadError = items.isEmpty ? "This gallery is empty." : nil
            } catch {
                guard !Task.isCancelled else { return }
                isLoading = false
                // Cached data is already on screen — a background refresh
                // failing (the frame went to sleep, a request timed out)
                // shouldn't replace it with an error the user didn't ask for.
                if items.isEmpty {
                    loadError = error.localizedDescription
                }
            }
        }
    }
}
