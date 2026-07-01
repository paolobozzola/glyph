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
        for block in blocks(of: parsed) {
            out.append(render(block: block))
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
        // Code block
        if kinds.contains(where: { if case .codeBlock = $0 { return true }; return false }) {
            let p = NSMutableParagraphStyle()
            p.firstLineHeadIndent = 12; p.headIndent = 12
            p.paragraphSpacing = 8; p.paragraphSpacingBefore = 4
            let text = block.inlines.map(\.text).joined()
            return NSAttributedString(
                string: text.hasSuffix("\n") ? text : text + "\n",
                attributes: [.font: NSFont.monospacedSystemFont(ofSize: bodySize - 1, weight: .regular),
                             .foregroundColor: NSColor.textColor,
                             .backgroundColor: NSColor.quaternaryLabelColor.withAlphaComponent(0.35),
                             .paragraphStyle: p])
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
            let marker = kinds.isOrdered ? "\(ordinal).\t" : "•\t"
            let line = NSMutableAttributedString(
                string: marker,
                attributes: [.font: NSFont.systemFont(ofSize: bodySize),
                             .foregroundColor: NSColor.secondaryLabelColor,
                             .paragraphStyle: p])
            line.append(inlineRun(block.inlines, baseFont: NSFont.systemFont(ofSize: bodySize),
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
                .foregroundColor: color,
                .paragraphStyle: paragraphStyle,
            ]
            if isCode {
                attrs[.backgroundColor] = NSColor.quaternaryLabelColor.withAlphaComponent(0.35)
            }
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
