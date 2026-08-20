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

/// One browsable item: an image (local file, already on the frame, or a
/// local video). A video isn't sent directly — picking one opens a frame
/// picker (`VideoFramePickerSheet`) instead of Send to Frame.
struct LibraryItem: Identifiable, Hashable {
    enum Kind {
        case image
        case video
    }

    let id: String
    let url: URL?
    let devicePath: String?
    /// Set only for device-hosted items, alongside `devicePath` — carried
    /// separately rather than re-parsed out of the path string, since
    /// deleting an image needs the gallery name and bare filename apart.
    let galleryName: String?
    let name: String
    let kind: Kind

    init(localURL: URL, kind: Kind = .image) {
        self.id = localURL.path
        self.url = localURL
        self.devicePath = nil
        self.galleryName = nil
        self.name = localURL.lastPathComponent
        self.kind = kind
    }

    init(devicePath: String, galleryName: String) {
        self.id = devicePath
        self.url = nil
        self.devicePath = devicePath
        self.galleryName = galleryName
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
    /// The single item the inspector shows. Plain click sets this (and
    /// clears `selectedIDs` down to just that one item); it's kept separate
    /// from multi-select so the inspector always has one unambiguous subject.
    @Published var selection: LibraryItem.ID?
    /// Cmd/Shift-click multi-selection, for bulk favorite/delete. Always a
    /// superset containing `selection` when both are non-empty.
    @Published var selectedIDs: Set<LibraryItem.ID> = []
    @Published var searchText: String = ""
    private(set) var currentSource: LibrarySource?

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

    /// The actual selected items, in the same order they appear in the grid
    /// — used for bulk actions and for Shift-click range extension.
    var selectedItems: [LibraryItem] {
        filteredItems.filter { selectedIDs.contains($0.id) }
    }

    func load(_ source: LibrarySource) {
        Self.log.notice("load: \(source.title, privacy: .public)")
        loadTask?.cancel()
        currentSource = source
        selection = nil
        selectedIDs = []
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

    /// Click-selection with Cmd (toggle) / Shift (range from the last
    /// anchor) support, matching the standard macOS Finder-grid convention.
    func selectItem(_ item: LibraryItem, extendWithCommand: Bool, extendWithShift: Bool) {
        if extendWithShift, let anchor = selection,
           let anchorIndex = filteredItems.firstIndex(where: { $0.id == anchor }),
           let targetIndex = filteredItems.firstIndex(where: { $0.id == item.id }) {
            let range = anchorIndex < targetIndex ? anchorIndex...targetIndex : targetIndex...anchorIndex
            selectedIDs.formUnion(filteredItems[range].map(\.id))
            return
        }
        if extendWithCommand {
            if selectedIDs.contains(item.id) {
                selectedIDs.remove(item.id)
                if selection == item.id { selection = selectedIDs.first }
            } else {
                selectedIDs.insert(item.id)
                selection = item.id
            }
            return
        }
        selection = item.id
        selectedIDs = [item.id]
    }

    /// Removes an item from `items` (and, for a gallery, its cache) after a
    /// successful delete on the frame — without waiting on a full reload.
    func removeItem(_ item: LibraryItem) {
        items.removeAll { $0.id == item.id }
        selectedIDs.remove(item.id)
        if selection == item.id { selection = nil }
        if let galleryName = item.galleryName {
            galleryListingCache[galleryName]?.removeAll { $0 == item.name }
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
            items = cachedNames.map { LibraryItem(devicePath: "/gallerys/\(name)/\($0)", galleryName: name) }
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
                items = names.map { LibraryItem(devicePath: "/gallerys/\(name)/\($0)", galleryName: name) }
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
