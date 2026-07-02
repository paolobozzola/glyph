import AppKit
import CoreServices
import UniformTypeIdentifiers

final class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = buildMainMenu()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)
        registerMarkdownAssociation()
    }

    /// Make Glyph a recognized (and default) handler for Markdown without the user having
    /// to run `lsregister` by hand.
    ///
    /// Just installing + launching doesn't reliably make LaunchServices pick up our type
    /// declarations — especially on machines that have seen several builds (stale LS cache),
    /// where `.md` files then show Glyph greyed-out in "Open With" and won't open. Force a
    /// self-registration every launch (the programmatic equivalent of `lsregister -f`), and
    /// on first launch claim the default handler so files Glyph creates reopen in Glyph.
    private func registerMarkdownAssociation() {
        LSRegisterURL(Bundle.main.bundleURL as CFURL, true)   // refresh our LS registration

        let key = "glyph.didClaimMarkdownDefault"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        // Claim the Markdown type as default once — never fight a later user choice.
        if let md = UTType("net.daringfireball.markdown") {
            NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpen: md) { _ in }
        }
        // Nudge Quick Look to adopt our just-registered preview extension. quicklookd caches
        // the generator→type binding, so a Mac that previewed a .md before installing Glyph
        // keeps showing raw text until the next logout. Refresh once (after a short delay so
        // pkd has registered the extension) so previews work without the user running
        // `qlmanage -r` themselves.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.refreshQuickLook()
        }
    }

    private func refreshQuickLook() {
        for args in [["-r"], ["-r", "cache"]] {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/qlmanage")
            p.arguments = args
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            try? p.run()
        }
    }

    // Document-based app: open an untitled document on launch / dock click.
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { true }

    // MARK: - Settings (⌘,)

    private lazy var settingsWC = SettingsWindowController()

    @objc func showSettings(_ sender: Any?) { settingsWC.present() }

    // Typewriter cadence lives in the View menu (radio Per Line / Per Paragraph) so it's a
    // quick switch while writing, not buried in Settings.
    private var cadenceLineItem: NSMenuItem?
    private var cadenceParaItem: NSMenuItem?

    @objc func setTypewriterCadence(_ sender: NSMenuItem) {
        GlyphSettings.defaults.set(sender.representedObject as? String ?? "line", forKey: GlyphSettings.cadenceKey)
        updateCadenceChecks()
        NotificationCenter.default.post(name: GlyphSettings.didChange, object: nil)
    }

    private func updateCadenceChecks() {
        let c = GlyphSettings.cadence
        cadenceLineItem?.state = (c == "line") ? .on : .off
        cadenceParaItem?.state = (c == "paragraph") ? .on : .off
    }

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
        let settingsItem = appMenu.addItem(withTitle: "Settings…", action: #selector(showSettings(_:)), keyEquivalent: ",")
        settingsItem.target = self
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
        // Note: "Open Recent" is provided automatically by AppKit on this macOS;
        // we intentionally don't build one here to avoid a duplicate entry.

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
        fileMenu.addItem(.separator())
        let exportItem = fileMenu.addItem(withTitle: "Export", action: nil, keyEquivalent: "")
        let exportMenu = NSMenu(title: "Export")
        exportItem.submenu = exportMenu
        exportMenu.addItem(withTitle: "Export as HTML…", action: #selector(EditorViewController.exportAsHTML(_:)), keyEquivalent: "")
        exportMenu.addItem(withTitle: "Export as PDF…", action: #selector(EditorViewController.exportAsPDF(_:)), keyEquivalent: "")

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

        // Find (drives the in-editor search bar via the bridge)
        let findItem = editMenu.addItem(withTitle: "Find", action: nil, keyEquivalent: "")
        let findMenu = NSMenu(title: "Find")
        findItem.submenu = findMenu
        addCommand(to: findMenu, "Find…", "find", key: "f")
        addCommand(to: findMenu, "Find and Replace…", "findReplace", key: "f", modifiers: [.command, .option])
        addCommand(to: findMenu, "Find Next", "findNext", key: "g")
        addCommand(to: findMenu, "Find Previous", "findPrev", key: "g", modifiers: [.command, .shift])
        editMenu.addItem(.separator())

        // Spelling & grammar (WKWebView handles these via the responder chain)
        let spellingItem = editMenu.addItem(withTitle: "Spelling and Grammar", action: nil, keyEquivalent: "")
        let spellingMenu = NSMenu(title: "Spelling and Grammar")
        spellingItem.submenu = spellingMenu
        // No accelerators: Apple's defaults here are ⌘: and ⌘; — punctuation keys
        // that mis-map on non-US layouts. Menu access only.
        spellingMenu.addItem(withTitle: "Show Spelling and Grammar", action: #selector(NSText.showGuessPanel(_:)), keyEquivalent: "")
        spellingMenu.addItem(withTitle: "Check Document Now", action: #selector(NSText.checkSpelling(_:)), keyEquivalent: "")
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
        // Table: insert + delete row/column/table (place the cursor in a cell first).
        let tableItem = formatMenu.addItem(withTitle: "Table", action: nil, keyEquivalent: "")
        let tableMenu = NSMenu(title: "Table")
        tableItem.submenu = tableMenu
        addCommand(to: tableMenu, "Insert Table", "table")
        tableMenu.addItem(.separator())
        addCommand(to: tableMenu, "Delete Row", "deleteRow")
        addCommand(to: tableMenu, "Delete Column", "deleteColumn")
        addCommand(to: tableMenu, "Delete Table", "deleteTable")
        formatMenu.addItem(.separator())
        addCommand(to: formatMenu, "Add Properties", "addProperties")

        // View menu
        let viewItem = NSMenuItem()
        mainMenu.addItem(viewItem)
        let viewMenu = NSMenu(title: "View")
        viewItem.submenu = viewMenu
        addCommand(to: viewMenu, "Show Outline", "toggleOutline", key: "o", modifiers: [.command, .option])
        addCommand(to: viewMenu, "Markdown Source", "toggleSource", key: "m", modifiers: [.command, .option])
        addCommand(to: viewMenu, "Focus", "toggleFocus", key: "f", modifiers: [.command, .shift])
        addCommand(to: viewMenu, "Typewriter", "toggleTypewriter", key: "t", modifiers: [.command, .shift])
        let cadenceItem = viewMenu.addItem(withTitle: "Typewriter Cadence", action: nil, keyEquivalent: "")
        let cadenceMenu = NSMenu(title: "Typewriter Cadence")
        cadenceItem.submenu = cadenceMenu
        cadenceLineItem = cadenceMenu.addItem(withTitle: "Per Line", action: #selector(setTypewriterCadence(_:)), keyEquivalent: "")
        cadenceLineItem?.representedObject = "line"; cadenceLineItem?.target = self
        cadenceParaItem = cadenceMenu.addItem(withTitle: "Per Paragraph", action: #selector(setTypewriterCadence(_:)), keyEquivalent: "")
        cadenceParaItem?.representedObject = "paragraph"; cadenceParaItem?.target = self
        updateCadenceChecks()
        viewMenu.addItem(.separator())
        viewMenu.addItem(withTitle: "Enter Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
            .keyEquivalentModifierMask = [.command, .control]

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

        // Help menu
        let helpItem = NSMenuItem()
        mainMenu.addItem(helpItem)
        let helpMenu = NSMenu(title: "Help")
        helpItem.submenu = helpMenu
        // ⇧⌘H: letter-based, so it's stable across international layouts (unlike
        // punctuation keys such as ⌘/ which mis-map on e.g. Italian keyboards).
        addCommand(to: helpMenu, "Glyph Cheat Sheet", "help", key: "h", modifiers: [.command, .shift])
        NSApp.helpMenu = helpMenu

        return mainMenu
    }

    /// Add a menu item that routes a bridge command to the focused editor.
    /// Shortcut policy: use only **letters or digits** for `key` — punctuation key
    /// equivalents (":", ";", "/", "?") mis-map on non-US keyboard layouts.
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
