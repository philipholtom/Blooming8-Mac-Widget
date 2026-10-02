import Foundation

/// A generator that produces a fresh 1200x1600 JPEG to push to the frame,
/// as opposed to picking an existing photo from an on-device gallery.
public protocol ContentSource {
    var id: String { get }
    var displayName: String { get }
    /// The on-device gallery this source's images are uploaded into —
    /// matches the galleries the original Python scripts already used
    /// (e.g. "NASA" for APOD), so generated content lands alongside
    /// whatever they already uploaded there rather than a new catch-all.
    var galleryName: String { get }
    func generateImage(settings: AppSettings) async throws -> Data
}

/// A source that can also produce "today's" item, not only a random one — for
/// APOD, the actual picture of the day. The picker offers it as a button, and
/// scheduled auto-show uses it instead of a random date.
public protocol TodayContentSource: ContentSource {
    var todayButtonTitle: String { get }
    func generateTodayImage(settings: AppSettings) async throws -> Data
}

public enum ContentSourceError: LocalizedError {
    case message(String)

    public var errorDescription: String? {
        switch self {
        case .message(let text): return text
        }
    }
}

/// Wikimedia's API etiquette requires a descriptive User-Agent — the
/// original Python scripts embedded a personal name/email, which doesn't
/// belong in a public repo, so this identifies the app instead.
public let contentSourceUserAgent = "Blooming8Widget/1.0 (+https://github.com/philipholtom/Blooming8-Mac-Widget)"

public enum ContentSources {
    public static let all: [ContentSource] = [
        APODSource(),
        FortuneSource(),
        WeatherSource(),
        MoonPhaseSource(),
        HistorySource(),
        PeriodicTableSource(),
        MarsRoverSource(),
        EPICSource(),
        MuseumArtSource(),
        WikipediaPOTDSource(),
        CatPhotoSource(),
        DogPhotoSource(),
        SatelliteMapSource()
    ]
}
