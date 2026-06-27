import AppKit
import WebKit

/// Hosts the Milkdown editor (a WKWebView) and bridges it to the document.
///
/// Lifecycle rule (docs/SHELL.md §4): load the document's Markdown into the web view
/// **once**, after the editor reports `ready`. During editing the flow is JS → Swift
/// only (we never push model → web view on keystrokes). Re-load only on revert /
/// external reload.
final class EditorViewController: NSViewController, WKScriptMessageHandler, NSWindowDelegate {

    weak var document: MarkdownDocument?

    private var webView: WKWebView!
    private var isEditorReady = false

    // MARK: - View

    override func loadView() {
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(AppSchemeHandler(), forURLScheme: "app")
        configuration.userContentController.add(self, name: "glyph")

        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 820, height: 640),
                            configuration: configuration)
        webView.allowsMagnification = false
        webView.isInspectable = true
        if #available(macOS 12.0, *) {
            webView.underPageBackgroundColor = .textBackgroundColor
        }
        self.view = webView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        webView.load(URLRequest(url: URL(string: "app://editor/index.html")!))
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(systemAppearanceChanged),
            name: NSNotification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil
        )
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.delegate = self
        pushTheme()
    }

    deinit {
        DistributedNotificationCenter.default().removeObserver(self)
    }

    // MARK: - Bridge: JS → Swift

    func userContentController(_ controller: WKUserContentController,
                              didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let type = body["type"] as? String else { return }

        switch type {
        case "ready":
            isEditorReady = true
            loadMarkdownIntoEditor()
            pushTheme()
        case "change":
            if let markdown = body["markdown"] as? String {
                document?.text = markdown
                document?.updateChangeCount(.changeDone)
            }
        default:
            break
        }
    }

    // MARK: - Bridge: Swift → JS

    func loadMarkdownIntoEditor() {
        guard isEditorReady, let text = document?.text else { return }
        let payload = (try? JSONSerialization.data(withJSONObject: [text]))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "[\"\"]"
        webView.evaluateJavaScript("window.glyph.setMarkdown(\(payload)[0])")
    }

    /// Read the live Markdown out of the editor (used by save).
    func requestLatestMarkdown(_ completion: @escaping (String?) -> Void) {
        guard isEditorReady else { completion(nil); return }
        webView.evaluateJavaScript("window.glyph.getMarkdown()") { value, _ in
            completion(value as? String)
        }
    }

    // MARK: - Theme

    @objc private func systemAppearanceChanged() { pushTheme() }

    private func pushTheme() {
        let isDark = view.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        webView.evaluateJavaScript("window.glyph && window.glyph.setTheme('\(isDark ? "dark" : "light")')")
    }

    // MARK: - Undo / redo routed to the editor

    @objc func glyphUndo(_ sender: Any?) {
        webView.evaluateJavaScript("window.glyph.cmd('undo')")
    }

    @objc func glyphRedo(_ sender: Any?) {
        webView.evaluateJavaScript("window.glyph.cmd('redo')")
    }

    // MARK: - NSWindowDelegate

    func windowDidBecomeKey(_ notification: Notification) {
        document?.checkForExternalChanges()
    }
}
