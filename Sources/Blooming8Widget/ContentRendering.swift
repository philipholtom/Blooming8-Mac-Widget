import AppKit

/// Shared drawing helpers for ContentSource implementations, ported from the
/// PIL-based rendering in the original Python scripts. Uses a flipped
/// (top-left origin) graphics context so coordinates match the Python code
/// almost 1:1.
enum ImageCanvas {
    static func render(width: Int, height: Int, draw: () -> Void) -> NSImage? {
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return nil }

        let nsContext = NSGraphicsContext(cgContext: context, flipped: true)
        let previous = NSGraphicsContext.current
        NSGraphicsContext.current = nsContext
        draw()
        NSGraphicsContext.current = previous

        guard let cgImage = context.makeImage() else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))
    }

    /// Baseline (non-progressive) JPEG at the given quality, matching the
    /// Python scripts' `quality=95, progressive=False` output.
    static func jpegData(_ image: NSImage, quality: CGFloat = 0.95) -> Data? {
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else {
            return nil
        }
        return bitmap.representation(using: .jpeg, properties: [.compressionFactor: quality])
    }
}

/// Character-count based word wrap, matching `textwrap.wrap(text, width:)`
/// from the Python scripts (not pixel-measured, just word-boundary wrapping).
func wrapText(_ text: String, maxCharsPerLine: Int, maxLines: Int? = nil) -> [String] {
    var lines: [String] = []
    var currentLine = ""
    for word in text.split(separator: " ") {
        let candidate = currentLine.isEmpty ? String(word) : currentLine + " " + word
        if candidate.count > maxCharsPerLine, !currentLine.isEmpty {
            lines.append(currentLine)
            currentLine = String(word)
        } else {
            currentLine = candidate
        }
    }
    if !currentLine.isEmpty { lines.append(currentLine) }
    if let maxLines {
        return Array(lines.prefix(maxLines))
    }
    return lines
}
