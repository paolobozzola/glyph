import SwiftUI
import WebKit

/// Hosts the Milkdown editor (a WKWebView) and bridges it to the document.
///
/// Lifecycle rule (docs/SHELL.md §4): the document's Markdown is loaded into the
/// web view **once**, after the editor reports `ready`. During editing the flow is
/// JS → Swift only; we never push model → web view on keystrokes (that would reset
/// the caret). `updateNSView` is intentionally a content no-op.
struct EditorWebView: NSViewRepresentable {
    @ObservedObject var document: MarkdownDocument

    func makeCoordinator() -> Coordinator { Coordinator(document: document) }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(AppSchemeHandler(), forURLScheme: "app")
        configuration.userContentController.add(context.coordinator, name: "glyph")

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isInspectable = true                       // Safari Web Inspector during dev
        webView.allowsMagnification = false
        if #available(macOS 12.0, *) {
            webView.underPageBackgroundColor = .textBackgroundColor
        }
        context.coordinator.webView = webView

        webView.load(URLRequest(url: URL(string: "app://editor/index.html")!))
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        // Content no-op by design — see the lifecycle rule above.
    }

    final class Coordinator: NSObject, WKScriptMessageHandler {
        let document: MarkdownDocument
        weak var webView: WKWebView?
        private var didLoadInitial = false

        init(document: MarkdownDocument) { self.document = document }

        func userContentController(_ controller: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any],
                  let type = body["type"] as? String else { return }

            switch type {
            case "ready":
                loadInitialMarkdown()
            case "change":
                if let markdown = body["markdown"] as? String {
                    document.text = markdown
                    // M0 visibility: confirms the round-trip in Console / Xcode.
                    NSLog("[Glyph] change: %d chars", markdown.count)
                }
            default:
                break
            }
        }

        private func loadInitialMarkdown() {
            guard !didLoadInitial, let webView else { return }
            didLoadInitial = true
            // JSON-encode then index [0] so any quotes/newlines are safely escaped.
            let payload = (try? JSONSerialization.data(withJSONObject: [document.text]))
                .flatMap { String(data: $0, encoding: .utf8) } ?? "[\"\"]"
            webView.evaluateJavaScript("window.glyph.setMarkdown(\(payload)[0])")
        }
    }
}
