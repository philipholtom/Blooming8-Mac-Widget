import AppKit
import Combine

@MainActor
final class PhotoController: ObservableObject {
    let settings: Settings
    private let client = BloominClient()
    private let bleWaker = BLEWaker()

    @Published var previewImage: NSImage?
    /// Raw bytes behind `previewImage`, kept alongside it so "Save Photo"
    /// can write the exact original file rather than a re-encoded copy.
    @Published var currentImageData: Data?
    @Published var currentImagePath: String?
    @Published var deviceName: String?
    @Published var batteryPercent: Int?
    @Published var currentGalleryOnDevice: String?
    @Published var galleries: [String] = []
    @Published var sleepDurationSeconds: Int?
    @Published var maxIdleSeconds: Int?
    @Published var wakeSensitivity: Int?
    @Published var statusText: String = ""
    @Published var isBusy: Bool = false
    /// Tabs unlocked this app session (in-memory only — re-locks on relaunch).
    @Published var unlockedTabIDs: Set<UUID> = []
    /// When the next automatic random photo is scheduled to fire, if enabled.
    @Published var nextAutoRandomFireDate: Date?

    private var autoRandomTimer: Timer?
    private var autoRandomCancellable: AnyCancellable?

    init(settings: Settings) {
        self.settings = settings
        // Re-evaluate the schedule whenever any relevant setting changes, and
        // once immediately (Combine's sink fires with the current value right
        // after subscribing) so the schedule is live from app launch.
        autoRandomCancellable = Publishers.CombineLatest4(
            settings.$autoRandomEnabled,
            settings.$autoRandomInterval,
            settings.$autoRandomDailyMinute,
            settings.$deviceIP
        )
        .sink { [weak self] _, _, _, _ in
            self?.updateAutoRandomSchedule()
        }
    }

    /// (Re)starts or stops the auto-random timer to match current settings.
    /// Safe to call any time settings change — always cancels any pending fire first.
    private func updateAutoRandomSchedule() {
        autoRandomTimer?.invalidate()
        autoRandomTimer = nil
        guard settings.autoRandomEnabled, !settings.deviceIP.isEmpty else {
            nextAutoRandomFireDate = nil
            return
        }
        scheduleNextAutoRandom()
    }

    private func scheduleNextAutoRandom() {
        let interval: TimeInterval = settings.autoRandomInterval == .hourly
            ? 3600
            : secondsUntilNextDailyFire()
        nextAutoRandomFireDate = Date().addingTimeInterval(interval)
        autoRandomTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.showRandomPhoto()
                self?.scheduleNextAutoRandom()
            }
        }
    }

    private func secondsUntilNextDailyFire() -> TimeInterval {
        let calendar = Calendar.current
        let now = Date()
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = settings.autoRandomDailyMinute / 60
        components.minute = settings.autoRandomDailyMinute % 60
        components.second = 0
        var fireDate = calendar.date(from: components) ?? now
        if fireDate <= now {
            fireDate = calendar.date(byAdding: .day, value: 1, to: fireDate) ?? now.addingTimeInterval(86400)
        }
        return fireDate.timeIntervalSince(now)
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

    /// Uploads local image files into a gallery, converting each to baseline
    /// JPEG first (the frame's /upload endpoint expects JPEG; re-encoding
    /// also smooths over exotic source formats/color profiles). Creates the
    /// gallery if it doesn't already exist. Does not display any of them —
    /// this is a bulk import, not a "show now" action.
    func uploadPhotos(urls: [URL], gallery: String) async {
        let trimmedGallery = gallery.trimmingCharacters(in: .whitespaces)
        guard !trimmedGallery.isEmpty else {
            statusText = "Choose or type a gallery to upload into."
            return
        }
        guard !urls.isEmpty else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            let info = try await withWakeRetry { try await client.fetchDeviceInfo(ip: settings.deviceIP) }
            applyDeviceInfo(info)
            await client.ensureGallery(ip: settings.deviceIP, name: trimmedGallery)

            var uploaded = 0
            var failed = 0
            for (index, url) in urls.enumerated() {
                statusText = "Uploading \(url.lastPathComponent) (\(index + 1)/\(urls.count))..."
                guard let data = try? Data(contentsOf: url),
                      let image = NSImage(data: data),
                      let jpeg = ImageCanvas.jpegData(image)
                else {
                    failed += 1
                    continue
                }
                let baseName = url.deletingPathExtension().lastPathComponent
                let filename = "\(baseName)_\(Int(Date().timeIntervalSince1970 * 1000))_\(index).jpg"
                do {
                    _ = try await client.uploadImage(ip: settings.deviceIP, filename: filename, gallery: trimmedGallery, imageData: jpeg, showNow: false)
                    uploaded += 1
                } catch {
                    failed += 1
                }
            }
            let failedSuffix = failed > 0 ? " (\(failed) failed)" : ""
            statusText = "Uploaded \(uploaded) of \(urls.count) photo\(urls.count == 1 ? "" : "s") to '\(trimmedGallery)'\(failedSuffix)."
            await loadGalleries()
        } catch {
            statusText = "Couldn't upload: \(error.localizedDescription)"
        }
    }

    /// Downloads every photo in a gallery into a subfolder (named after the
    /// gallery) inside the chosen destination folder.
    func downloadGallery(_ gallery: String, to folder: URL) async {
        guard !gallery.isEmpty else {
            statusText = "Choose a gallery to download."
            return
        }
        isBusy = true
        defer { isBusy = false }
        do {
            let info = try await withWakeRetry { try await client.fetchDeviceInfo(ip: settings.deviceIP) }
            applyDeviceInfo(info)
            let names = try await client.fetchAllImages(ip: settings.deviceIP, gallery: gallery)
            guard !names.isEmpty else {
                statusText = "'\(gallery)' has no photos to download."
                return
            }

            let destination = folder.appendingPathComponent(gallery, isDirectory: true)
            try? FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

            var downloaded = 0
            var failed = 0
            for (index, name) in names.enumerated() {
                statusText = "Downloading \(name) (\(index + 1)/\(names.count))..."
                do {
                    let data = try await client.fetchImageData(ip: settings.deviceIP, path: "/gallerys/\(gallery)/\(name)")
                    try data.write(to: destination.appendingPathComponent(name))
                    downloaded += 1
                } catch {
                    failed += 1
                }
            }
            let failedSuffix = failed > 0 ? " (\(failed) failed)" : ""
            statusText = "Downloaded \(downloaded) of \(names.count) photo\(names.count == 1 ? "" : "s") to \(destination.path)\(failedSuffix)."
        } catch {
            statusText = "Couldn't download: \(error.localizedDescription)"
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
        sleepDurationSeconds = info.sleepDuration
        maxIdleSeconds = info.maxIdle
        wakeSensitivity = info.idxWakeSens
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

    /// Re-sends the currently displayed image to the frame. Useful when the
    /// screen visibly didn't update after a previous action — the frame can
    /// silently reject a /show call while it's still mid-draw from an
    /// earlier one, so this retries a few times with a short pause if it
    /// reports busy.
    func redisplayCurrentPhoto() async {
        guard !settings.deviceIP.isEmpty else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            let info = try await withWakeRetry { try await client.fetchDeviceInfo(ip: settings.deviceIP) }
            applyDeviceInfo(info)
            guard let path = info.image, !path.isEmpty else {
                statusText = "No current photo to redisplay."
                return
            }

            let maxAttempts = 4
            var lastError: Error?
            for attempt in 1...maxAttempts {
                do {
                    try await client.show(ip: settings.deviceIP, imagePath: path)
                    lastError = nil
                    break
                } catch {
                    lastError = error
                    if attempt < maxAttempts {
                        statusText = "Frame busy, retrying (\(attempt)/\(maxAttempts))..."
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                    }
                }
            }
            if let lastError { throw lastError }

            let data = try await client.fetchImageData(ip: settings.deviceIP, path: path)
            previewImage = NSImage(data: data)
            currentImageData = data
            currentImagePath = path
            statusText = "Redisplayed the current photo."
        } catch {
            statusText = "Couldn't redisplay photo: \(error.localizedDescription)"
        }
    }

    /// Advances the frame's current playback queue by one (only meaningful
    /// when it's in gallery-slideshow or playlist mode), then refreshes the
    /// preview to whatever it landed on.
    func showNextImage() async {
        guard !settings.deviceIP.isEmpty else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            try await withWakeRetry { try await client.showNext(ip: settings.deviceIP) }
            let info = try await client.fetchDeviceInfo(ip: settings.deviceIP)
            applyDeviceInfo(info)
            if let path = info.image, !path.isEmpty {
                let data = try await client.fetchImageData(ip: settings.deviceIP, path: path)
                previewImage = NSImage(data: data)
                currentImageData = data
                currentImagePath = path
            }
            statusText = "Showed next image."
        } catch {
            statusText = "Couldn't show next image: \(error.localizedDescription)"
        }
    }

    /// Starts a gallery slideshow that cycles on-device every `durationSeconds`.
    func startSlideshow(gallery: String, durationSeconds: Int) async {
        guard !gallery.isEmpty else {
            statusText = "Choose a gallery for the slideshow."
            return
        }
        isBusy = true
        defer { isBusy = false }
        do {
            try await withWakeRetry {
                try await client.startSlideshow(ip: settings.deviceIP, gallery: gallery, durationSeconds: durationSeconds)
            }
            currentGalleryOnDevice = gallery
            statusText = "Started slideshow of '\(gallery)' every \(durationSeconds)s."
        } catch {
            statusText = "Couldn't start slideshow: \(error.localizedDescription)"
        }
    }

    /// Stops slideshow/playlist playback, returning the frame to single-image mode.
    func stopSlideshow() async {
        isBusy = true
        defer { isBusy = false }
        do {
            try await withWakeRetry { try await client.stopPlayback(ip: settings.deviceIP) }
            statusText = "Stopped slideshow."
        } catch {
            statusText = "Couldn't stop slideshow: \(error.localizedDescription)"
        }
    }

    /// Pushes device-level settings (name, sleep timers, wake sensitivity) to
    /// the frame. Only non-nil values are sent. Refreshes deviceInfo
    /// afterward so the UI reflects what the frame actually accepted.
    func updateDeviceSettings(name: String?, sleepDurationSeconds: Int?, maxIdleSeconds: Int?, wakeSensitivity: Int?) async {
        isBusy = true
        defer { isBusy = false }
        do {
            try await withWakeRetry {
                try await client.updateSettings(
                    ip: settings.deviceIP,
                    name: name,
                    sleepDuration: sleepDurationSeconds,
                    maxIdle: maxIdleSeconds,
                    idxWakeSens: wakeSensitivity
                )
            }
            let info = try await client.fetchDeviceInfo(ip: settings.deviceIP)
            applyDeviceInfo(info)
            statusText = "Device settings updated."
        } catch {
            statusText = "Couldn't update device settings: \(error.localizedDescription)"
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
                currentImageData = data
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
            currentImageData = data
            currentImagePath = path
            currentGalleryOnDevice = picked.gallery
            statusText = statusMessage
        } catch {
            statusText = "Couldn't show a random photo: \(error.localizedDescription)"
        }
    }

    /// Generates a fresh image from one of the checked content sources
    /// (chosen at random if more than one is checked), uploads it to that
    /// source's own gallery (matching whatever the original Python scripts
    /// already used, e.g. "NASA" for APOD), and displays it immediately.
    func showRandomGeneratedContent() async {
        let sources = ContentSources.all.filter { settings.selectedContentSources.contains($0.id) }
        guard let source = sources.randomElement() else {
            statusText = "Select at least one content source."
            return
        }
        isBusy = true
        defer { isBusy = false }
        do {
            let info = try await withWakeRetry { try await client.fetchDeviceInfo(ip: settings.deviceIP) }
            applyDeviceInfo(info)

            statusText = "Generating \(source.displayName)..."
            let imageData = try await source.generateImage(settings: settings)

            await client.ensureGallery(ip: settings.deviceIP, name: source.galleryName)
            let filename = "\(source.id)_\(Int(Date().timeIntervalSince1970)).jpg"
            let path = try await client.uploadImage(
                ip: settings.deviceIP,
                filename: filename,
                gallery: source.galleryName,
                imageData: imageData,
                showNow: true
            )

            previewImage = NSImage(data: imageData)
            currentImageData = imageData
            currentImagePath = path
            currentGalleryOnDevice = source.galleryName
            statusText = "Showed \(source.displayName)."

            // Pick up the source's gallery in the picker in case it's new.
            await loadGalleries()
        } catch {
            statusText = "Couldn't generate \(source.displayName): \(error.localizedDescription)"
        }
    }

    private static let imageFileExtensions: Set<String> = ["jpg", "jpeg", "png", "heic", "gif", "bmp", "tiff", "tif", "webp"]

    /// Picks a random image from the local folder in Settings and uploads it
    /// to a "Random" gallery on the frame. That gallery is meant to hold
    /// exactly one photo at a time, so whatever's already in it is deleted
    /// first rather than left to accumulate.
    func showRandomLocalFolderPhoto() async {
        let folderPath = settings.randomFolderPath.trimmingCharacters(in: .whitespaces)
        guard !folderPath.isEmpty else {
            statusText = "Choose a folder to pick random photos from."
            return
        }
        let folderURL = URL(fileURLWithPath: folderPath, isDirectory: true)
        guard let chosen = enumerateImageFiles(in: folderURL).randomElement() else {
            statusText = "No photos found in '\(folderURL.lastPathComponent)'."
            return
        }
        guard let sourceData = try? Data(contentsOf: chosen),
              let image = NSImage(data: sourceData),
              let jpeg = ImageCanvas.jpegData(image)
        else {
            statusText = "Couldn't read '\(chosen.lastPathComponent)'."
            return
        }

        isBusy = true
        defer { isBusy = false }
        do {
            let info = try await withWakeRetry { try await client.fetchDeviceInfo(ip: settings.deviceIP) }
            applyDeviceInfo(info)

            let gallery = "Random"
            await client.ensureGallery(ip: settings.deviceIP, name: gallery)

            let existing = try await client.fetchAllImages(ip: settings.deviceIP, gallery: gallery)
            var deleteFailures = 0
            for name in existing {
                do {
                    try await client.deleteImage(ip: settings.deviceIP, filename: name, gallery: gallery)
                } catch {
                    deleteFailures += 1
                }
            }

            let filename = "\(chosen.deletingPathExtension().lastPathComponent)_\(Int(Date().timeIntervalSince1970)).jpg"
            let path = try await client.uploadImage(ip: settings.deviceIP, filename: filename, gallery: gallery, imageData: jpeg, showNow: true)

            previewImage = NSImage(data: jpeg)
            currentImageData = jpeg
            currentImagePath = path
            currentGalleryOnDevice = gallery
            let deleteWarning = deleteFailures > 0 ? " (\(deleteFailures) old photo\(deleteFailures == 1 ? "" : "s") couldn't be removed)" : ""
            statusText = "Showed '\(chosen.lastPathComponent)' from local folder.\(deleteWarning)"

            await loadGalleries()
        } catch {
            statusText = "Couldn't show a random local photo: \(error.localizedDescription)"
        }
    }

    private func enumerateImageFiles(in folder: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var files: [URL] = []
        for case let url as URL in enumerator where Self.imageFileExtensions.contains(url.pathExtension.lowercased()) {
            files.append(url)
        }
        return files
    }
}
