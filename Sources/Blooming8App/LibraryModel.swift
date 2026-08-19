import Blooming8Core
import AppKit
import Combine
import SwiftUI

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

/// One browsable image. `deviceGallery` distinguishes an image that already
/// lives on the frame from a local file that would need uploading.
struct LibraryItem: Identifiable, Hashable {
    let id: String
    let url: URL?
    let devicePath: String?
    let name: String

    init(localURL: URL) {
        self.id = localURL.path
        self.url = localURL
        self.devicePath = nil
        self.name = localURL.lastPathComponent
    }

    init(devicePath: String) {
        self.id = devicePath
        self.url = nil
        self.devicePath = devicePath
        self.name = (devicePath as NSString).lastPathComponent
    }

    var isLocal: Bool { url != nil }
}

/// Backs the grid: owns the current source's item list and the work of
/// producing it. Enumeration and device fetches both happen off the main
/// thread — a 10k-file folder walk on the main actor freezes the window.
@MainActor
final class LibraryModel: ObservableObject {
    @Published var items: [LibraryItem] = []
    @Published var isLoading = false
    @Published var loadError: String?
    @Published var selection: LibraryItem.ID?
    @Published var searchText: String = ""

    private let settings: AppSettings
    private let controller: PhotoController
    private var loadTask: Task<Void, Never>?

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
            let urls = await Task.detached(priority: .userInitiated) {
                ImageFolder.enumerateImages(in: folder)
                    .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
            }.value
            guard !Task.isCancelled else { return }
            items = urls.map(LibraryItem.init(localURL:))
            isLoading = false
            if items.isEmpty { loadError = "No images found under \(folder.path)." }
        }
    }

    private func loadGallery(named name: String) {
        isLoading = true
        items = []
        loadTask = Task {
            do {
                let names = try await BloominClient().fetchAllImages(ip: settings.deviceIP, gallery: name)
                guard !Task.isCancelled else { return }
                items = names.map { LibraryItem(devicePath: "/gallerys/\(name)/\($0)") }
                isLoading = false
                if items.isEmpty { loadError = "This gallery is empty." }
            } catch {
                guard !Task.isCancelled else { return }
                isLoading = false
                loadError = error.localizedDescription
            }
        }
    }
}
