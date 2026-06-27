import AppKit
import QuickLookThumbnailing

/// Quick Look thumbnail: draws the document's text onto a page. Uses native Core
/// Graphics / AppKit drawing (not a web-view snapshot) so it's reliable off the main
/// thread — see docs/SHELL.md for why this differs from the preview renderer.
class ThumbnailProvider: QLThumbnailProvider {

    override func provideThumbnail(for request: QLFileThumbnailRequest,
                                   _ handler: @escaping (QLThumbnailReply?, Error?) -> Void) {
        let url = request.fileURL
        let accessing = url.startAccessingSecurityScopedResource()
        let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        if accessing { url.stopAccessingSecurityScopedResource() }

        let size = request.maximumSize
        let reply = QLThumbnailReply(contextSize: size) { (cgContext: CGContext) -> Bool in
            ThumbnailProvider.draw(text: text, size: size, in: cgContext)
            return true
        }
        handler(reply, nil)
    }

    private static func draw(text: String, size: CGSize, in cg: CGContext) {
        let rect = CGRect(origin: .zero, size: size)

        // Paper + subtle border (explicit Core Graphics — reliable in the thumbnail ctx)
        cg.setFillColor(CGColor(gray: 1, alpha: 1))
        cg.fill(rect)
        cg.setStrokeColor(CGColor(gray: 0.85, alpha: 1))
        cg.setLineWidth(1)
        cg.stroke(rect.insetBy(dx: 0.5, dy: 0.5))

        // Text — the QL thumbnail CGContext is bottom-left origin; a non-flipped
        // NSGraphicsContext draws AttributedString upright (verified vs. a bitmap harness).
        let ns = NSGraphicsContext(cgContext: cg, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ns

        let inset = max(6, size.width * 0.10)
        let textRect = rect.insetBy(dx: inset, dy: inset)
        let fontSize = max(6, size.width / 24)

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.lineSpacing = fontSize * 0.25

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize),
            .foregroundColor: NSColor(white: 0.15, alpha: 1),
            .paragraphStyle: paragraph,
        ]
        (String(text.prefix(1200)) as NSString).draw(in: textRect, withAttributes: attributes)

        NSGraphicsContext.restoreGraphicsState()
    }
}
