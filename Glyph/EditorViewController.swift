import AppKit
import WebKit
import UniformTypeIdentifiers

/// Hosts the Milkdown editor (a WKWebView) and bridges it to the document.
///
/// Lifecycle rule (docs/SHELL.md §4): load the document's Markdown into the web view
/// **once**, after the editor reports `ready`. During editing the flow is JS → Swift
/// only (we never push model → web view on keystrokes). Re-load only on revert /
/// external reload.
final class EditorViewController: NSViewController, WKScriptMessageHandler, WKNavigationDelegate, NSWindowDelegate {

    weak var document: MarkdownDocument?

    private var webView: WKWebView!
    private var isEditorReady = false

    // Offscreen web view used only for PDF export (retained until printing finishes).
    private var pdfWebView: WKWebView?
    private var pdfURL: URL?

    // MARK: - View

    override func loadView() {
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(AppSchemeHandler(), forURLScheme: "app")
        // Weak proxy: WKUserContentController retains its handler, which would
        // otherwise create a cycle (controller → self → webView → config → controller)
        // and keep the editor/web view alive after the window closes.
        configuration.userContentController.add(WeakScriptMessageHandler(self), name: "glyph")

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

    // MARK: - Formatting commands (Format menu)

    /// Format-menu items carry their command name (e.g. "bold", "heading:2") in
    /// `representedObject`; route it to the editor.
    @objc func glyphCommand(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        let escaped = name.replacingOccurrences(of: "'", with: "\\'")
        webView.evaluateJavaScript("window.glyph.cmd('\(escaped)')")
    }

    // MARK: - Print

    @objc func printDocument(_ sender: Any?) {
        guard let window = view.window else { return }
        let printInfo = NSPrintInfo.shared
        let operation = webView.printOperation(with: printInfo)
        operation.showsPrintPanel = true
        operation.view?.frame = webView.bounds
        operation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
    }

    // MARK: - Share

    @objc func shareDocument(_ sender: Any?) {
        guard let contentView = view.window?.contentView else { return }
        let items: [Any] = document?.fileURL.map { [$0] } ?? [document?.text ?? ""]
        let picker = NSSharingServicePicker(items: items)
        picker.show(relativeTo: .zero, of: contentView, preferredEdge: .minY)
    }

    // MARK: - Export

    private var baseName: String {
        document?.fileURL?.deletingPathExtension().lastPathComponent
            ?? (document?.displayName ?? "Untitled")
    }

    /// File ▸ Export ▸ Export as HTML…
    @objc func exportAsHTML(_ sender: Any?) {
        fetchExportHTML { [weak self] html in
            guard let self, let window = self.view.window else { return }
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.html]
            panel.nameFieldStringValue = self.baseName + ".html"
            panel.beginSheetModal(for: window) { response in
                guard response == .OK, let url = panel.url else { return }
                try? Data(html.utf8).write(to: url)
            }
        }
    }

    /// File ▸ Export ▸ Export as PDF…
    @objc func exportAsPDF(_ sender: Any?) {
        fetchExportHTML { [weak self] html in
            guard let self, let window = self.view.window else { return }
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.pdf]
            panel.nameFieldStringValue = self.baseName + ".pdf"
            panel.beginSheetModal(for: window) { response in
                guard response == .OK, let url = panel.url else { return }
                self.renderPDF(html: html, to: url)
            }
        }
    }

    private func fetchExportHTML(_ completion: @escaping (String) -> Void) {
        webView.evaluateJavaScript("window.glyph.exportHTML()") { value, _ in
            if let html = value as? String { completion(html) }
        }
    }

    private func renderPDF(html: String, to url: URL) {
        // US Letter at 72 dpi; the print operation paginates the content.
        let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 612, height: 792))
        web.navigationDelegate = self
        pdfWebView = web
        pdfURL = url
        web.loadHTMLString(html, baseURL: nil)
    }

    // MARK: - WKNavigationDelegate (PDF export only)

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard webView === pdfWebView, let url = pdfURL else { return }
        defer { pdfWebView = nil; pdfURL = nil }

        let info = NSPrintInfo(dictionary: [
            .jobDisposition: NSPrintInfo.JobDisposition.save,
            .jobSavingURL: url,
        ])
        info.paperSize = NSSize(width: 612, height: 792)
        info.topMargin = 36; info.bottomMargin = 36
        info.leftMargin = 36; info.rightMargin = 36
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic

        let operation = webView.printOperation(with: info)
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false
        operation.run()
    }

    // MARK: - NSWindowDelegate

    func windowDidBecomeKey(_ notification: Notification) {
        document?.checkForExternalChanges()
    }
}

/// Forwards script messages to a weakly-held handler, so `WKUserContentController`
/// doesn't keep the editor alive after its window closes.
final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    private weak var target: WKScriptMessageHandler?

    init(_ target: WKScriptMessageHandler) { self.target = target }

    func userContentController(_ controller: WKUserContentController,
                              didReceive message: WKScriptMessage) {
        target?.userContentController(controller, didReceive: message)
    }
}
