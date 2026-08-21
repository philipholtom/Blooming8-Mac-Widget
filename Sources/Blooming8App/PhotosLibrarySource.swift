import AppKit
import Photos

/// Read-only access to the user's Photos library for the "Apple Photos"
/// sidebar entry: a flat list of image assets (newest first, no videos, no
/// album structure — see LibraryModel's `.applePhotos` case), plus
/// thumbnails and full-resolution exports on demand.
///
/// Kept out of Blooming8Core and app-only: the widget has no Photos browser
/// today, so there's no reason for it to carry a Photos framework
/// dependency too.
enum PhotosLibrarySource {
    /// Requests access if not yet decided, otherwise just reports the
    /// current status. `.readWrite` (not `.readOnly`) matches the frame's
    /// scope elsewhere: on macOS this doesn't grant anything the browser
    /// doesn't already need — it's the same one system prompt either way.
    static func requestAccess() async -> Bool {
        switch PHPhotoLibrary.authorizationStatus(for: .readWrite) {
        case .authorized, .limited:
            return true
        case .notDetermined:
            let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            return status == .authorized || status == .limited
        default:
            return false
        }
    }

    /// Every image asset in the library, newest first. `PHAsset.fetchAssets`
    /// is safe to call off the main thread — the caller runs this inside a
    /// detached task since even the fetch itself can take a moment against a
    /// large library.
    static func fetchAllImageAssets() -> [PHAsset] {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        let result = PHAsset.fetchAssets(with: options)
        var assets: [PHAsset] = []
        assets.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in assets.append(asset) }
        return assets
    }

    /// A short label for the grid caption, since assets don't reliably expose
    /// a filename without a separate, per-asset resource lookup — too costly
    /// to do for every cell in a library that can run into the thousands.
    /// The creation date is what Photos.app itself shows on hover, so this
    /// matches that convention rather than inventing a new one.
    static func displayName(for asset: PHAsset) -> String {
        guard let date = asset.creationDate else { return asset.localIdentifier }
        return dateFormatter.string(from: date)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    /// A grid-sized preview for `assetID`, downloading from iCloud if the
    /// original isn't stored on this Mac. `.highQualityFormat` delivers
    /// exactly once (unlike `.opportunistic`, which can call back twice —
    /// a fast low-res pass then a better one — and would need extra
    /// bookkeeping to safely resume a continuation only once).
    static func thumbnail(assetID: String, maxPixelSize: Int) async -> NSImage? {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil).firstObject else {
            return nil
        }
        let targetSize = CGSize(width: maxPixelSize, height: maxPixelSize)
        return await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = true
            options.isSynchronous = false
            PHImageManager.default().requestImage(
                for: asset, targetSize: targetSize, contentMode: .aspectFill, options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }

    /// The original image bytes for `assetID`, for Send to Frame — full
    /// resolution, orientation applied downstream by `loadUprightCGImage`.
    /// Downloads from iCloud if needed, so this can take longer than the
    /// thumbnail fetch above for a photo that isn't cached locally.
    static func fetchOriginalData(assetID: String) async -> Data? {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil).firstObject else {
            return nil
        }
        return await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            options.isSynchronous = false
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, _ in
                continuation.resume(returning: data)
            }
        }
    }
}

/// Bounded thumbnail cache for the Photos grid, mirroring `ThumbnailStore`/
/// `DeviceThumbnailStore` in Blooming8Core — same shape, kept as a separate
/// app-local type since it wraps `Photos` rather than a file path or an HTTP
/// fetch.
actor PhotosThumbnailStore {
    static let shared = PhotosThumbnailStore()

    private let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 600
        return cache
    }()

    private var inFlight: [String: Task<NSImage?, Never>] = [:]

    func thumbnail(assetID: String, maxPixelSize: Int = 320) async -> NSImage? {
        let key = "\(assetID)#\(maxPixelSize)"
        if let cached = cache.object(forKey: key as NSString) { return cached }
        if let existing = inFlight[key] { return await existing.value }

        let task = Task<NSImage?, Never> {
            await PhotosLibrarySource.thumbnail(assetID: assetID, maxPixelSize: maxPixelSize)
        }
        inFlight[key] = task
        let image = await task.value
        inFlight[key] = nil
        if let image { cache.setObject(image, forKey: key as NSString) }
        return image
    }
}
