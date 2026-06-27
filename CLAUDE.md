# Glyph

A pure **WYSIWYG Markdown editor for macOS**. Open, read, and edit `.md` files with
live rich-text rendering while the file on disk stays plain, portable Markdown.

- **Name:** Glyph
- **Owner:** paolobozzola (paolo.bozzola@moviri.com)
- **Repo:** github.com/paolobozzola/glyph (private initially)
- **Status:** Planning. No application code yet — see `docs/PLAN.md`.

## Product principle

The `.md` file is the **single source of truth**. The editor is a view over the text,
never the other way around. We never persist editor-internal state (e.g. ProseMirror
JSON) to disk — only Markdown.

## Stack decisions (locked)

| Layer | Choice | Why |
|-------|--------|-----|
| App shell | Swift + SwiftUI `DocumentGroup` (`FileDocument`) | Native document model: tabs, multi-window, open/save panels, recent files, dirty-state, all for free |
| Editing engine | **Milkdown** (ProseMirror + remark) in a `WKWebView` | Only mainstream web editor that is Markdown-first; faithful round-trip via remark |
| Markdown flavor | CommonMark + GFM (`remark-gfm`) | Tables, task lists, strikethrough, autolinks |
| Editor bundle | Vite build, bundled in-app, loaded via custom `WKURLSchemeHandler` (`app://`) | No network at runtime; avoids `file://` WebKit restrictions |
| Quick Look | Quick Look Preview Extension (separate app extension target) | Spacebar preview of `.md` in Finder |
| Distribution | Developer ID + notarize + staple, DMG; Sparkle for updates | Direct download, no sandbox → full filesystem access |

Architecture chosen: **hybrid** (native shell + embedded web engine). Rejected pure-native
TextKit (editor too costly to hand-build) and Tauri/Electron (not Mac-idiomatic enough).

## Swift ⇄ JS bridge contract

- Swift → JS: `evaluateJavaScript` to load a document's Markdown into the editor.
- JS → Swift: `WKScriptMessageHandler` posts changes back, **debounced ~300ms**;
  Swift updates the document model and sets the dirty flag.
- Native menu/shortcuts (Cmd+B/I, headings, save) call editor commands over the bridge.
- ProseMirror owns undo/redo (Cmd+Z routed to it, not native).

## Known risk to manage early

**Markdown round-trip fidelity.** Milkdown normalizes some syntax (list markers `*`↔`-`,
wrapping, trailing whitespace). Policy: **normalize on save, rules explicit/configurable.**
Validate against a corpus of real `.md` files *before* building features on top.

## Brand

- Mark: a single "G" — a clean ink bowl whose defining crossbar is struck in gold. The
  gold is the stroke that turns the C into a G. Theme: inscription / illuminated letter.
- Palette: ink `#1A1822`, illuminated gold `#E6B450`, paper `#F5F1E8`, muted `#6B6678`.
- Assets in `assets/logo/`.
