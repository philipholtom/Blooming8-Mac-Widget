import AppKit

/// NASA's Astronomy Picture of the Day, for a random date, framed with the
/// date and description overlaid. Ported from random_apod_framed.py — the
/// layout constants below match that script exactly.
struct APODSource: ContentSource {
    let id = "apod"
    let displayName = "NASA Photo of the Day"
    let galleryName = "NASA"

    private let width = 1200
    private let height = 1600
    private let borderWidth: CGFloat = 30
    private let textAreaTop: CGFloat = 80
    private let textAreaBottom: CGFloat = 150

    func generateImage(settings: Settings) async throws -> Data {
        let apod = try await fetchRandomAPOD(apiKey: settings.nasaApiKey)
        guard let urlString = apod.hdurl ?? apod.url, let imageURL = URL(string: urlString) else {
            throw ContentSourceError.message("No image URL in APOD response")
        }
        let (imageData, _) = try await URLSession.shared.data(from: imageURL)
        guard let sourceImage = NSImage(data: imageData) else {
            throw ContentSourceError.message("Couldn't decode APOD image")
        }
        guard let framed = composeFramed(image: sourceImage, date: apod.date, description: apod.explanation),
              let jpeg = ImageCanvas.jpegData(framed)
        else {
            throw ContentSourceError.message("Couldn't render APOD image")
        }
        return jpeg
    }

    private struct APODResponse: Decodable {
        let date: String
        let explanation: String
        let url: String?
        let hdurl: String?
    }

    private func fetchRandomAPOD(apiKey: String, maxRetries: Int = 4) async throws -> APODResponse {
        var lastError: Error = ContentSourceError.message("Couldn't reach the NASA APOD API")
        for _ in 0..<maxRetries {
            var components = URLComponents(string: "https://api.nasa.gov/planetary/apod")!
            components.queryItems = [
                URLQueryItem(name: "api_key", value: apiKey),
                URLQueryItem(name: "date", value: randomDateString())
            ]
            do {
                let (data, response) = try await URLSession.shared.data(from: components.url!)
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                    lastError = ContentSourceError.message("NASA API returned an error")
                    continue
                }
                let decoded = try JSONDecoder().decode(APODResponse.self, from: data)
                if decoded.hdurl != nil || decoded.url != nil {
                    return decoded
                }
                // That date was video-only (no image) — try another date.
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    /// A random date between APOD's start (1995-06-16) and today, matching
    /// get_random_date() in the Python script.
    private func randomDateString() -> String {
        var startComponents = DateComponents()
        startComponents.year = 1995
        startComponents.month = 6
        startComponents.day = 16
        let calendar = Calendar(identifier: .gregorian)
        let start = calendar.date(from: startComponents) ?? Date()
        let days = max(calendar.dateComponents([.day], from: start, to: Date()).day ?? 0, 0)
        let randomDate = calendar.date(byAdding: .day, value: Int.random(in: 0...days), to: start) ?? Date()

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.calendar = calendar
        return formatter.string(from: randomDate)
    }

    private func composeFramed(image: NSImage, date: String, description: String) -> NSImage? {
        let contentWidth = CGFloat(width) - 2 * borderWidth
        let contentHeight = CGFloat(height) - borderWidth - textAreaTop - textAreaBottom - borderWidth

        return ImageCanvas.render(width: width, height: height) {
            NSColor.white.setFill()
            NSBezierPath(rect: NSRect(x: 0, y: 0, width: self.width, height: self.height)).fill()

            let imageSize = image.size
            let imageAspect = imageSize.width / imageSize.height
            let contentAspect = contentWidth / contentHeight
            let newWidth: CGFloat
            let newHeight: CGFloat
            if imageAspect > contentAspect {
                newHeight = contentHeight
                newWidth = contentHeight * imageAspect
            } else {
                newWidth = contentWidth
                newHeight = newWidth / imageAspect
            }
            let xOffset = self.borderWidth + (contentWidth - newWidth) / 2
            let yOffset = self.borderWidth + self.textAreaTop + (contentHeight - newHeight) / 2
            image.draw(in: NSRect(x: xOffset, y: yOffset, width: newWidth, height: newHeight))

            let titleFont = NSFont(name: "Helvetica", size: 28) ?? NSFont.systemFont(ofSize: 28)
            let textFont = NSFont(name: "Helvetica", size: 16) ?? NSFont.systemFont(ofSize: 16)

            let dateText = "APOD: \(date)" as NSString
            let dateAttrs: [NSAttributedString.Key: Any] = [.font: titleFont, .foregroundColor: NSColor.black]
            let dateSize = dateText.size(withAttributes: dateAttrs)
            dateText.draw(
                at: NSPoint(x: (CGFloat(self.width) - dateSize.width) / 2, y: self.borderWidth + 15),
                withAttributes: dateAttrs
            )

            let descAttrs: [NSAttributedString.Key: Any] = [.font: textFont, .foregroundColor: NSColor.black]
            let wrapped = wrapText(description, maxCharsPerLine: 60, maxLines: 5)
            var descY = CGFloat(self.height) - self.textAreaBottom + self.borderWidth
            let lineHeight: CGFloat = 18
            for line in wrapped {
                let nsLine = line as NSString
                let lineSize = nsLine.size(withAttributes: descAttrs)
                nsLine.draw(at: NSPoint(x: (CGFloat(self.width) - lineSize.width) / 2, y: descY), withAttributes: descAttrs)
                descY += lineHeight
            }
        }
    }
}
