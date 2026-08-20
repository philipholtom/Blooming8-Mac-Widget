import Foundation
import Combine

public enum RandomWeighting: String, CaseIterable, Identifiable {
    case perPhoto
    case perGallery

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .perPhoto: return "Photo"
        case .perGallery: return "Gallery"
        }
    }
}

public enum AutoRandomInterval: String, CaseIterable, Identifiable {
    case hourly
    case daily

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .hourly: return "Every Hour"
        case .daily: return "Daily"
        }
    }
}

public final class AppSettings: ObservableObject {
    /// Both products read and write one store, so the frame IP, tabs,
    /// favorites and passwords stay in sync no matter which one you configure.
    ///
    /// A plain suite name rather than a `group.*` App Group: real App Groups
    /// need the `com.apple.security.application-groups` entitlement, which in
    /// turn needs a Developer ID signing identity. Neither product is
    /// sandboxed, so a shared suite lands in
    /// ~/Library/Preferences/com.pholtom.blooming8.shared.plist and is
    /// readable by both without any entitlement.
    public static let suiteName = "com.pholtom.blooming8.shared"

    private let defaults: UserDefaults

    @Published public var deviceIP: String {
        didSet { defaults.set(deviceIP, forKey: "deviceIP") }
    }
    @Published public var selectedGalleries: Set<String> {
        didSet { defaults.set(Array(selectedGalleries), forKey: "selectedGalleries") }
    }
    @Published public var randomWeighting: RandomWeighting {
        didSet { defaults.set(randomWeighting.rawValue, forKey: "randomWeighting") }
    }
    @Published public var bleDeviceName: String {
        didSet { defaults.set(bleDeviceName, forKey: "bleDeviceName") }
    }
    @Published public var tabs: [GalleryTab] {
        didSet {
            if let data = try? JSONEncoder().encode(tabs) {
                defaults.set(data, forKey: "galleryTabs")
            }
        }
    }
    @Published public var autoRandomEnabled: Bool {
        didSet { defaults.set(autoRandomEnabled, forKey: "autoRandomEnabled") }
    }
    @Published public var autoRandomInterval: AutoRandomInterval {
        didSet { defaults.set(autoRandomInterval.rawValue, forKey: "autoRandomInterval") }
    }
    /// Minutes since midnight (local time), only used when autoRandomInterval == .daily.
    @Published public var autoRandomDailyMinute: Int {
        didSet { defaults.set(autoRandomDailyMinute, forKey: "autoRandomDailyMinute") }
    }
    /// NASA APOD API key. Defaults to NASA's public shared demo key (rate-limited);
    /// stored locally only, never committed to the repo.
    @Published public var nasaApiKey: String {
        didSet { defaults.set(nasaApiKey, forKey: "nasaApiKey") }
    }
    @Published public var selectedContentSources: Set<String> {
        didSet { defaults.set(Array(selectedContentSources), forKey: "selectedContentSources") }
    }
    @Published public var weatherLocationName: String {
        didSet { defaults.set(weatherLocationName, forKey: "weatherLocationName") }
    }
    @Published public var weatherLatitude: Double {
        didSet { defaults.set(weatherLatitude, forKey: "weatherLatitude") }
    }
    @Published public var weatherLongitude: Double {
        didSet { defaults.set(weatherLongitude, forKey: "weatherLongitude") }
    }
    /// The year format_history_text/create_history_art always surfaces first
    /// if present — a personal touch from the original script (likely a
    /// birth year), kept configurable rather than silently hardcoded.
    @Published public var historyHighlightYear: Int {
        didSet { defaults.set(historyHighlightYear, forKey: "historyHighlightYear") }
    }
    /// A folder on this Mac to pick random photos from for the "Local Folder"
    /// tab. Stored as a plain path — the app isn't sandboxed, so no
    /// security-scoped bookmark is needed to keep reading it after relaunch.
    @Published public var randomFolderPath: String {
        didSet { defaults.set(randomFolderPath, forKey: "randomFolderPath") }
    }

    /// When true, a landscape source photo is cropped and centered to fill
    /// the frame's portrait canvas instead of being letterboxed. Portrait and
    /// square sources are unaffected either way — they don't have the "tiny
    /// photo between two black bars" problem this exists to fix.
    @Published public var cropLandscapePhotos: Bool {
        didSet { defaults.set(cropLandscapePhotos, forKey: "cropLandscapePhotos") }
    }

    /// List of favorite image file paths marked by the user.
    @Published public var favoriteImagePaths: [String] {
        didSet { defaults.set(favoriteImagePaths, forKey: "favoriteImagePaths") }
    }

    /// Whether the Local Folder tab is password protected.
    @Published public var localFolderLocked: Bool {
        didSet { defaults.set(localFolderLocked, forKey: "localFolderLocked") }
    }

    /// Hash of the Local Folder password (nil if not locked).
    @Published public var localFolderPasswordHash: String? {
        didSet { defaults.set(localFolderPasswordHash, forKey: "localFolderPasswordHash") }
    }

    public convenience init() {
        self.init(defaults: UserDefaults(suiteName: AppSettings.suiteName) ?? .standard)
    }

    public init(defaults: UserDefaults) {
        self.defaults = defaults
        AppSettings.migrateLegacyDefaultsIfNeeded(into: defaults)
        deviceIP = defaults.string(forKey: "deviceIP") ?? ""
        if let stored = defaults.stringArray(forKey: "selectedGalleries") {
            selectedGalleries = Set(stored)
        } else if let legacy = defaults.string(forKey: "selectedGallery"), !legacy.isEmpty {
            // Migrate from the old single-gallery setting.
            selectedGalleries = [legacy]
        } else {
            selectedGalleries = []
        }
        if let raw = defaults.string(forKey: "randomWeighting"),
           let weighting = RandomWeighting(rawValue: raw) {
            randomWeighting = weighting
        } else {
            randomWeighting = .perPhoto
        }
        // Defaults to "Office" — the BLE name your existing NASA APOD Frame
        // script uses to wake this same frame (same IP, confirmed working).
        bleDeviceName = defaults.string(forKey: "bleDeviceName") ?? "Office"

        if let data = defaults.data(forKey: "galleryTabs"),
           let decoded = try? JSONDecoder().decode([GalleryTab].self, from: data) {
            tabs = decoded
        } else {
            tabs = []
        }

        autoRandomEnabled = defaults.bool(forKey: "autoRandomEnabled")
        if let raw = defaults.string(forKey: "autoRandomInterval"),
           let interval = AutoRandomInterval(rawValue: raw) {
            autoRandomInterval = interval
        } else {
            autoRandomInterval = .hourly
        }
        if defaults.object(forKey: "autoRandomDailyMinute") != nil {
            autoRandomDailyMinute = defaults.integer(forKey: "autoRandomDailyMinute")
        } else {
            autoRandomDailyMinute = 9 * 60 // 9:00 AM default
        }

        nasaApiKey = defaults.string(forKey: "nasaApiKey") ?? "DEMO_KEY"
        if let stored = defaults.stringArray(forKey: "selectedContentSources") {
            selectedContentSources = Set(stored)
        } else {
            selectedContentSources = []
        }

        weatherLocationName = defaults.string(forKey: "weatherLocationName") ?? ""
        weatherLatitude = defaults.object(forKey: "weatherLatitude") != nil
            ? defaults.double(forKey: "weatherLatitude") : 0
        weatherLongitude = defaults.object(forKey: "weatherLongitude") != nil
            ? defaults.double(forKey: "weatherLongitude") : 0
        historyHighlightYear = defaults.object(forKey: "historyHighlightYear") != nil
            ? defaults.integer(forKey: "historyHighlightYear") : 1979
        randomFolderPath = defaults.string(forKey: "randomFolderPath") ?? ""
        cropLandscapePhotos = defaults.bool(forKey: "cropLandscapePhotos")
        favoriteImagePaths = defaults.stringArray(forKey: "favoriteImagePaths") ?? []
        localFolderLocked = defaults.bool(forKey: "localFolderLocked")
        localFolderPasswordHash = defaults.string(forKey: "localFolderPasswordHash")
    }

    /// The widget stored everything in the standard domain before the app
    /// existed. Copy that across on first run against the shared suite so an
    /// existing install doesn't come back up with a blank frame IP, no tabs
    /// and no favorites.
    private static func migrateLegacyDefaultsIfNeeded(into defaults: UserDefaults) {
        let marker = "didMigrateLegacyDefaults"
        guard !defaults.bool(forKey: marker) else { return }
        defaults.set(true, forKey: marker)

        let legacy = UserDefaults.standard
        let keys = [
            "deviceIP", "selectedGallery", "selectedGalleries", "randomWeighting",
            "bleDeviceName", "galleryTabs", "autoRandomEnabled", "autoRandomInterval",
            "autoRandomDailyMinute", "nasaApiKey", "selectedContentSources",
            "weatherLocationName", "weatherLatitude", "weatherLongitude",
            "historyHighlightYear", "randomFolderPath", "favoriteImagePaths",
            "localFolderLocked", "localFolderPasswordHash"
        ]
        for key in keys {
            guard let value = legacy.object(forKey: key) else { continue }
            defaults.set(value, forKey: key)
        }
    }
}

extension AppSettings {
    /// The tab a gallery belongs to that's still locked (its password hasn't
    /// been entered this session), if any. `unlockedTabIDs` lives on
    /// `PhotoController`, not here, since it's per-process runtime state,
    /// not a persisted setting — callers pass it in.
    public func lockedTab(for galleryName: String, unlockedTabIDs: Set<UUID>) -> GalleryTab? {
        tabs.first {
            $0.isLocked && !unlockedTabIDs.contains($0.id) && $0.galleryNames.contains(galleryName)
        }
    }
}
