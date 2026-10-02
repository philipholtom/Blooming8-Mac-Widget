import AppKit

/// NASA's Astronomy Picture of the Day, for a random date, framed with the
/// date and description overlaid. Ported from random_apod_framed.py — the
/// layout constants below match that script exactly.
public struct APODSource: TodayContentSource {
    public init() {}

    public let id = "apod"
    public let displayName = "NASA Photo of the Day"
    public let galleryName = "NASA"

    private let width = 1200
    private let height = 1600
    private let borderWidth: CGFloat = 30
    private let textAreaTop: CGFloat = 80
    private let textAreaBottom: CGFloat = 150

    public let todayButtonTitle = "Today's Picture"

    public func generateImage(settings: AppSettings) async throws -> Data {
        try await render(try await fetchRandomAPOD())
    }

    /// The real picture of the day, as opposed to a random date's.
    public func generateTodayImage(settings: AppSettings) async throws -> Data {
        let apod: APODResponse
        do {
            apod = try await fetchAPOD(dateCode: Self.dateCode(for: Date()))
        } catch {
            // NASA publishes each day's entry just after midnight US Eastern.
            throw ContentSourceError.message("Today's NASA picture isn't available yet — try again in a little while.")
        }
        guard Self.isUsableImage(apod) else {
            throw ContentSourceError.message("Today's NASA picture is a video, so there's no image to show. Try a random one instead.")
        }
        return try await render(apod)
    }

    private func render(_ apod: APODResponse) async throws -> Data {
        guard let urlString = apod.hdurl, let imageURL = URL(string: urlString) else {
            throw ContentSourceError.message("No image URL in APOD response")
        }
        let (imageData, _) = try await URLSession.shared.data(from: imageURL)
        guard let sourceImage = NSImage(data: imageData) else {
            throw ContentSourceError.message("Couldn't decode APOD image")
        }
        guard let framed = composeFramed(image: sourceImage, date: apod.date, description: Self.plainText(fromHTML: apod.explanation)),
              let jpeg = ImageCanvas.jpegData(framed)
        else {
            throw ContentSourceError.message("Couldn't render APOD image")
        }
        return jpeg
    }

    private struct APODResponse: Decodable {
        let date: String
        let explanation: String
        let mediaType: String?
        let hdurl: String?

        private enum CodingKeys: String, CodingKey {
            case date, explanation, hdurl
            case mediaType = "media_type"
        }
    }

    /// Videos carry an `hdurl` too (a thumbnail), so the media type has to be
    /// checked; the logo check guards against NASA's placeholder coming back.
    private static func isUsableImage(_ apod: APODResponse) -> Bool {
        guard apod.mediaType == "image", let hd = apod.hdurl, !hd.isEmpty else { return false }
        return !hd.contains("nasa-logo")
    }

    /// NASA moved APOD onto science.nasa.gov, and the old api.nasa.gov
    /// endpoint now answers every date with the NASA logo as the "image".
    /// This is the new site's own JSON endpoint — same fields, keyed by a
    /// YYMMDD date, covering the whole archive back to 1995, and needing no
    /// API key.
    private func fetchAPOD(dateCode: String) async throws -> APODResponse {
        let url = URL(string: "https://science.nasa.gov/wp-json/wp/v2/apod-basic/\(dateCode)")!
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ContentSourceError.message("NASA's APOD service returned an error")
        }
        return try JSONDecoder().decode(APODResponse.self, from: data)
    }

    private func fetchRandomAPOD(maxRetries: Int = 6) async throws -> APODResponse {
        var lastError: Error = ContentSourceError.message("Couldn't reach NASA's APOD service")
        for _ in 0..<maxRetries {
            do {
                let decoded = try await fetchAPOD(dateCode: randomDateCode())
                if Self.isUsableImage(decoded) { return decoded }
                // That date was video-only (or had no real image) — try another.
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    /// APOD rolls over to a new day in US Eastern time, so dates are worked
    /// out there — in a UK timezone they'd be a day out against it.
    private static var easternCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .current
        return calendar
    }

    private static func dateCode(for date: Date) -> String {
        let calendar = easternCalendar
        let formatter = DateFormatter()
        formatter.dateFormat = "yyMMdd"
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        return formatter.string(from: date)
    }

    /// A random date between APOD's start (1995-06-16) and today.
    private func randomDateCode() -> String {
        let calendar = Self.easternCalendar
        var startComponents = DateComponents()
        startComponents.year = 1995
        startComponents.month = 6
        startComponents.day = 16
        let start = calendar.date(from: startComponents) ?? Date()
        let days = max(calendar.dateComponents([.day], from: start, to: Date()).day ?? 0, 0)
        let randomDate = calendar.date(byAdding: .day, value: Int.random(in: 0...days), to: start) ?? Date()
        return Self.dateCode(for: randomDate)
    }

    /// The endpoint's `explanation` is HTML: a leading "Explanation:" label,
    /// links, and site boilerplate ("APOD's email…", "Tomorrow's picture:")
    /// on the end. The frame wants the plain paragraph.
    static func plainText(fromHTML html: String) -> String {
        var text = html
        if let boilerplate = text.range(of: "<(strong|b)>\\s*(APOD|Tomorrow)", options: [.regularExpression, .caseInsensitive]) {
            text = String(text[..<boilerplate.lowerBound])
        }
        text = text.replacingOccurrences(of: "<br\\s*/?>", with: " ", options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        text = decodeHTMLEntities(text)
        text = text.replacingOccurrences(of: "^\\s*Explanation:\\s*", with: "", options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        // Links in the source leave stray spaces before punctuation ("nebula , stars").
        text = text.replacingOccurrences(of: "\\s+([,.;:!?])", with: "$1", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func decodeHTMLEntities(_ text: String) -> String {
        var result = text
        if let regex = try? NSRegularExpression(pattern: "&#(x[0-9a-fA-F]+|[0-9]+);") {
            let matches = regex.matches(in: result, range: NSRange(result.startIndex..., in: result)).reversed()
            for match in matches {
                guard let whole = Range(match.range, in: result), let codeRange = Range(match.range(at: 1), in: result) else { continue }
                let code = result[codeRange]
                let value = code.hasPrefix("x") ? UInt32(code.dropFirst(), radix: 16) : UInt32(code, radix: 10)
                if let value, let scalar = Unicode.Scalar(value) {
                    result.replaceSubrange(whole, with: String(Character(scalar)))
                }
            }
        }
        let named = [("&nbsp;", " "), ("&quot;", "\""), ("&apos;", "'"), ("&lt;", "<"), ("&gt;", ">"), ("&amp;", "&")]
        for (entity, replacement) in named {
            result = result.replacingOccurrences(of: entity, with: replacement)
        }
        return result
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
            drawImage(image, in: NSRect(x: xOffset, y: yOffset, width: newWidth, height: newHeight))

            let titleFont = NSFont(name: "Helvetica", size: 28) ?? NSFont.systemFont(ofSize: 28)
            let textFont = NSFont(name: "Helvetica", size: 16) ?? NSFont.systemFont(ofSize: 16)

            drawCentered("APOD: \(date)", font: titleFont, color: .black, y: self.borderWidth + 15, canvasWidth: self.width)

            let wrapped = wrapTextEndingCleanly(description, maxCharsPerLine: 60, maxLines: 5)
            var descY = CGFloat(self.height) - self.textAreaBottom + self.borderWidth
            let lineHeight: CGFloat = 18
            for line in wrapped {
                drawCentered(line, font: textFont, color: .black, y: descY, canvasWidth: self.width)
                descY += lineHeight
            }
        }
    }
}
