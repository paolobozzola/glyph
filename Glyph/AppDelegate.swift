import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = buildMainMenu()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)
    }

    // Document-based app: open an untitled document on launch / dock click.
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { true }

    // MARK: - Main menu (programmatic)

    private func buildMainMenu() -> NSMenu {
        let mainMenu = NSMenu()
        let appName = "Glyph"

        // App menu
        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appItem.submenu = appMenu
        appMenu.addItem(withTitle: "About \(appName)", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide \(appName)", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = appMenu.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit \(appName)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        // File menu
        let fileItem = NSMenuItem()
        mainMenu.addItem(fileItem)
        let fileMenu = NSMenu(title: "File")
        fileItem.submenu = fileMenu
        fileMenu.addItem(withTitle: "New", action: #selector(NSDocumentController.newDocument(_:)), keyEquivalent: "n")
        fileMenu.addItem(withTitle: "Open…", action: #selector(NSDocumentController.openDocument(_:)), keyEquivalent: "o")

        // Open Recent (auto-populated by NSDocumentController)
        let openRecentItem = fileMenu.addItem(withTitle: "Open Recent", action: nil, keyEquivalent: "")
        let openRecentMenu = NSMenu(title: "Open Recent")
        openRecentItem.submenu = openRecentMenu
        let clearItem = openRecentMenu.addItem(withTitle: "Clear Menu", action: #selector(NSDocumentController.clearRecentDocuments(_:)), keyEquivalent: "")
        clearItem.tag = 0

        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        fileMenu.addItem(withTitle: "Save…", action: #selector(NSDocument.save(_:)), keyEquivalent: "s")
        let saveAs = fileMenu.addItem(withTitle: "Save As…", action: #selector(NSDocument.saveAs(_:)), keyEquivalent: "S")
        saveAs.keyEquivalentModifierMask = [.command, .shift]
        fileMenu.addItem(withTitle: "Revert to Saved", action: #selector(NSDocument.revertToSaved(_:)), keyEquivalent: "")
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "Share…", action: #selector(EditorViewController.shareDocument(_:)), keyEquivalent: "")
        fileMenu.addItem(.separator())
        let pageSetup = fileMenu.addItem(withTitle: "Page Setup…", action: #selector(NSDocument.runPageLayout(_:)), keyEquivalent: "P")
        pageSetup.keyEquivalentModifierMask = [.command, .shift]
        fileMenu.addItem(withTitle: "Print…", action: #selector(EditorViewController.printDocument(_:)), keyEquivalent: "p")

        // Edit menu
        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "Edit")
        editItem.submenu = editMenu
        // Undo/redo are routed to the editor (Milkdown owns history) via custom
        // selectors so WKWebView's responder chain reaches EditorViewController.
        editMenu.addItem(withTitle: "Undo", action: #selector(EditorViewController.glyphUndo(_:)), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "Redo", action: #selector(EditorViewController.glyphRedo(_:)), keyEquivalent: "Z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenu.addItem(.separator())

        // Spelling & grammar (WKWebView handles these via the responder chain)
        let spellingItem = editMenu.addItem(withTitle: "Spelling and Grammar", action: nil, keyEquivalent: "")
        let spellingMenu = NSMenu(title: "Spelling and Grammar")
        spellingItem.submenu = spellingMenu
        spellingMenu.addItem(withTitle: "Show Spelling and Grammar", action: #selector(NSText.showGuessPanel(_:)), keyEquivalent: ":")
        spellingMenu.addItem(withTitle: "Check Document Now", action: #selector(NSText.checkSpelling(_:)), keyEquivalent: ";")
        spellingMenu.addItem(.separator())
        spellingMenu.addItem(withTitle: "Check Spelling While Typing", action: #selector(NSTextView.toggleContinuousSpellChecking(_:)), keyEquivalent: "")
        spellingMenu.addItem(withTitle: "Check Grammar With Spelling", action: #selector(NSTextView.toggleGrammarChecking(_:)), keyEquivalent: "")

        // Format menu
        let formatItem = NSMenuItem()
        mainMenu.addItem(formatItem)
        let formatMenu = NSMenu(title: "Format")
        formatItem.submenu = formatMenu
        addCommand(to: formatMenu, "Bold", "bold", key: "b")
        addCommand(to: formatMenu, "Italic", "italic", key: "i")
        addCommand(to: formatMenu, "Strikethrough", "strike")
        addCommand(to: formatMenu, "Inline Code", "code")
        addCommand(to: formatMenu, "Link", "link", key: "k")
        formatMenu.addItem(.separator())

        let headingItem = formatMenu.addItem(withTitle: "Heading", action: nil, keyEquivalent: "")
        let headingMenu = NSMenu(title: "Heading")
        headingItem.submenu = headingMenu
        addCommand(to: headingMenu, "Body Text", "paragraph", key: "0", modifiers: [.command, .option])
        for level in 1...6 {
            addCommand(to: headingMenu, "Heading \(level)", "heading:\(level)", key: "\(level)", modifiers: [.command, .option])
        }
        formatMenu.addItem(.separator())
        addCommand(to: formatMenu, "Bulleted List", "bulletList", key: "8", modifiers: [.command, .shift])
        addCommand(to: formatMenu, "Numbered List", "orderedList", key: "7", modifiers: [.command, .shift])
        addCommand(to: formatMenu, "Block Quote", "blockquote")
        addCommand(to: formatMenu, "Code Block", "codeBlock")
        formatMenu.addItem(.separator())
        addCommand(to: formatMenu, "Horizontal Rule", "hr")
        addCommand(to: formatMenu, "Insert Table", "table")

        // Window menu
        let windowItem = NSMenuItem()
        mainMenu.addItem(windowItem)
        let windowMenu = NSMenu(title: "Window")
        windowItem.submenu = windowMenu
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowMenu.addItem(.separator())
        windowMenu.addItem(withTitle: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        NSApp.windowsMenu = windowMenu

        return mainMenu
    }

    /// Add a Format-menu item that routes a bridge command to the focused editor.
    @discardableResult
    private func addCommand(to menu: NSMenu,
                            _ title: String,
                            _ command: String,
                            key: String = "",
                            modifiers: NSEvent.ModifierFlags = .command) -> NSMenuItem {
        let item = menu.addItem(withTitle: title,
                                action: #selector(EditorViewController.glyphCommand(_:)),
                                keyEquivalent: key)
        item.representedObject = command
        if !key.isEmpty { item.keyEquivalentModifierMask = modifiers }
        return item
    }
}
