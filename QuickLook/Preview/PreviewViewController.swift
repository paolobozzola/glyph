import Cocoa
import Quartz
import WebKit

/// Quick Look preview: renders the `.md` file as styled HTML in a WKWebView, using the
/// bundled markdown-it payload served over the app:// scheme (offline). Shares
/// AppSchemeHandler with the main app.
class PreviewViewController: NSViewController, QLPreviewingController {

    private var webView: WKWebView!
    private var pendingMarkdown: String?
    private var completion: ((Error?) -> Void)?

    override func loadView() {
        let configuration = WKWebViewConfiguration()
        let handler = AppSchemeHandler(subdirectory: "preview",
                                       bundle: Bundle(for: PreviewViewController.self))
        configuration.setURLSchemeHandler(handler, forURLScheme: "app")

        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 640, height: 800),
                            configuration: configuration)
        webView.navigationDelegate = self
        self.view = webView
    }

    func preparePreviewOfFile(at url: URL, completionHandler handler: @escaping (Error?) -> Void) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        do {
            pendingMarkdown = try String(contentsOf: url, encoding: .utf8)
        } catch {
            handler(error)
            return
        }
        completion = handler
        webView.load(URLRequest(url: URL(string: "app://preview/index.html")!))
    }
}

extension PreviewViewController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let markdown = pendingMarkdown else { finish(nil); return }
        let payload = (try? JSONSerialization.data(withJSONObject: [markdown]))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "[\"\"]"
        webView.evaluateJavaScript("window.glyphRender(\(payload)[0])") { [weak self] _, _ in
            self?.finish(nil)   // render is best-effort; the preview is already loaded
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(error)
    }

    private func finish(_ error: Error?) {
        completion?(error)
        completion = nil
    }
}
