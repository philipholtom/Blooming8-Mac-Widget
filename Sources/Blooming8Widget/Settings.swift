import Foundation
import Combine

enum RandomWeighting: String, CaseIterable, Identifiable {
    case perPhoto
    case perGallery

    var id: String { rawValue }

    var label: String {
        switch self {
        case .perPhoto: return "Photo"
        case .perGallery: return "Gallery"
        }
    }
}

enum AutoRandomInterval: String, CaseIterable, Identifiable {
    case hourly
    case daily

    var id: String { rawValue }

    var label: String {
        switch self {
        case .hourly: return "Every Hour"
        case .daily: return "Daily"
        }
    }
}

final class Settings: ObservableObject {
    @Published var deviceIP: String {
        didSet { UserDefaults.standard.set(deviceIP, forKey: "deviceIP") }
    }
    @Published var selectedGalleries: Set<String> {
        didSet { UserDefaults.standard.set(Array(selectedGalleries), forKey: "selectedGalleries") }
    }
    @Published var randomWeighting: RandomWeighting {
        didSet { UserDefaults.standard.set(randomWeighting.rawValue, forKey: "randomWeighting") }
    }
    @Published var bleDeviceName: String {
        didSet { UserDefaults.standard.set(bleDeviceName, forKey: "bleDeviceName") }
    }
    @Published var tabs: [GalleryTab] {
        didSet {
            if let data = try? JSONEncoder().encode(tabs) {
                UserDefaults.standard.set(data, forKey: "galleryTabs")
            }
        }
    }
    @Published var autoRandomEnabled: Bool {
        didSet { UserDefaults.standard.set(autoRandomEnabled, forKey: "autoRandomEnabled") }
    }
    @Published var autoRandomInterval: AutoRandomInterval {
        didSet { UserDefaults.standard.set(autoRandomInterval.rawValue, forKey: "autoRandomInterval") }
    }
    /// Minutes since midnight (local time), only used when autoRandomInterval == .daily.
    @Published var autoRandomDailyMinute: Int {
        didSet { UserDefaults.standard.set(autoRandomDailyMinute, forKey: "autoRandomDailyMinute") }
    }
    /// NASA APOD API key. Defaults to NASA's public shared demo key (rate-limited);
    /// stored locally only, never committed to the repo.
    @Published var nasaApiKey: String {
        didSet { UserDefaults.standard.set(nasaApiKey, forKey: "nasaApiKey") }
    }
    @Published var selectedContentSources: Set<String> {
        didSet { UserDefaults.standard.set(Array(selectedContentSources), forKey: "selectedContentSources") }
    }

    init() {
        deviceIP = UserDefaults.standard.string(forKey: "deviceIP") ?? ""
        if let stored = UserDefaults.standard.stringArray(forKey: "selectedGalleries") {
            selectedGalleries = Set(stored)
        } else if let legacy = UserDefaults.standard.string(forKey: "selectedGallery"), !legacy.isEmpty {
            // Migrate from the old single-gallery setting.
            selectedGalleries = [legacy]
        } else {
            selectedGalleries = []
        }
        if let raw = UserDefaults.standard.string(forKey: "randomWeighting"),
           let weighting = RandomWeighting(rawValue: raw) {
            randomWeighting = weighting
        } else {
            randomWeighting = .perPhoto
        }
        // Defaults to "Office" — the BLE name your existing NASA APOD Frame
        // script uses to wake this same frame (same IP, confirmed working).
        bleDeviceName = UserDefaults.standard.string(forKey: "bleDeviceName") ?? "Office"

        if let data = UserDefaults.standard.data(forKey: "galleryTabs"),
           let decoded = try? JSONDecoder().decode([GalleryTab].self, from: data) {
            tabs = decoded
        } else {
            tabs = []
        }

        autoRandomEnabled = UserDefaults.standard.bool(forKey: "autoRandomEnabled")
        if let raw = UserDefaults.standard.string(forKey: "autoRandomInterval"),
           let interval = AutoRandomInterval(rawValue: raw) {
            autoRandomInterval = interval
        } else {
            autoRandomInterval = .hourly
        }
        if UserDefaults.standard.object(forKey: "autoRandomDailyMinute") != nil {
            autoRandomDailyMinute = UserDefaults.standard.integer(forKey: "autoRandomDailyMinute")
        } else {
            autoRandomDailyMinute = 9 * 60 // 9:00 AM default
        }

        nasaApiKey = UserDefaults.standard.string(forKey: "nasaApiKey") ?? "DEMO_KEY"
        if let stored = UserDefaults.standard.stringArray(forKey: "selectedContentSources") {
            selectedContentSources = Set(stored)
        } else {
            selectedContentSources = []
        }
    }
}
