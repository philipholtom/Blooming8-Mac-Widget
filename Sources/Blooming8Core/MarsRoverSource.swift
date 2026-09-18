import AppKit

/// Recent raw images from NASA's Mars rovers, via JPL's own raw-images feed
/// (mars.nasa.gov) rather than api.nasa.gov's "Mars Rover Photos" API —
/// confirmed directly that the latter is dead (its Heroku backend returns
/// "No such app"), while this one, JPL's own, is still live.
public struct MarsRoverSource: ContentSource {
    public init() {}

    public let id = "marsRover"
    public let displayName = "Mars Rover"
    public let galleryName = "Mars"

    private let width = 1200
    private let height = 1600

    private struct FeedResponse: Decodable {
        let images: [RawImage]
    }

    private struct RawImage: Decodable {
        let sol: Int
        let imageFiles: ImageFiles

        enum CodingKeys: String, CodingKey {
            case sol
            case imageFiles = "image_files"
        }

        struct ImageFiles: Decodable {
            let large: String?
            let mediumImage: String?
            enum CodingKeys: String, CodingKey {
                case large
                case mediumImage = "medium"
            }
        }
    }

    // Perseverance only — confirmed directly against the live API.
    // Curiosity's "msl" category is recognized (echoes "mission":"msl" in
    // the response) but always returns zero images ("No more images.",
    // total_images: 0), and no alternate slug for it (curiosity,
    // mars-science-laboratory, msl-raw-images, MSL) resolves either — its
    // raw images apparently live behind a different, undiscovered path.
    private static let rover = "mars2020"

    public func generateImage(settings: AppSettings) async throws -> Data {
        var components = URLComponents(string: "https://mars.nasa.gov/rss/api/")!
        components.queryItems = [
            URLQueryItem(name: "feed", value: "raw_images"),
            URLQueryItem(name: "category", value: Self.rover),
            URLQueryItem(name: "feedtype", value: "json"),
            URLQueryItem(name: "num", value: "50"),
            URLQueryItem(name: "page", value: "0")
        ]
        var request = URLRequest(url: components.url!)
        request.setValue(contentSourceUserAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ContentSourceError.message("Mars rover feed returned an error")
        }
        let feed = try JSONDecoder().decode(FeedResponse.self, from: data)
        let candidates = feed.images.filter { $0.imageFiles.large != nil || $0.imageFiles.mediumImage != nil }
        guard let picked = candidates.randomElement(),
              let urlString = picked.imageFiles.large ?? picked.imageFiles.mediumImage,
              let imageURL = URL(string: urlString)
        else {
            throw ContentSourceError.message("No usable images in the Mars rover feed")
        }

        let (imageData, _) = try await URLSession.shared.data(from: imageURL)
        guard let cgImage = loadUprightCGImage(data: imageData) else {
            throw ContentSourceError.message("Couldn't decode the Mars rover image")
        }
        guard let framed = renderLetterboxed(cgImage: cgImage, width: width, height: height, background: .black) else {
            throw ContentSourceError.message("Couldn't render the Mars rover image")
        }

        let caption = "Perseverance · Sol \(picked.sol)"
        let finalImage = ImageCanvas.render(width: width, height: height) {
            drawImage(framed, in: NSRect(x: 0, y: 0, width: width, height: height))
            let font = NSFont(name: "Helvetica-Bold", size: 22) ?? NSFont.boldSystemFont(ofSize: 22)
            drawCentered(caption, font: font, color: .white, y: CGFloat(height) - 44, canvasWidth: width)
        }
        guard let finalImage, let jpeg = ImageCanvas.jpegData(finalImage) else {
            throw ContentSourceError.message("Couldn't render the Mars rover image")
        }
        return jpeg
    }
}
