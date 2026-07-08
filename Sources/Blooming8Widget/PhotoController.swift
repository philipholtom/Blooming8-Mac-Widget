import AppKit
import Combine

@MainActor
final class PhotoController: ObservableObject {
    let settings: Settings
    private let client = BloominClient()
    private let bleWaker = BLEWaker()

    @Published var previewImage: NSImage?
    @Published var currentImagePath: String?
    @Published var deviceName: String?
    @Published var batteryPercent: Int?
    @Published var currentGalleryOnDevice: String?
    @Published var galleries: [String] = []
    @Published var statusText: String = ""
    @Published var isBusy: Bool = false
    /// Tabs unlocked this app session (in-memory only — re-locks on relaunch).
    @Published var unlockedTabIDs: Set<UUID> = []

    init(settings: Settings) {
        self.settings = settings
    }

    /// Every gallery name that's currently selectable for randomization: ones
    /// not assigned to any tab, plus ones in tabs that are unlocked (or have
    /// no password). Galleries in a still-locked tab are excluded even if
    /// they were checked before the tab got locked.
    var availableGalleryNames: Set<String> {
        let assigned = Set(settings.tabs.flatMap { $0.galleryNames })
        var available = Set(galleries).subtracting(assigned)
        for tab in settings.tabs where !tab.isLocked || unlockedTabIDs.contains(tab.id) {
            available.formUnion(tab.galleryNames)
        }
        return available
    }

    @discardableResult
    func unlock(tab: GalleryTab, password: String) -> Bool {
        guard let hash = tab.passwordHash else {
            unlockedTabIDs.insert(tab.id)
            return true
        }
        guard PasswordHasher.hash(password) == hash else { return false }
        unlockedTabIDs.insert(tab.id)
        return true
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

    /// Sends a Bluetooth wake pulse on demand (e.g. from a button or menu item),
    /// independent of any HTTP call failing first.
    @discardableResult
    func wakeFrame() async -> Bool {
        guard !settings.bleDeviceName.isEmpty else {
            statusText = "Set a Bluetooth device name in Settings first."
            return false
        }
        isBusy = true
        defer { isBusy = false }
        statusText = "Sending Bluetooth wake pulse to '\(settings.bleDeviceName)'..."
        let woke = await bleWaker.wake(deviceName: settings.bleDeviceName)
        statusText = woke
            ? "Wake pulse sent."
            : "Couldn't find '\(settings.bleDeviceName)' over Bluetooth — is it powered on and nearby?"
        return woke
    }

    /// Runs `operation`; if it fails with a connectivity error (the frame is
    /// likely asleep) and a Bluetooth device name is configured, sends a wake
    /// pulse, polls until the frame answers HTTP again, then retries once.
    private func withWakeRetry<T>(_ operation: () async throws -> T) async throws -> T {
        do {
            return try await operation()
        } catch {
            guard isConnectivityError(error), !settings.bleDeviceName.isEmpty else { throw error }
            statusText = "Frame unreachable — sending Bluetooth wake pulse..."
            guard await bleWaker.wake(deviceName: settings.bleDeviceName) else { throw error }
            statusText = "Wake pulse sent — waiting for frame to come online..."
            guard await waitUntilReachable() else { throw error }
            return try await operation()
        }
    }

    private func waitUntilReachable(maxWait: TimeInterval = 45) async -> Bool {
        let deadline = Date().addingTimeInterval(maxWait)
        while Date() < deadline {
            if (try? await client.fetchDeviceInfo(ip: settings.deviceIP)) != nil {
                return true
            }
            try? await Task.sleep(nanoseconds: 3_000_000_000)
        }
        return false
    }

    private func applyDeviceInfo(_ info: DeviceInfo) {
        deviceName = info.name
        currentGalleryOnDevice = info.gallery
        batteryPercent = info.battery
    }

    private func isConnectivityError(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        switch urlError.code {
        case .cannotConnectToHost, .timedOut, .networkConnectionLost, .cannotFindHost, .dnsLookupFailed, .notConnectedToInternet:
            return true
        default:
            return false
        }
    }

    func refreshCurrentPhoto() async {
        guard !settings.deviceIP.isEmpty else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            let info = try await withWakeRetry { try await client.fetchDeviceInfo(ip: settings.deviceIP) }
            applyDeviceInfo(info)
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
        let galleriesToUse = settings.selectedGalleries.intersection(availableGalleryNames)
        guard !galleriesToUse.isEmpty else {
            statusText = "Select at least one (unlocked) gallery."
            return
        }
        isBusy = true
        defer { isBusy = false }
        do {
            // Cheap reachability probe first: if the frame is asleep, this wakes
            // it over Bluetooth and waits before the (heavier) gallery fetches below.
            let info = try await withWakeRetry { try await client.fetchDeviceInfo(ip: settings.deviceIP) }
            applyDeviceInfo(info)

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
