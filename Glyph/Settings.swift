import AppKit
import WebKit


// MARK: - Small UI helpers

private func caption(_ text: String) -> NSTextField {
    let l = NSTextField(wrappingLabelWithString: text)
    l.font = .systemFont(ofSize: 11)
    l.textColor = .secondaryLabelColor
    l.isSelectable = false
    return l
}

private func sectionTitle(_ text: String) -> NSTextField {
    let l = NSTextField(labelWithString: text)
    l.font = .systemFont(ofSize: 11, weight: .semibold)
    l.textColor = .secondaryLabelColor
    return l
}

private func rightLabel(_ text: String, width: CGFloat = 118) -> NSTextField {
    let l = NSTextField(labelWithString: text)
    l.alignment = .right
    l.widthAnchor.constraint(equalToConstant: width).isActive = true
    return l
}

// Fixed content width so switching tabs only changes height, never width.
private let kSettingsContentWidth: CGFloat = 620

// MARK: - Settings window (toolbar tabs)

final class SettingsWindowController: NSWindowController, NSToolbarDelegate {
    private struct Tab { let id: NSToolbarItem.Identifier; let title: String; let symbol: String; let vc: NSViewController }
    private let tabs: [Tab] = [
        Tab(id: .init("editing"), title: "Editing", symbol: "pencil", vc: EditingSettingsViewController()),
        Tab(id: .init("typography"), title: "Typography", symbol: "textformat.size", vc: TypographySettingsViewController()),
    ]

    private let container = NSView()
    private var currentView: NSView?

    convenience init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: kSettingsContentWidth, height: 360),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        self.init(window: window)
        window.contentView = container
        // Add every tab's view once (top-pinned, intrinsic height); we crossfade between them.
        for tab in tabs {
            let v = tab.vc.view
            v.translatesAutoresizingMaskIntoConstraints = false
            v.alphaValue = 0
            container.addSubview(v)
            NSLayoutConstraint.activate([
                v.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                v.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                v.topAnchor.constraint(equalTo: container.topAnchor),
            ])
        }
        let toolbar = NSToolbar(identifier: "GlyphSettingsToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconAndLabel
        toolbar.allowsUserCustomization = false
        if #available(macOS 11.0, *) { window.toolbarStyle = .preference }
        window.toolbar = toolbar
        select(tabs[0], animated: false)
        toolbar.selectedItemIdentifier = tabs[0].id
    }

    func present() {
        showWindow(nil); window?.center(); window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func select(_ tab: Tab, animated: Bool) {
        guard let window = window else { return }
        window.title = tab.title
        let newView = tab.vc.view
        newView.layoutSubtreeIfNeeded()

        // Target window frame: adjust by the content-height delta, keeping the top edge fixed.
        let curContent = window.contentRect(forFrameRect: window.frame).size
        let dh = newView.fittingSize.height - curContent.height
        var target = window.frame
        target.size.height += dh
        target.origin.y -= dh

        let old = currentView
        currentView = newView
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.22
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                ctx.allowsImplicitAnimation = true
                window.animator().setFrame(target, display: true)
                old?.animator().alphaValue = 0
                newView.animator().alphaValue = 1
            }
        } else {
            window.setFrame(target, display: false)
            old?.alphaValue = 0
            newView.alphaValue = 1
        }
    }

    @objc private func toolbarAction(_ sender: NSToolbarItem) {
        if let tab = tabs.first(where: { $0.id == sender.itemIdentifier }) { select(tab, animated: true) }
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard let tab = tabs.first(where: { $0.id == id }) else { return nil }
        let item = NSToolbarItem(itemIdentifier: id)
        item.label = tab.title
        item.image = NSImage(systemSymbolName: tab.symbol, accessibilityDescription: tab.title)
        item.target = self
        item.action = #selector(toolbarAction(_:))
        return item
    }
    func toolbarDefaultItemIdentifiers(_ t: NSToolbar) -> [NSToolbarItem.Identifier] { tabs.map { $0.id } }
    func toolbarAllowedItemIdentifiers(_ t: NSToolbar) -> [NSToolbarItem.Identifier] { tabs.map { $0.id } }
    func toolbarSelectableItemIdentifiers(_ t: NSToolbar) -> [NSToolbarItem.Identifier] { tabs.map { $0.id } }
}

// MARK: - Editing tab

final class EditingSettingsViewController: NSViewController {
    override func loadView() {
        let dim = NSPopUpButton()
        dim.addItems(withTitles: ["Subtle", "Medium", "Strong"])
        dim.selectItem(at: GlyphSettings.dimChoices.firstIndex(of: GlyphSettings.dim) ?? 1)
        dim.target = self; dim.action = #selector(dimChanged(_:))

        let anchor = NSPopUpButton()
        anchor.addItems(withTitles: ["Top", "Center", "Middle"])
        anchor.selectItem(at: GlyphSettings.anchorChoices.firstIndex(of: GlyphSettings.anchor) ?? 1)
        anchor.target = self; anchor.action = #selector(anchorChanged(_:))

        let remember = NSButton(checkboxWithTitle: "Remember Focus & Typewriter across launches",
                                target: self, action: #selector(rememberChanged(_:)))
        remember.state = GlyphSettings.remember ? .on : .off

        func field(_ label: String, _ control: NSView, _ cap: String) -> NSView {
            let row = NSStackView(views: [rightLabel(label), control])
            row.orientation = .horizontal; row.spacing = 10; row.alignment = .firstBaseline
            let c = caption(cap)
            let capBox = NSStackView(views: [c]); capBox.edgeInsets = NSEdgeInsets(top: 0, left: 128, bottom: 0, right: 0)
            let col = NSStackView(views: [row, capBox]); col.orientation = .vertical
            col.alignment = .leading; col.spacing = 3
            return col
        }
        let rememberBox = NSStackView(views: [remember,
            { let c = caption("Reopen documents with the modes you left enabled."); let b = NSStackView(views: [c]); b.edgeInsets = NSEdgeInsets(top: 0, left: 20, bottom: 0, right: 0); return b }()])
        rememberBox.orientation = .vertical; rememberBox.alignment = .leading; rememberBox.spacing = 3

        let stack = NSStackView(views: [
            sectionTitle("FOCUS & TYPEWRITER"),
            field("Dim intensity:", dim, "How strongly non-focused paragraphs fade in Focus mode."),
            field("Typewriter line:", anchor, "Where the current line sits when Typewriter centering is on."),
            rememberBox,
        ])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        let container = NSView()
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 26),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -26),
            container.widthAnchor.constraint(equalToConstant: kSettingsContentWidth),
        ])
        self.view = container
    }

    @objc private func dimChanged(_ s: NSPopUpButton) {
        GlyphSettings.defaults.set(GlyphSettings.dimChoices[s.indexOfSelectedItem], forKey: GlyphSettings.dimKey); GlyphSettings.notifyChanged()
    }
    @objc private func anchorChanged(_ s: NSPopUpButton) {
        GlyphSettings.defaults.set(GlyphSettings.anchorChoices[s.indexOfSelectedItem], forKey: GlyphSettings.anchorKey); GlyphSettings.notifyChanged()
    }
    @objc private func rememberChanged(_ s: NSButton) {
        GlyphSettings.defaults.set(s.state == .on, forKey: GlyphSettings.rememberKey); GlyphSettings.notifyChanged()
    }
}

// MARK: - Typography tab (fonts + relative scale + live preview)

final class TypographySettingsViewController: NSViewController {
    private var headingFontPopup, bodyFontPopup, codeFontPopup, basePopup: NSPopUpButton!
    private var steppers: [NSStepper] = []
    private var remLabels: [NSTextField] = []
    private var pxLabels: [NSTextField] = []
    private let pvH1 = NSTextField(labelWithString: "Heading 1")
    private let pvH2 = NSTextField(labelWithString: "Heading 2")
    private let pvH3 = NSTextField(labelWithString: "Heading 3")
    private let pvPara = NSTextField(wrappingLabelWithString:
        "Body text scales from one base size, and every heading level follows in proportion.")
    private let pvCode = NSTextField(wrappingLabelWithString: "")

    override func loadView() {
        // --- Fonts section ---
        func fontPopup(_ choices: [String], _ current: String, _ action: Selector) -> NSPopUpButton {
            let p = NSPopUpButton(); p.addItems(withTitles: choices)
            p.selectItem(withTitle: current); p.target = self; p.action = action
            return p
        }
        headingFontPopup = fontPopup(GlyphSettings.headingFontChoices, GlyphSettings.headingFont, #selector(fontsChanged))
        bodyFontPopup = fontPopup(GlyphSettings.bodyFontChoices, GlyphSettings.bodyFont, #selector(fontsChanged))
        codeFontPopup = fontPopup(GlyphSettings.codeFontChoices, GlyphSettings.codeFont, #selector(fontsChanged))

        let fontGrid = NSGridView(views: [
            [rightLabel("Headings:", width: 90), headingFontPopup],
            [rightLabel("Body:", width: 90), bodyFontPopup],
            [rightLabel("Code:", width: 90), codeFontPopup],
        ])
        fontGrid.rowSpacing = 10; fontGrid.columnSpacing = 10
        fontGrid.column(at: 0).xPlacement = .trailing

        // --- Scale section ---
        basePopup = NSPopUpButton()
        basePopup.addItems(withTitles: GlyphSettings.bodyChoices.map { "\(Int($0)) px" })
        basePopup.selectItem(at: GlyphSettings.bodyChoices.firstIndex(of: GlyphSettings.bodyPx) ?? 2)
        basePopup.target = self; basePopup.action = #selector(scaleChanged(_:))
        let baseHint = NSTextField(labelWithString: "Body = 1rem")
        baseHint.font = .systemFont(ofSize: 11); baseHint.textColor = .secondaryLabelColor
        let baseRow = NSStackView(views: [rightLabel("Base size:", width: 90), basePopup, baseHint])
        baseRow.orientation = .horizontal; baseRow.spacing = 10; baseRow.alignment = .firstBaseline

        let names = ["H1", "H2", "H3", "H4", "H5", "H6"]
        var rows: [[NSView]] = [[headerCell("LEVEL", .left), headerCell("REM", .left), headerCell("SIZE", .left)]]
        for i in 0..<6 {
            let name = NSTextField(labelWithString: names[i]); name.font = .systemFont(ofSize: 13, weight: .semibold)
            let st = NSStepper(); st.minValue = 0.5; st.maxValue = 4; st.increment = 0.125
            st.doubleValue = GlyphSettings.headingRem(i); st.tag = i
            st.target = self; st.action = #selector(scaleChanged(_:))
            let rem = NSTextField(labelWithString: ""); rem.alignment = .right
            rem.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
            rem.widthAnchor.constraint(equalToConstant: 40).isActive = true
            // rem value + its stepper glued together, so the control sits by the field it changes
            let remGroup = NSStackView(views: [rem, st])
            remGroup.orientation = .horizontal; remGroup.spacing = 4; remGroup.alignment = .centerY
            let px = NSTextField(labelWithString: ""); px.textColor = .secondaryLabelColor
            px.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
            steppers.append(st); remLabels.append(rem); pxLabels.append(px)
            rows.append([name, remGroup, px])
        }
        let scaleGrid = NSGridView(views: rows)
        scaleGrid.rowSpacing = 10; scaleGrid.columnSpacing = 26
        scaleGrid.column(at: 0).width = 36

        let reset = NSButton(title: "Reset to defaults", target: self, action: #selector(resetDefaults(_:)))
        reset.bezelStyle = .rounded; reset.controlSize = .small

        let left = NSStackView(views: [
            sectionTitle("FONTS"), fontGrid,
            sectionTitle("RELATIVE TYPE SCALE"), baseRow, scaleGrid, reset,
        ])
        left.orientation = .vertical; left.alignment = .leading; left.spacing = 14
        left.setCustomSpacing(26, after: fontGrid)   // clear gap between Fonts and Scale groups

        // --- Preview: the heading hierarchy at true sizes + a body line + a code span ---
        let cardW: CGFloat = 320, pad: CGFloat = 20, textW = cardW - pad * 2
        [pvPara, pvCode].forEach {
            $0.lineBreakMode = .byWordWrapping
            $0.preferredMaxLayoutWidth = textW
            $0.widthAnchor.constraint(equalToConstant: textW).isActive = true
        }
        let previewStack = NSStackView(views: [pvH1, pvH2, pvH3, pvPara, pvCode])
        previewStack.orientation = .vertical; previewStack.alignment = .leading; previewStack.spacing = 6
        previewStack.setCustomSpacing(18, after: pvH3)   // gap between the heading hierarchy and body
        previewStack.setCustomSpacing(10, after: pvPara)
        let card = NSView(); card.wantsLayer = true
        card.layer?.backgroundColor = NSColor.textBackgroundColor.cgColor
        card.layer?.cornerRadius = 12; card.layer?.borderWidth = 1
        card.layer?.borderColor = NSColor.separatorColor.cgColor
        card.addSubview(previewStack)
        NSLayoutConstraint.activate([
            previewStack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: pad),
            previewStack.trailingAnchor.constraint(lessThanOrEqualTo: card.trailingAnchor, constant: -pad),
            previewStack.topAnchor.constraint(equalTo: card.topAnchor, constant: pad),
            previewStack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -pad),
            card.widthAnchor.constraint(equalToConstant: cardW),
        ])
        let preview = NSStackView(views: [sectionTitle("PREVIEW"), card])
        preview.orientation = .vertical; preview.alignment = .leading; preview.spacing = 10

        let columns = NSStackView(views: [left, preview])
        columns.orientation = .horizontal; columns.alignment = .top; columns.spacing = 34
        columns.translatesAutoresizingMaskIntoConstraints = false
        let container = NSView(); container.addSubview(columns)
        NSLayoutConstraint.activate([
            columns.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 28),
            columns.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -28),
            columns.topAnchor.constraint(equalTo: container.topAnchor, constant: 26),
            columns.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -26),
            container.widthAnchor.constraint(equalToConstant: kSettingsContentWidth),
        ])
        self.view = container
        refresh()
    }

    private func headerCell(_ t: String, _ align: NSTextAlignment = .left) -> NSTextField {
        let l = NSTextField(labelWithString: t)
        l.font = .systemFont(ofSize: 10, weight: .semibold)
        l.textColor = .tertiaryLabelColor
        l.alignment = align
        return l
    }

    private var base: Double { GlyphSettings.bodyChoices[basePopup.indexOfSelectedItem] }

    private func refresh() {
        let b = base
        let headingName = headingFontPopup.titleOfSelectedItem ?? "New York"
        let bodyName = bodyFontPopup.titleOfSelectedItem ?? "System"
        let codeName = codeFontPopup.titleOfSelectedItem ?? "SF Mono"
        for i in 0..<6 {
            let rem = steppers[i].doubleValue
            remLabels[i].stringValue = String(format: "%.3g", rem)
            pxLabels[i].stringValue = "\(Int((rem * b).rounded()))px"
        }
        let hViews = [pvH1, pvH2, pvH3]
        for (i, v) in hViews.enumerated() {
            v.font = GlyphSettings.nsFont(headingName, size: steppers[i].doubleValue * b, bold: true)
            v.textColor = .labelColor
        }
        let bodyF = GlyphSettings.nsFont(bodyName, size: b, bold: false)
        pvPara.font = bodyF; pvPara.textColor = .labelColor
        // Body line with an inline-code span (shows the code font + color, like the editor).
        let codeF = GlyphSettings.nsFont(codeName, size: b * 0.95, bold: false)
        let line = NSMutableAttributedString(string: "Tune ", attributes: [.font: bodyF, .foregroundColor: NSColor.labelColor])
        line.append(NSAttributedString(string: "bodyPx", attributes: [.font: codeF, .foregroundColor: NSColor.systemRed]))
        line.append(NSAttributedString(string: " and the whole scale follows.", attributes: [.font: bodyF, .foregroundColor: NSColor.labelColor]))
        pvCode.attributedStringValue = line
    }

    private func persistAndPush() {
        GlyphSettings.defaults.set(base, forKey: GlyphSettings.bodyPxKey)
        for i in 0..<6 { GlyphSettings.defaults.set(steppers[i].doubleValue, forKey: GlyphSettings.headingKeys[i]) }
        GlyphSettings.defaults.set(headingFontPopup.titleOfSelectedItem, forKey: GlyphSettings.headingFontKey)
        GlyphSettings.defaults.set(bodyFontPopup.titleOfSelectedItem, forKey: GlyphSettings.bodyFontKey)
        GlyphSettings.defaults.set(codeFontPopup.titleOfSelectedItem, forKey: GlyphSettings.codeFontKey)
        GlyphSettings.notifyChanged()
    }

    @objc private func scaleChanged(_ s: Any) { refresh(); persistAndPush() }
    @objc private func fontsChanged(_ s: Any) { refresh(); persistAndPush() }
    @objc private func resetDefaults(_ s: NSButton) {
        basePopup.selectItem(at: GlyphSettings.bodyChoices.firstIndex(of: 16) ?? 2)
        for i in 0..<6 { steppers[i].doubleValue = GlyphSettings.headingDefaults[i] }
        headingFontPopup.selectItem(withTitle: "New York")
        bodyFontPopup.selectItem(withTitle: "System")
        codeFontPopup.selectItem(withTitle: "SF Mono")
        refresh(); persistAndPush()
    }
}
