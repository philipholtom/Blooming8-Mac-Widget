import Foundation

/// A generator that produces a fresh 1200x1600 JPEG to push to the frame,
/// as opposed to picking an existing photo from an on-device gallery.
protocol ContentSource {
    var id: String { get }
    var displayName: String { get }
    func generateImage(settings: Settings) async throws -> Data
}

enum ContentSourceError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let text): return text
        }
    }
}

enum ContentSources {
    static let all: [ContentSource] = [APODSource(), FortuneSource()]
}
