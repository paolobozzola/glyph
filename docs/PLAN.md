# Glyph — Project Plan

A pure WYSIWYG Markdown editor for macOS. This document is the canonical roadmap.
For locked stack decisions and the bridge contract, see `../CLAUDE.md`.

---

## 1. Architecture overview

```
┌─────────────────────────────────────────────┐
│ Glyph.app (Swift / SwiftUI DocumentGroup)    │
│                                              │
│  FileDocument  ◄── source of truth (.md text)│
│      ▲  │                                    │
│      │  │ load markdown (evaluateJavaScript) │
│      │  ▼                                    │
│  ┌──────────────────────────────────────┐   │
│  │ WKWebView                            │   │
│  │   Milkdown (ProseMirror + remark)    │   │
│  │   ── change (debounced) ──► Swift     │   │
│  │      via WKScriptMessageHandler       │   │
│  └──────────────────────────────────────┘   │
│                                              │
│  Native menus/shortcuts ──► editor commands  │
└─────────────────────────────────────────────┘
   + Quick Look Preview Extension (own target)
```

The editor web bundle is built with Vite and shipped inside the app bundle, served
over a custom `app://` scheme handler.

## 2. Feature set

### MVP (v1.0) — the editor done right
- [ ] Open / edit / save `.md`; document tabs; recent files; drag file onto Dock icon
- [ ] WYSIWYG for GFM core: headings, bold/italic/strikethrough, ordered/unordered/**task**
      lists, links, images, blockquotes, inline code, fenced code blocks (syntax
      highlighting), tables, horizontal rules
- [ ] Slash command menu (`/`) to insert blocks
- [ ] Markdown input rules (`## ` → heading, `- ` → list, etc.)
- [ ] Native menu + keyboard shortcuts for all formatting
- [ ] Light/dark following the system; a couple of editor themes/fonts
- [ ] Find & replace
- [ ] Auto-save + dirty-state + external-change detection (reload prompt if file changed on disk)
- [ ] **App logo / icon** (see §4) wired into `.icns` and the app target — *done, in `assets/logo/`*
- [ ] **GitHub repo** `paolobozzola/glyph`, private initially (see §5) — *done*

#### MVP native macOS features
- [x] **File-type association / default app** — declare Markdown UTI; double-click & "Open With" → Glyph
- [x] **Quick Look preview** — Preview extension (WKWebView + markdown-it bundle over app://); renderer verified in browser. *Runtime activation needs a signed app installed in /Applications (M4).*
- [x] **Quick Look thumbnail** — Thumbnail extension (native CGContext text-on-page); drawing verified via bitmap harness. *Same activation caveat.*
- [x] **Document Versions + autosave-in-place** — `NSDocument.autosavesInPlace`; Revert to Saved
- [x] **Window & state restoration** — native window tabbing; system reopen-on-relaunch
- [x] **System text services in editor** — Spelling & Grammar submenu; Emoji/Look Up/dictation via WKWebView
- [x] **Printing (⌘P)** — `WKWebView.printOperation`
- [x] **Share menu** — `NSSharingServicePicker`
- [x] **Format menu** — bold/italic/strike/code/link, headings 1–6, lists, quote, code block, hr, table
- [x] **Find & replace** — in-editor find bar (prosemirror-search): ⌘F / ⌥⌘F / ⌘G / ⇧⌘G, match count, highlights, replace + replace-all

### v1.x — polish
- [ ] Image handling: paste/drag → save to sibling assets folder, insert relative link
- [x] Export to HTML and PDF (File ▸ Export; Milkdown `getHTML` + offscreen print-to-PDF)
- [ ] Word/char count, outline/TOC popover, focus / typewriter mode
- [ ] Source ⇄ WYSIWYG toggle (raw-Markdown view for power users)
- [ ] YAML frontmatter shown as an editable header block

### v2.0
- [ ] Sparkle auto-updates (appcast + EdDSA signing; host on GitHub Releases)

### Out of scope for a single-file app (revisit only if moving toward a vault)
- Folder sidebar, wiki-links/backlinks, global search, tags, plugin system

## 3. Quick Look integration — notes

- Implemented as a **Quick Look Preview Extension** (`.appex`) bundled in `Glyph.app`,
  declaring `public.plain-text` / a `net.daringfireball.markdown` UTI for `.md`/`.markdown`.
- The extension renders Markdown to styled HTML (reuse the same CSS/theme as the editor
  for visual consistency) and displays it in a preview view.
- Keep the renderer lightweight and synchronous-friendly; Quick Look budgets are tight.
- Also provide a Thumbnail Extension later (optional) for Finder icons.

## 4. Logo / brand

- **Concept:** a single "G" — a clean ink bowl (a C) whose defining **crossbar** is struck
  in gold. The gold is precisely the stroke that turns the C into a G. Theme: inscription /
  illuminated letter (the carved/illuminated *glyph*).
- **Palette:** ink `#1A1822`, illuminated gold `#E6B450`, paper `#F5F1E8`, muted `#6B6678`.
- **Assets:** `assets/logo/` — `glyph-mark-dark.svg`, `glyph-mark-light.svg`.
- **Next:** export `.icns` (16→1024 px) from the squircle tile for the app target.

## 5. Repository & release

- GitHub: `github.com/paolobozzola/glyph`, **private** initially; flip to public when ready.
- Branch model: trunk-based on `main` for now (solo).
- Distribution: Apple Developer Program → Developer ID signing → notarize + staple → DMG.
  **Sparkle** for auto-updates. (Sandbox not required for direct download.)

## 6. Suggested build order

1. Repo + docs + logo (this step).
2. Spike: minimal Swift `DocumentGroup` app embedding a `WKWebView` that round-trips a
   hardcoded Markdown string through Milkdown back to Swift. Proves the bridge + fidelity.
3. Real file open/save wired to the document model; dirty-state.
4. Editor feature completeness (GFM, slash menu, input rules, themes).
5. Native menus/shortcuts bridged to editor commands; find & replace.
6. Quick Look extension.
7. Packaging: icon, signing, notarization, DMG, Sparkle.
