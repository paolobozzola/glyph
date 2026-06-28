import WebKit
import Foundation

/// Serves content over `app://<host>/...`:
///  1. the bundled web payload (`Resources/<subdirectory>/…`) — editor or QL preview, and
///  2. (editor only) files from the open document's directory, so relative image links
///     like `notes.assets/img.png` resolve to assets saved next to the `.md`.
/// Everything loads with no network access.
final class AppSchemeHandler: NSObject, WKURLSchemeHandler {
    private let subdirectory: String
    private let bundle: Bundle
    private let assetDirectory: (() -> URL?)?

    init(subdirectory: String = "editor",
         bundle: Bundle = .main,
         assetDirectory: (() -> URL?)? = nil) {
        self.subdirectory = subdirectory
        self.bundle = bundle
        self.assetDirectory = assetDirectory
    }

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url else {
            task.didFailWithError(URLError(.badURL)); return
        }

        // url.path is already percent-decoded, so it matches on-disk names with spaces.
        var rel = url.path
        if rel.hasPrefix("/") { rel.removeFirst() }
        if rel.isEmpty { rel = "index.html" }

        guard let fileURL = resolveFile(rel), let data = try? Data(contentsOf: fileURL) else {
            task.didFailWithError(URLError(.fileDoesNotExist)); return
        }

        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": Self.mimeType(forExtension: fileURL.pathExtension)]
        )!
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}

    /// Look in the bundled payload first, then the document's directory. Both lookups are
    /// confined to their root to prevent path-traversal (`..`) escapes.
    private func resolveFile(_ rel: String) -> URL? {
        if let base = bundle.resourceURL?.appendingPathComponent(subdirectory, isDirectory: true) {
            let candidate = base.appendingPathComponent(rel)
            if isContained(candidate, in: base), FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        if let dir = assetDirectory?() {
            let candidate = dir.appendingPathComponent(rel)
            if isContained(candidate, in: dir), FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    private func isContained(_ candidate: URL, in base: URL) -> Bool {
        let b = base.standardizedFileURL.path
        let c = candidate.standardizedFileURL.path
        return c == b || c.hasPrefix(b + "/")
    }

    static func mimeType(forExtension ext: String) -> String {
        switch ext.lowercased() {
        case "html": return "text/html; charset=utf-8"
        case "js":   return "application/javascript; charset=utf-8"
        case "css":  return "text/css; charset=utf-8"
        case "json": return "application/json; charset=utf-8"
        case "png":  return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif":  return "image/gif"
        case "webp": return "image/webp"
        case "svg":  return "image/svg+xml"
        case "tif", "tiff": return "image/tiff"
        case "bmp":  return "image/bmp"
        case "heic": return "image/heic"
        default:     return "application/octet-stream"
        }
    }
}
