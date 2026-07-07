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
    }
}
