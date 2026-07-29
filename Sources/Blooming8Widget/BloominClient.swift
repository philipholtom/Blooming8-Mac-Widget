import Foundation

struct DeviceInfo: Decodable {
    let name: String?
    let image: String?
    let gallery: String?
    let battery: Int?
    let sleepDuration: Int?
    let maxIdle: Int?
    let idxWakeSens: Int?

    enum CodingKeys: String, CodingKey {
        case name, image, gallery, battery
        case sleepDuration = "sleep_duration"
        case maxIdle = "max_idle"
        case idxWakeSens = "idx_wake_sens"
    }
}

struct GalleryEntry: Decodable {
    let name: String
}

struct GalleryImage: Decodable {
    let name: String
}

struct GalleryListing: Decodable {
    let data: [GalleryImage]
    let cursorNext: String?
    let more: Bool?

    enum CodingKeys: String, CodingKey {
        case data
        case cursorNext = "cursor_next"
        case more
    }
}

enum BloominError: LocalizedError {
    case noDeviceIP
    case badResponse(String)
    case http(Int)
    case busy(String)

    var errorDescription: String? {
        switch self {
        case .noDeviceIP:
            return "Set the frame's IP address first."
        case .badResponse(let detail):
            return "Unexpected response: \(detail)"
        case .http(let code):
            return "Frame returned HTTP \(code)."
        case .busy(let reason):
            return "Frame is busy (\(reason))."
        }
    }
}

final class BloominClient {
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 15
        session = URLSession(configuration: config)
    }

    private func baseURL(ip: String) throws -> String {
        guard !ip.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw BloominError.noDeviceIP
        }
        return "http://\(ip.trimmingCharacters(in: .whitespaces))"
    }

    func fetchDeviceInfo(ip: String) async throws -> DeviceInfo {
        let url = try URL(string: baseURL(ip: ip) + "/deviceInfo")!
        let (data, response) = try await session.data(from: url)
        try checkStatus(response)
        return try JSONDecoder().decode(DeviceInfo.self, from: data)
    }

    func fetchGalleryList(ip: String) async throws -> [String] {
        let url = try URL(string: baseURL(ip: ip) + "/gallery/list")!
        let (data, response) = try await session.data(from: url)
        try checkStatus(response)
        let entries = try JSONDecoder().decode([GalleryEntry].self, from: data)
        return entries.map { $0.name }
    }

    /// Fetches every image in a gallery by walking the device's cursor-based
    /// pagination (`full=1`). The cursor from one page's `cursor_next` is
    /// fed back in via a `cursor` query parameter (undocumented, found by
    /// probing the device directly) to fetch the next page.
    func fetchAllImages(ip: String, gallery: String) async throws -> [String] {
        var allNames: [String] = []
        var seen = Set<String>()
        var cursor: String? = nil
        var pageCount = 0
        let maxPages = 200 // safety cap: ~10,000 images at 51/page

        while pageCount < maxPages {
            pageCount += 1
            var components = URLComponents(string: try baseURL(ip: ip) + "/gallery")!
            var queryItems = [
                URLQueryItem(name: "gallery_name", value: gallery),
                URLQueryItem(name: "offset", value: "0"),
                URLQueryItem(name: "limit", value: "51"),
                URLQueryItem(name: "full", value: "1")
            ]
            if let cursor {
                queryItems.append(URLQueryItem(name: "cursor", value: cursor))
            }
            components.queryItems = queryItems
            let (data, response) = try await session.data(from: components.url!)
            try checkStatus(response)
            let listing = try JSONDecoder().decode(GalleryListing.self, from: data)

            let newNames = listing.data.map { $0.name }.filter { !seen.contains($0) }
            if newNames.isEmpty { break }
            newNames.forEach { seen.insert($0) }
            allNames.append(contentsOf: newNames)

            guard listing.more == true, let next = listing.cursorNext, next != cursor else {
                break
            }
            cursor = next
        }
        return allNames
    }

    private struct ShowResponse: Decodable {
        let status: String?
        let msg: String?
    }

    /// The frame can reject a /show call while it's still drawing the
    /// previous one — observed both as HTTP 500 and, inconsistently, as
    /// HTTP 200 with `{"status":"fail","msg":"DRAWING"}` in the body. Check
    /// both shapes so callers can reliably detect and retry on this.
    func show(ip: String, imagePath: String) async throws {
        let url = try URL(string: baseURL(ip: ip) + "/show")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["play_type": 0, "image": imagePath]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request)
        let decoded = try? JSONDecoder().decode(ShowResponse.self, from: data)
        if decoded?.status == "fail" {
            throw BloominError.busy(decoded?.msg ?? "unknown reason")
        }
        try checkStatus(response)
    }

    /// Immediately displays the next image in the frame's current playback
    /// queue (only meaningful when it's in gallery-slideshow or playlist
    /// mode, not single-image mode).
    func showNext(ip: String) async throws {
        let url = try URL(string: baseURL(ip: ip) + "/showNext")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let (_, response) = try await session.data(for: request)
        try checkStatus(response)
    }

    /// Starts a gallery slideshow: cycles through `gallery`'s images every
    /// `durationSeconds`, advancing automatically on-device.
    func startSlideshow(ip: String, gallery: String, durationSeconds: Int) async throws {
        let url = try URL(string: baseURL(ip: ip) + "/show")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["play_type": 1, "gallery": gallery, "duration": durationSeconds]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (_, response) = try await session.data(for: request)
        try checkStatus(response)
    }

    /// Stops slideshow/playlist playback, returning to single-image mode.
    func stopPlayback(ip: String) async throws {
        let url = try URL(string: baseURL(ip: ip) + "/stop")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let (_, response) = try await session.data(for: request)
        try checkStatus(response)
    }

    /// Updates device-level settings. Only non-nil fields are sent, so a
    /// call can touch just the name, just the sleep timers, or all of them.
    func updateSettings(ip: String, name: String? = nil, sleepDuration: Int? = nil, maxIdle: Int? = nil, idxWakeSens: Int? = nil) async throws {
        let url = try URL(string: baseURL(ip: ip) + "/settings")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = [:]
        if let name { body["name"] = name }
        if let sleepDuration { body["sleep_duration"] = sleepDuration }
        if let maxIdle { body["max_idle"] = maxIdle }
        if let idxWakeSens { body["idx_wake_sens"] = idxWakeSens }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (_, response) = try await session.data(for: request)
        try checkStatus(response)
    }

    func fetchImageData(ip: String, path: String) async throws -> Data {
        let url = try URL(string: baseURL(ip: ip) + path)!
        let (data, response) = try await session.data(from: url)
        try checkStatus(response)
        return data
    }

    /// Best-effort: creates a gallery if it doesn't already exist. Ignores
    /// failure (e.g. it already exists) since this is purely a convenience
    /// to keep generated content out of the user's own galleries.
    func ensureGallery(ip: String, name: String) async {
        guard var components = try? URLComponents(string: baseURL(ip: ip) + "/gallery") else { return }
        components.queryItems = [URLQueryItem(name: "name", value: name)]
        guard let url = components.url else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        _ = try? await session.data(for: request)
    }

    private struct UploadResponse: Decodable {
        let path: String
    }

    /// Uploads a JPEG to a gallery and, if `showNow`, displays it immediately.
    /// Returns the stored path on the device (e.g. `/gallerys/{gallery}/{filename}`).
    func uploadImage(ip: String, filename: String, gallery: String, imageData: Data, showNow: Bool) async throws -> String {
        var components = URLComponents(string: try baseURL(ip: ip) + "/upload")!
        components.queryItems = [
            URLQueryItem(name: "filename", value: filename),
            URLQueryItem(name: "gallery", value: gallery),
            URLQueryItem(name: "show_now", value: showNow ? "1" : "0")
        ]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"

        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"image\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        let (data, response) = try await session.data(for: request)
        try checkStatus(response)
        return try JSONDecoder().decode(UploadResponse.self, from: data).path
    }

    private func checkStatus(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw BloominError.badResponse("no HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw BloominError.http(http.statusCode)
        }
    }
}
