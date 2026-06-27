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
- [ ] **macOS Quick Look integration** — spacebar in Finder previews `.md` rendered
      (Quick Look Preview Extension target; renders Markdown → styled HTML)
- [ ] **App logo / icon** (see §4) wired into `.icns` and the app target
- [ ] **GitHub repo** `paolobozzola/glyph`, private initially (see §5)

### v1.x — polish
- [ ] Image handling: paste/drag → save to sibling assets folder, insert relative link
- [ ] Export to HTML and PDF (print pipeline)
- [ ] Word/char count, outline/TOC popover, focus / typewriter mode
- [ ] Source ⇄ WYSIWYG toggle (raw-Markdown view for power users)
- [ ] YAML frontmatter shown as an editable header block

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

- **Concept:** a letterform with a cursor — an open ring "G" with a gold text-caret bar
  sitting in the opening. Reads as "G" + the blinking insertion point of a text editor.
  Theme: inscription / illuminated letter (the carved/illuminated *glyph*).
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
