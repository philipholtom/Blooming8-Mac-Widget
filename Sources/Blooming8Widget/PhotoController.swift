import AppKit
import Combine

@MainActor
final class PhotoController: ObservableObject {
    let settings: Settings
    private let client = BloominClient()

    @Published var previewImage: NSImage?
    @Published var currentImagePath: String?
    @Published var deviceName: String?
    @Published var currentGalleryOnDevice: String?
    @Published var galleries: [String] = []
    @Published var statusText: String = ""
    @Published var isBusy: Bool = false

    init(settings: Settings) {
        self.settings = settings
    }

    func loadGalleries() async {
        guard !settings.deviceIP.isEmpty else { return }
        do {
            let names = try await client.fetchGalleryList(ip: settings.deviceIP)
            galleries = names
            // Drop any previously-selected galleries that no longer exist on the device.
            settings.selectedGalleries.formIntersection(names)
            if settings.selectedGalleries.isEmpty {
                let fallback = currentGalleryOnDevice.flatMap { names.contains($0) ? $0 : nil } ?? names.first
                settings.selectedGalleries = fallback.map { [$0] } ?? []
            }
        } catch {
            statusText = "Couldn't load galleries: \(error.localizedDescription)"
        }
    }

    func refreshCurrentPhoto() async {
        guard !settings.deviceIP.isEmpty else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            let info = try await client.fetchDeviceInfo(ip: settings.deviceIP)
            deviceName = info.name
            currentGalleryOnDevice = info.gallery
            if let path = info.image, !path.isEmpty {
                let data = try await client.fetchImageData(ip: settings.deviceIP, path: path)
                previewImage = NSImage(data: data)
                currentImagePath = path
            }
            statusText = ""
        } catch {
            statusText = "Couldn't reach frame: \(error.localizedDescription)"
        }
    }

    func showRandomPhoto() async {
        let galleriesToUse = settings.selectedGalleries
        guard !galleriesToUse.isEmpty else {
            statusText = "Select at least one gallery."
            return
        }
        isBusy = true
        defer { isBusy = false }
        do {
            let picked: (gallery: String, name: String)
            let statusMessage: String

            switch settings.randomWeighting {
            case .perPhoto:
                // Pool every image from every selected gallery, then pick one photo
                // uniformly from the pool — a gallery with 150 photos naturally
                // contributes more candidates than one with 10.
                var pool: [(gallery: String, name: String)] = []
                for gallery in galleriesToUse {
                    let images = try await client.fetchAllImages(ip: settings.deviceIP, gallery: gallery)
                    pool.append(contentsOf: images.map { (gallery: gallery, name: $0) })
                }
                guard let choice = pool.randomElement() else {
                    statusText = "No images found in the selected galleries."
                    return
                }
                picked = choice
                let galleryWord = galleriesToUse.count == 1 ? "gallery" : "galleries"
                statusMessage = "Picked from \(pool.count) photo\(pool.count == 1 ? "" : "s") across \(galleriesToUse.count) \(galleryWord)."

            case .perGallery:
                // Pick a gallery first, giving every gallery equal odds regardless
                // of size, then a random photo from within just that gallery.
                guard let chosenGallery = galleriesToUse.randomElement() else {
                    statusText = "No images found in the selected galleries."
                    return
                }
                let images = try await client.fetchAllImages(ip: settings.deviceIP, gallery: chosenGallery)
                guard let name = images.randomElement() else {
                    statusText = "No images found in '\(chosenGallery)'."
                    return
                }
                picked = (gallery: chosenGallery, name: name)
                statusMessage = "Picked gallery '\(chosenGallery)' (\(images.count) photos), then a random photo from it."
            }

            let path = "/gallerys/\(picked.gallery)/\(picked.name)"
            try await client.show(ip: settings.deviceIP, imagePath: path)
            let data = try await client.fetchImageData(ip: settings.deviceIP, path: path)
            previewImage = NSImage(data: data)
            currentImagePath = path
            currentGalleryOnDevice = picked.gallery
            statusText = statusMessage
        } catch {
            statusText = "Couldn't show a random photo: \(error.localizedDescription)"
        }
    }
}
