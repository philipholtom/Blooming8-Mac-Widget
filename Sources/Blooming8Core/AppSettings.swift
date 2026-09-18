import Foundation
import Combine
import os

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
    /// `Bundle.main.bundleIdentifier`, not a hardcoded string: this file is
    /// shared by both products, so the subsystem needs to resolve to
    /// whichever one is actually running for `log stream` filtering to
    /// mean anything (unlike BLEWaker, which hardcodes the widget's
    /// subsystem even though it's shared code too — a pre-existing
    /// inconsistency, not a pattern worth repeating here).
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.pholtom.blooming8", category: "keychain")

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
            // Password hashes live in Keychain, not in this JSON blob (see
            // GalleryTab's custom Codable) — keep Keychain in sync here,
            // in the one place tabs actually change, rather than scattering
            // writes across every call site that mutates a tab's password.
            for tab in tabs {
                let account = GalleryTab.keychainAccount(for: tab.id)
                if let hash = tab.passwordHash {
                    KeychainStore.write(hash, account: account)
                } else {
                    KeychainStore.delete(account: account)
                }
            }
            // A tab that existed in oldValue but not anymore (deleted) would
            // otherwise leave its Keychain entry orphaned forever.
            let currentIDs = Set(tabs.map(\.id))
            for removed in oldValue where !currentIDs.contains(removed.id) {
                KeychainStore.delete(account: GalleryTab.keychainAccount(for: removed.id))
            }
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

    /// Hash of the Local Folder password (nil if not locked). Lives in
    /// Keychain, not this UserDefaults suite — the suite's own doc comment
    /// above explains why it can't have real access-group protection
    /// (no App Groups entitlement without a paid Developer ID), which is
    /// exactly why a password hash shouldn't sit in it as plain text.
    @Published public var localFolderPasswordHash: String? {
        didSet {
            if let localFolderPasswordHash {
                KeychainStore.write(localFolderPasswordHash, account: Self.localFolderPasswordAccount)
            } else {
                KeychainStore.delete(account: Self.localFolderPasswordAccount)
            }
        }
    }

    private static let localFolderPasswordAccount = "localFolderPasswordHash"

    /// Bearer token for the frame's separate remote-push relay API
    /// ("einkshot" — see `EinkshotClient`), for sending a photo over the
    /// internet rather than the local network. Lives in Keychain under the
    /// same service `KeychainStore` already uses for password hashes, and
    /// the same account name a one-off `security add-generic-password` used
    /// before this settings field existed — so a token set that way already
    /// shows up here without needing to be re-entered.
    @Published public var einkshotToken: String? {
        didSet {
            if let einkshotToken, !einkshotToken.trimmingCharacters(in: .whitespaces).isEmpty {
                KeychainStore.write(einkshotToken, account: Self.einkshotTokenAccount)
            } else {
                KeychainStore.delete(account: Self.einkshotTokenAccount)
            }
        }
    }

    private static let einkshotTokenAccount = "einkshotDeviceToken"

    /// When true, unlock prompts (gallery tabs, Local Folder/Favorites) try
    /// Touch ID first and only fall back to the password field if it's
    /// unavailable or fails. The password stays the real secret either way —
    /// this only changes whether biometrics offer a faster path to it.
    @Published public var useTouchIDForLocks: Bool {
        didSet { defaults.set(useTouchIDForLocks, forKey: "useTouchIDForLocks") }
    }

    /// One photo scheduled to send at a fixed time on chosen days — see
    /// `ScheduledSend`. Persisted as JSON, same pattern as `tabs`, since it's
    /// a single struct rather than a UserDefaults-primitive value.
    @Published public var scheduledSend: ScheduledSend? {
        didSet {
            if let scheduledSend, let data = try? JSONEncoder().encode(scheduledSend) {
                defaults.set(data, forKey: "scheduledSend")
            } else {
                defaults.removeObject(forKey: "scheduledSend")
            }
        }
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
        if let fromKeychain = KeychainStore.read(account: Self.localFolderPasswordAccount) {
            Self.log.notice("localFolderPasswordHash: read from Keychain")
            localFolderPasswordHash = fromKeychain
        } else if let legacy = defaults.string(forKey: "localFolderPasswordHash") {
            // One-time migration: this was sitting in the shared
            // UserDefaults suite as plain text before password hashes
            // moved to Keychain.
            Self.log.notice("localFolderPasswordHash: migrating legacy UserDefaults value into Keychain")
            KeychainStore.write(legacy, account: Self.localFolderPasswordAccount)
            defaults.removeObject(forKey: "localFolderPasswordHash")
            localFolderPasswordHash = legacy
        } else {
            localFolderPasswordHash = nil
        }
        useTouchIDForLocks = defaults.bool(forKey: "useTouchIDForLocks")
        einkshotToken = KeychainStore.read(account: Self.einkshotTokenAccount)
        if let data = defaults.data(forKey: "scheduledSend"),
           let decoded = try? JSONDecoder().decode(ScheduledSend.self, from: data) {
            scheduledSend = decoded
        } else {
            scheduledSend = nil
        }

        // `tabs`'s own didSet (which re-encodes without passwordHash, now
        // that it's migrated into Keychain during decode above — see
        // GalleryTab.init(from:)) does NOT fire for the assignment above:
        // Swift skips property observers when a property is set inside its
        // own initializer. Without this, a tab whose hash just migrated
        // out of the decoded blob would sit there completely unchanged,
        // legacy hash and all, until something unrelated happened to
        // touch `tabs` again — possibly never. Redone here, now that every
        // stored property (including `defaults` and `tabs` itself) is set
        // and `self` can be used.
        if let data = try? JSONEncoder().encode(tabs) {
            defaults.set(data, forKey: "galleryTabs")
        }
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
            "localFolderLocked", "localFolderPasswordHash", "useTouchIDForLocks"
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
