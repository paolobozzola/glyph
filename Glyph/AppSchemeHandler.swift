import WebKit
import Foundation

/// Serves the bundled editor over `app://editor/...` so the web view loads entirely
/// from the app bundle with no network access. The editor is a single self-contained
/// `index.html` in `Resources/editor/` (see web/vite.config.ts).
final class AppSchemeHandler: NSObject, WKURLSchemeHandler {
    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url else {
            task.didFailWithError(URLError(.badURL)); return
        }

        // app://editor/index.html  ->  Resources/editor/index.html
        let name = url.path.isEmpty || url.path == "/" ? "index.html"
                                                       : (url.path as NSString).lastPathComponent
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension

        guard let fileURL = Bundle.main.url(forResource: base, withExtension: ext, subdirectory: "editor"),
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
