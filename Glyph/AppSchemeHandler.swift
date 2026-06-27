import WebKit
import Foundation

/// Serves a bundled web payload over `app://<host>/...` so the web view loads entirely
/// from the bundle with no network access. Used by the editor (`Resources/editor/`) and
/// the Quick Look preview extension (`Resources/preview/`).
final class AppSchemeHandler: NSObject, WKURLSchemeHandler {
    private let subdirectory: String
    private let bundle: Bundle

    init(subdirectory: String = "editor", bundle: Bundle = .main) {
        self.subdirectory = subdirectory
        self.bundle = bundle
    }

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url else {
            task.didFailWithError(URLError(.badURL)); return
        }

        // app://<host>/index.html  ->  Resources/<subdirectory>/index.html
        let name = url.path.isEmpty || url.path == "/" ? "index.html"
                                                       : (url.path as NSString).lastPathComponent
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension

        guard let fileURL = bundle.url(forResource: base, withExtension: ext, subdirectory: subdirectory),
              let data = try? Data(contentsOf: fileURL) else {
            task.didFailWithError(URLError(.fileDoesNotExist)); return
        }

        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": mimeType(forExtension: ext)]
        )!
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}

    private func mimeType(forExtension ext: String) -> String {
        switch ext.lowercased() {
        case "html": return "text/html; charset=utf-8"
        case "js":   return "application/javascript; charset=utf-8"
        case "css":  return "text/css; charset=utf-8"
        case "json": return "application/json; charset=utf-8"
        default:     return "application/octet-stream"
        }
    }
}
