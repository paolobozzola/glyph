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

    /// Explicit saves (⌘S / Save As) pull the freshest Markdown straight from the
    /// editor first, so nothing typed in the last debounce window is lost.
    override func save(to url: URL,
                       ofType typeName: String,
                       for saveOperation: NSDocument.SaveOperationType,
                       completionHandler: @escaping (Error?) -> Void) {
        guard let editor else {
            superSave(to: url, ofType: typeName, for: saveOperation, completionHandler: completionHandler)
            return
        }
        editor.requestLatestMarkdown { [weak self] latest in
            guard let self else { return }
            if let latest { self.text = latest }
            self.superSave(to: url, ofType: typeName, for: saveOperation, completionHandler: completionHandler)
        }
    }

    // `super` can't be referenced inside a closure, so route through a helper.
    private func superSave(to url: URL,
                           ofType typeName: String,
                           for saveOperation: NSDocument.SaveOperationType,
                           completionHandler: @escaping (Error?) -> Void) {
        super.save(to: url, ofType: typeName, for: saveOperation, completionHandler: completionHandler)
    }

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
