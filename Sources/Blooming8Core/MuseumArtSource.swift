import AppKit

/// A random public-domain painting from the Metropolitan Museum of Art's
/// open-access collection — no API key needed. Search first for object IDs
/// (that endpoint doesn't include images), then fetch a random one's detail
/// to get the actual image, retrying if that particular object turns out to
/// have no public-domain image after all — the search's `hasImages` filter
/// isn't perfectly reliable in practice.
public struct MuseumArtSource: ContentSource {
    public init() {}

    public let id = "museumArt"
    public let displayName = "Museum Art"
    public let galleryName = "Museum"

    private let width = 1200
    private let height = 1600

    private struct SearchResponse: Decodable {
        let objectIDs: [Int]?
    }

    private struct ObjectDetail: Decodable {
        let title: String
        let artistDisplayName: String
        let primaryImage: String
        let isPublicDomain: Bool
    }

    public func generateImage(settings: AppSettings) async throws -> Data {
        // A handful of broad, reliably-populated query terms — the search
        // endpoint requires some query, there's no "browse everything".
        let query = ["painting", "landscape", "portrait", "still life", "watercolor"].randomElement() ?? "painting"
        var searchComponents = URLComponents(string: "https://collectionapi.metmuseum.org/public/collection/v1/search")!
        searchComponents.queryItems = [
            URLQueryItem(name: "hasImages", value: "true"),
            URLQueryItem(name: "q", value: query)
        ]
        let (searchData, searchResponse) = try await URLSession.shared.data(from: searchComponents.url!)
        guard let http = searchResponse as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ContentSourceError.message("Met Museum search returned an error")
        }
        let ids = try JSONDecoder().decode(SearchResponse.self, from: searchData).objectIDs ?? []
        guard !ids.isEmpty else {
            throw ContentSourceError.message("No Met Museum results for '\(query)'")
        }

        var lastError: Error = ContentSourceError.message("Couldn't find a public-domain image")
        for objectID in ids.shuffled().prefix(6) {
            do {
                let detailURL = URL(string: "https://collectionapi.metmuseum.org/public/collection/v1/objects/\(objectID)")!
                let (detailData, detailResponse) = try await URLSession.shared.data(from: detailURL)
                guard let http = detailResponse as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { continue }
                let object = try JSONDecoder().decode(ObjectDetail.self, from: detailData)
                guard object.isPublicDomain, !object.primaryImage.isEmpty, let imageURL = URL(string: object.primaryImage) else {
                    continue
                }

                let (imageData, _) = try await URLSession.shared.data(from: imageURL)
                guard let cgImage = loadUprightCGImage(data: imageData) else { continue }
                guard let framed = renderLetterboxed(cgImage: cgImage, width: width, height: height, background: .black) else {
                    continue
                }

                let caption = object.artistDisplayName.isEmpty ? object.title : "\(object.title) — \(object.artistDisplayName)"
                let finalImage = ImageCanvas.render(width: width, height: height) {
                    drawImage(framed, in: NSRect(x: 0, y: 0, width: width, height: height))
                    let font = NSFont(name: "Helvetica", size: 16) ?? NSFont.systemFont(ofSize: 16)
                    let wrapped = wrapText(caption, maxCharsPerLine: 60, maxLines: 2)
                    var y = CGFloat(height) - CGFloat(wrapped.count) * 20 - 16
                    for line in wrapped {
                        drawCentered(line, font: font, color: .white, y: y, canvasWidth: width)
                        y += 20
                    }
                }
                if let finalImage, let jpeg = ImageCanvas.jpegData(finalImage) {
                    return jpeg
                }
            } catch {
                lastError = error
            }
        }
        throw lastError
    }
}
