import Foundation
import AppKit

/// Recursive image-file discovery on the local disk, shared by the widget's
/// random picker and the app's folder browser.
public enum ImageFolder {
    public static let imageFileExtensions: Set<String> = [
        "jpg", "jpeg", "png", "heic", "gif", "bmp", "tiff", "tif", "webp"
    ]

    /// Walks `folder` recursively and returns every image file found. Skips
    /// hidden files and package contents (an .app or .photoslibrary would
    /// otherwise contribute thousands of irrelevant images).
    ///
    /// Blocking and potentially slow over tens of thousands of files, so call
    /// it off the main thread — it is `nonisolated` precisely so callers can.
    public static func enumerateImages(in folder: URL) -> [URL] {
        let keys: [URLResourceKey] = [.isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(
            at: folder,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var urls: [URL] = []
        for case let url as URL in enumerator
        where imageFileExtensions.contains(url.pathExtension.lowercased()) {
            urls.append(url)
        }
        return urls
    }
}

/// Bounded, off-main-thread thumbnail cache for grids over large image sets.
///
/// Decoding a full-size photo costs tens of milliseconds; a grid scrolling
/// through thousands of them has to decode small and decode once, or it
/// stutters badly. Keyed by path plus pixel size so the same file can be
/// cached at more than one size.
public actor ThumbnailStore {
    public static let shared = ThumbnailStore()

    private let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 600
        return cache
    }()

    /// In-flight loads, so a cell that scrolls off and back on doesn't kick
    /// off a second decode of the same file.
    private var inFlight: [String: Task<NSImage?, Never>] = [:]

    public init() {}

    public func thumbnail(for url: URL, maxPixelSize: Int = 320) async -> NSImage? {
        let key = "\(url.path)#\(maxPixelSize)"
        if let cached = cache.object(forKey: key as NSString) { return cached }
        if let existing = inFlight[key] { return await existing.value }

        let task = Task<NSImage?, Never>.detached(priority: .utility) {
            guard let cgImage = loadUprightCGImage(at: url, maxPixelSize: maxPixelSize) else { return nil }
            return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        }
        inFlight[key] = task
        let image = await task.value
        inFlight[key] = nil
        if let image { cache.setObject(image, forKey: key as NSString) }
        return image
    }

    public func clear() {
        cache.removeAllObjects()
    }
}
