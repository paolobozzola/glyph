import AppKit

/// Renders Markdown to a styled `NSAttributedString`, fully in-process (no web view).
///
/// Uses Foundation's `AttributedString(markdown:)` to parse CommonMark/GFM, then walks the
/// runs — grouped into blocks by their `presentationIntent` — and applies native fonts,
/// colors, and paragraph styles. Colors are semantic (`.textColor`, `.textBackgroundColor`)
/// so the preview follows light/dark automatically. This is deliberately simpler than the
/// full editor: the goal is a fast, reliable, readable Quick Look preview that can't hang.
enum MarkdownPreviewRenderer {

    private static let bodySize: CGFloat = 13

    static func attributedString(from markdown: String) -> NSAttributedString {
        let body = strippingFrontmatter(markdown)
        let parsed: AttributedString
        do {
            parsed = try AttributedString(
                markdown: body,
                options: .init(
                    allowsExtendedAttributes: true,
                    interpretedSyntax: .full,
                    failurePolicy: .returnPartiallyParsedIfPossible
                )
            )
        } catch {
            // Parsing should not fail with the lenient policy, but never leave a blank preview.
            return NSAttributedString(
                string: body,
                attributes: [.font: NSFont.systemFont(ofSize: bodySize),
                             .foregroundColor: NSColor.textColor]
            )
        }

        let out = NSMutableAttributedString()
        let blks = blocks(of: parsed)
        var i = 0
        while i < blks.count {
            // A GFM table arrives as many one-cell blocks; batch them into rows.
            if let info = tableInfo(blks[i]) {
                var cells: [(TableInfo, [Inline])] = []
                let tableId = info.tableId
                while i < blks.count, let inf = tableInfo(blks[i]), inf.tableId == tableId {
                    cells.append((inf, blks[i].inlines))
                    i += 1
                }
                out.append(renderTable(cells))
            } else {
                out.append(render(block: blks[i]))
                i += 1
            }
        }
        if out.length == 0 {
            out.append(NSAttributedString(string: " "))
        }
        return out
    }

    /// Drop a leading YAML frontmatter block (`---` … `---`/`...`) so the preview starts at
    /// the document body — the app surfaces frontmatter in its own properties panel.
    private static func strippingFrontmatter(_ text: String) -> String {
        var lines = text.components(separatedBy: "\n")
        guard let first = lines.first, first.trimmingCharacters(in: .whitespaces) == "---" else {
            return text
        }
        for i in 1..<lines.count {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
            if trimmed == "---" || trimmed == "..." {
                lines.removeSubrange(0...i)
                // Skip blank lines left between the frontmatter and the body.
                while let l = lines.first, l.trimmingCharacters(in: .whitespaces).isEmpty {
                    lines.removeFirst()
                }
                return lines.joined(separator: "\n")
            }
        }
        return text   // no closing fence — treat the whole thing as body
    }

    // MARK: - Block grouping

    private struct Inline {
        let text: String
        let intent: InlinePresentationIntent
        let link: URL?
    }
    private struct Block {
        let intent: PresentationIntent?
        var inlines: [Inline]
    }

    /// Group adjacent runs sharing the same `presentationIntent` into one block.
    private static func blocks(of attr: AttributedString) -> [Block] {
        var result: [Block] = []
        for run in attr.runs {
            let text = String(attr[run.range].characters)
            if text.isEmpty { continue }
            let inline = Inline(text: text,
                                intent: run.inlinePresentationIntent ?? [],
                                link: run.link)
            if var last = result.last, last.intent == run.presentationIntent {
                last.inlines.append(inline)
                result[result.count - 1] = last
            } else {
                result.append(Block(intent: run.presentationIntent, inlines: [inline]))
            }
        }
        return result
    }

    // MARK: - Block rendering

    private static func render(block: Block) -> NSAttributedString {
        let kinds = block.intent?.components.map(\.kind) ?? [.paragraph]

        // Header
        if let level = kinds.firstHeaderLevel {
            return paragraph(inlines: block.inlines,
                             baseFont: headerFont(level: level),
                             style: headerParagraphStyle(level: level))
        }
        // Thematic break
        if kinds.contains(where: { if case .thematicBreak = $0 { return true }; return false }) {
            let p = NSMutableParagraphStyle()
            p.paragraphSpacing = 12; p.paragraphSpacingBefore = 12
            return NSAttributedString(string: "––––––––––\n",
                                      attributes: [.font: NSFont.systemFont(ofSize: bodySize),
                                                   .foregroundColor: NSColor.tertiaryLabelColor,
                                                   .paragraphStyle: p])
        }
        // Code block — a single full-width shaded block (via NSTextBlock), not a ragged
        // per-line background box.
        if kinds.contains(where: { if case .codeBlock = $0 { return true }; return false }) {
            var text = block.inlines.map(\.text).joined()
            while text.hasSuffix("\n") { text.removeLast() }
            return codeBlockString(text)
        }
        // List item
        if let ordinal = kinds.listItemOrdinal {
            let depth = max(1, kinds.listDepth)
            let indent = CGFloat(depth) * 24
            let p = NSMutableParagraphStyle()
            p.firstLineHeadIndent = indent
            p.headIndent = indent + 18
            p.tabStops = [NSTextTab(textAlignment: .left, location: indent + 18)]
            p.paragraphSpacing = 3

            // GFM task list: "[ ] …" / "[x] …" → checkbox glyph, with the marker stripped.
            var inlines = block.inlines
            var marker = kinds.isOrdered ? "\(ordinal).\t" : "•\t"
            if let first = inlines.first {
                if first.text.hasPrefix("[ ] ") {
                    marker = "☐\t"
                    inlines[0] = Inline(text: String(first.text.dropFirst(4)),
                                        intent: first.intent, link: first.link)
                } else if first.text.hasPrefix("[x] ") || first.text.hasPrefix("[X] ") {
                    marker = "☑\t"
                    inlines[0] = Inline(text: String(first.text.dropFirst(4)),
                                        intent: first.intent, link: first.link)
                }
            }
            let line = NSMutableAttributedString(
                string: marker,
                attributes: [.font: NSFont.systemFont(ofSize: bodySize),
                             .foregroundColor: NSColor.secondaryLabelColor,
                             .paragraphStyle: p])
            line.append(inlineRun(inlines, baseFont: NSFont.systemFont(ofSize: bodySize),
                                  paragraphStyle: p))
            line.append(NSAttributedString(string: "\n"))
            return line
        }
        // Block quote
        if kinds.contains(where: { if case .blockQuote = $0 { return true }; return false }) {
            let p = NSMutableParagraphStyle()
            p.firstLineHeadIndent = 16; p.headIndent = 16
            p.paragraphSpacing = 8; p.paragraphSpacingBefore = 4
            return paragraph(inlines: block.inlines,
                             baseFont: NSFont.systemFont(ofSize: bodySize),
                             style: p,
                             color: .secondaryLabelColor)
        }
        // Plain paragraph
        let p = NSMutableParagraphStyle()
        p.paragraphSpacing = 10; p.lineSpacing = 2
        return paragraph(inlines: block.inlines,
                         baseFont: NSFont.systemFont(ofSize: bodySize),
                         style: p)
    }

    // MARK: - Tables

    private struct TableInfo {
        let tableId: Int
        let row: Int      // -1 for the header row
        let column: Int
        var isHeader: Bool { row < 0 }
    }

    /// Return table position for a block whose intent includes a table cell, else nil.
    private static func tableInfo(_ block: Block) -> TableInfo? {
        guard let components = block.intent?.components else { return nil }
        var tableId: Int?, column: Int?, row = 0, isHeader = false, sawCell = false
        for c in components {
            switch c.kind {
            case .table:                        tableId = c.identity
            case .tableHeaderRow:               isHeader = true
            case .tableRow(let idx):            row = idx
            case .tableCell(let col):           column = col; sawCell = true
            default:                            break
            }
        }
        guard sawCell, let tid = tableId, let col = column else { return nil }
        return TableInfo(tableId: tid, row: isHeader ? -1 : row, column: col)
    }

    /// Lay a batch of table cells out as aligned rows (header bold + a rule beneath it).
    private static func renderTable(_ cells: [(TableInfo, [Inline])]) -> NSAttributedString {
        let numColumns = max(1, (cells.map { $0.0.column }.max() ?? 0) + 1)
        let colWidth = max(80, min(190, 560 / CGFloat(numColumns)))
        let maxChars = max(8, Int(colWidth / 7))

        // Preserve encounter order of rows (header first as parsed).
        var rowOrder: [Int] = []
        var rows: [Int: [Int: [Inline]]] = [:]
        for (info, inlines) in cells {
            if rows[info.row] == nil { rows[info.row] = [:]; rowOrder.append(info.row) }
            rows[info.row]?[info.column] = inlines
        }

        let p = NSMutableParagraphStyle()
        p.tabStops = (1..<max(1, numColumns)).map {
            NSTextTab(textAlignment: .left, location: colWidth * CGFloat($0))
        }
        p.lineBreakMode = .byTruncatingTail
        p.paragraphSpacing = 2
        let topPad = NSMutableParagraphStyle(); topPad.paragraphSpacingBefore = 8; topPad.paragraphSpacing = 2
        topPad.tabStops = p.tabStops; topPad.lineBreakMode = .byTruncatingTail

        let out = NSMutableAttributedString()
        for (n, r) in rowOrder.enumerated() {
            let isHeader = r < 0
            let base = isHeader
                ? NSFont.systemFont(ofSize: bodySize, weight: .semibold)
                : NSFont.systemFont(ofSize: bodySize)
            let style = n == 0 ? topPad : p
            let line = NSMutableAttributedString()
            for col in 0..<numColumns {
                if col > 0 { line.append(NSAttributedString(string: "\t")) }
                let inlines = rows[r]?[col] ?? []
                let plain = inlines.map(\.text).joined()
                if plain.count > maxChars {
                    let clipped = String(plain.prefix(maxChars - 1)) + "…"
                    line.append(NSAttributedString(string: clipped,
                        attributes: [.font: base, .foregroundColor: NSColor.textColor,
                                     .paragraphStyle: style]))
                } else {
                    line.append(inlineRun(inlines, baseFont: base, paragraphStyle: style))
                }
            }
            line.append(NSAttributedString(string: "\n"))
            out.append(line)

            if isHeader {  // rule under the header row
                let rule = NSMutableParagraphStyle(); rule.paragraphSpacing = 4
                out.append(NSAttributedString(
                    string: String(repeating: "─", count: min(60, numColumns * 10)) + "\n",
                    attributes: [.font: NSFont.systemFont(ofSize: bodySize - 3),
                                 .foregroundColor: NSColor.tertiaryLabelColor,
                                 .paragraphStyle: rule]))
            }
        }
        return out
    }

    private static func paragraph(inlines: [Inline], baseFont: NSFont,
                                  style: NSParagraphStyle,
                                  color: NSColor = .textColor) -> NSAttributedString {
        let s = NSMutableAttributedString()
        s.append(inlineRun(inlines, baseFont: baseFont, paragraphStyle: style, color: color))
        s.append(NSAttributedString(string: "\n"))
        return s
    }

    /// Apply inline styling (bold / italic / code / strikethrough / links) to a run of inlines.
    private static func inlineRun(_ inlines: [Inline], baseFont: NSFont,
                                  paragraphStyle: NSParagraphStyle,
                                  color: NSColor = .textColor) -> NSAttributedString {
        let out = NSMutableAttributedString()
        for inline in inlines {
            let bold = inline.intent.contains(.stronglyEmphasized)
            let italic = inline.intent.contains(.emphasized)
            let isCode = inline.intent.contains(.code)

            var font = baseFont
            if isCode {
                font = NSFont.monospacedSystemFont(ofSize: baseFont.pointSize - 1, weight: .regular)
            } else {
                if bold { font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask) }
                if italic { font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask) }
            }

            var attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: isCode ? codeInlineColor : color,
                .paragraphStyle: paragraphStyle,
            ]
            if inline.intent.contains(.strikethrough) {
                attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            }
            if let link = inline.link {
                attrs[.foregroundColor] = NSColor.linkColor
                attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
                attrs[.link] = link
            }
            out.append(NSAttributedString(string: inline.text, attributes: attrs))
        }
        return out
    }

    // MARK: - Code

    /// Inline `code` — colored monospace (like the editor), no background box.
    private static let codeInlineColor = NSColor.systemRed

    /// A fenced code block as one full-width shaded region (NSTextBlock fills the whole
    /// paragraph rectangle, so it reads as a single block instead of ragged per-line boxes).
    private static func codeBlockString(_ text: String) -> NSAttributedString {
        let block = NSTextBlock()
        block.setContentWidth(100, type: .percentageValueType)
        block.backgroundColor = NSColor.textColor.withAlphaComponent(0.055)
        block.setWidth(10, type: .absoluteValueType, for: .padding)
        let p = NSMutableParagraphStyle()
        p.textBlocks = [block]
        p.paragraphSpacingBefore = 10
        p.paragraphSpacing = 10
        p.lineSpacing = 2
        // Join lines with U+2028 (line separator) so the block is ONE paragraph — otherwise
        // paragraphSpacing lands between every code line and the block looks double-spaced.
        let oneParagraph = text.replacingOccurrences(of: "\n", with: "\u{2028}")
        return NSAttributedString(string: oneParagraph + "\n", attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: bodySize - 1, weight: .regular),
            .foregroundColor: NSColor.textColor,
            .paragraphStyle: p])
    }

    // MARK: - Fonts / styles

    private static func headerFont(level: Int) -> NSFont {
        let size: CGFloat
        switch level {
        case 1: size = 26
        case 2: size = 21
        case 3: size = 17
        default: size = 15
        }
        return NSFont.systemFont(ofSize: size, weight: .semibold)
    }

    private static func headerParagraphStyle(level: Int) -> NSParagraphStyle {
        let p = NSMutableParagraphStyle()
        p.paragraphSpacingBefore = level <= 2 ? 16 : 12
        p.paragraphSpacing = 6
        return p
    }
}

private extension Array where Element == PresentationIntent.Kind {
    var firstHeaderLevel: Int? {
        for k in self { if case .header(let level) = k { return level } }
        return nil
    }
    var listItemOrdinal: Int? {
        for k in self { if case .listItem(let ordinal) = k { return ordinal } }
        return nil
    }
    var isOrdered: Bool {
        contains { if case .orderedList = $0 { return true }; return false }
    }
    var listDepth: Int {
        reduce(0) { count, k in
            switch k {
            case .orderedList, .unorderedList: return count + 1
            default: return count
            }
        }
    }
}
