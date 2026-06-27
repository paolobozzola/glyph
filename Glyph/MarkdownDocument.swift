import AppKit

/// The Markdown text *is* the document — the single source of truth.
/// `NSDocument` gives autosave-in-place, Versions, tabs, and recent files, and lets
/// dirty-tracking (`updateChangeCount`) stay decoupled from undo — so Milkdown keeps
/// owning ⌘Z (see docs/SHELL.md and CLAUDE.md).
final class MarkdownDocument: NSDocument {

    var text: String = "# New Document\n\nStart writing…\n"
    weak var editor: EditorViewController?

    override class var autosavesInPlace: Bool { true }
    override class var autosavesDrafts: Bool { true }

    // MARK: - Window

    override func makeWindowControllers() {
        let viewController = EditorViewController()
        viewController.document = self
        self.editor = viewController

        let window = NSWindow(contentViewController: viewController)
        window.setContentSize(NSSize(width: 820, height: 640))
        window.tabbingIdentifier = "GlyphDocument"
        window.tabbingMode = .preferred
        window.minSize = NSSize(width: 480, height: 320)

        let windowController = NSWindowController(window: window)
        windowController.shouldCascadeWindows = true
        addWindowController(windowController)
    }

    // MARK: - I/O

    override func data(ofType typeName: String) throws -> Data {
        Data(text.utf8)
    }

    override func read(from data: Data, ofType typeName: String) throws {
        guard let string = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        text = string
        editor?.loadMarkdownIntoEditor()   // refresh editor on revert / external reload
    }

    // Note: `text` is kept current by the editor's debounced `change` stream, so
    // `data(ofType:)` already has fresh content. We deliberately do NOT override the
    // async save to pull from the editor — during window teardown the WKWebView's
    // `evaluateJavaScript` completion may never fire, which would hang the close.

    // MARK: - External changes

    /// Called when the document window regains focus. If the file changed on disk,
    /// reload (clean doc) or ask the user (edited doc).
    func checkForExternalChanges() {
        guard let url = fileURL,
              let onDisk = try? String(contentsOf: url, encoding: .utf8),
              onDisk != text else { return }

        if isDocumentEdited {
            let alert = NSAlert()
            alert.messageText = "“\(displayName ?? "This document")” was changed by another app."
            alert.informativeText = "Reload from disk and discard your unsaved changes, or keep editing?"
            alert.addButton(withTitle: "Keep Editing")
            alert.addButton(withTitle: "Reload")
            guard alert.runModal() == .alertSecondButtonReturn else { return }
        }

        text = onDisk
        updateChangeCount(.changeCleared)
        editor?.loadMarkdownIntoEditor()
    }
}
