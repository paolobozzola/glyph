import Cocoa
import Quartz

/// Quick Look preview: renders the `.md` file as a styled `NSAttributedString` in a
/// read-only `NSTextView`. Rendering is fully native and in-process — no `WKWebView`.
///
/// Why not a web view: a `WKWebView` inside a *sandboxed, hardened-runtime* QL app
/// extension needs its web-content/networking helper processes, which don't reliably
/// launch under the extension sandbox — `load()` never returns and Quick Look shows a
/// spinning cog forever. (It works in an unsigned `make run` build only because that has
/// neither the sandbox nor the hardened runtime.) Native rendering can't hang, matches
/// the thumbnail extension's approach, and needs no extra entitlements.
class PreviewViewController: NSViewController, QLPreviewingController {

    private var scrollView: NSScrollView!
    private var textView: NSTextView!

    override func loadView() {
        let frame = NSRect(x: 0, y: 0, width: 640, height: 800)

        let scroll = NSScrollView(frame: frame)
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = true
        scroll.backgroundColor = .textBackgroundColor
        scroll.autoresizingMask = [.width, .height]

        let text = NSTextView(frame: frame)
        text.isEditable = false
        text.isSelectable = true
        text.drawsBackground = true
        text.backgroundColor = .textBackgroundColor
        text.textContainerInset = NSSize(width: 24, height: 24)
        text.isVerticallyResizable = true
        text.isHorizontallyResizable = false
        text.autoresizingMask = [.width]
        text.textContainer?.widthTracksTextView = true

        scroll.documentView = text
        self.scrollView = scroll
        self.textView = text
        self.view = scroll
    }

    func preparePreviewOfFile(at url: URL, completionHandler handler: @escaping (Error?) -> Void) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        let markdown: String
        do {
            markdown = try String(contentsOf: url, encoding: .utf8)
        } catch {
            handler(error)
            return
        }

        textView.textStorage?.setAttributedString(MarkdownPreviewRenderer.attributedString(from: markdown))
        // Native + synchronous: the preview is fully rendered here, so it can never stall.
        handler(nil)
    }
}
