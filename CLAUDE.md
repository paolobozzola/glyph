# Glyph

A pure **WYSIWYG Markdown editor for macOS**. Open, read, and edit `.md` files with
live rich-text rendering while the file on disk stays plain, portable Markdown.

- **Name:** Glyph
- **Owner:** paolobozzola (paolo.bozzola@moviri.com)
- **Repo:** github.com/paolobozzola/glyph (private initially)
- **Status:** M0–M4 working. Editor, documents, formatting, find/replace, spelling, print,
  share, and **Quick Look preview + thumbnail now activate** (notarized Developer ID build;
  QL extensions must be sandboxed and must NOT carry `network.client` — see `docs/SETUP.md`).
  Release via `make dist` (`docs/RELEASE.md`). v1.x in progress: **HTML/PDF export done**.
  Sparkle auto-updates deferred to **v2.0**. Local dev: `make run` (recompile + launch).

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
| Deployment target | **macOS 15 Sequoia** minimum | Modern SwiftUI APIs, reasonable reach |
| Document model | **AppKit `NSDocument`** (programmatic menu, `main.swift` entry) | Decouples dirty-tracking (`updateChangeCount`) from undo so Milkdown keeps ⌘Z; gives autosave-in-place, Versions, tabs, recent files. *(Pivoted from SwiftUI `DocumentGroup` at M1 — SwiftUI couples dirty to the undo manager.)* |
| Quick Look | Two app-extension targets: **Preview** + **Thumbnail** | Spacebar preview *and* rendered Finder thumbnails |
| Shared rendering | Local Swift package **`GlyphRender`** (Markdown→styled HTML) used by app + both QL extensions | One renderer, consistent look everywhere |
| Distribution | Developer ID + notarize + staple, DMG; Sparkle for updates | Direct download, no sandbox → full filesystem access |

### MVP native macOS features (all in)
File-type association / default-app (Markdown UTI) · Document Versions + autosave-in-place ·
window/state restoration · in-editor system text services (spellcheck, emoji picker, Look Up,
dictation) · Printing (⌘P) · Quick Look **preview** + **thumbnail** · Share menu
(`NSSharingServicePicker`). Deferred to v1.x: Spotlight indexing, App Intents/Shortcuts,
system Services provider, iCloud (needs sandbox — conflicts with direct-download).

Architecture chosen: **hybrid** (native shell + embedded web engine). Rejected pure-native
TextKit (editor too costly to hand-build) and Tauri/Electron (not Mac-idiomatic enough).

## Swift ⇄ JS bridge contract

- Swift → JS: `evaluateJavaScript` to load a document's Markdown into the editor.
- JS → Swift: `WKScriptMessageHandler` posts changes back, **debounced ~300ms**;
  Swift updates the document model and sets the dirty flag.
- Native menu/shortcuts (Cmd+B/I, headings, save) call editor commands over the bridge.
- ProseMirror owns undo/redo (Cmd+Z routed to it, not native).

## Markdown round-trip — policy (decided at M2)

Milkdown re-serializes via remark, so saving normalizes. We configure
`remarkStringifyOptionsCtx` in the editor bundle: **`bullet: "-"`, `rule: "-"`,
`listItemIndent: "one"`**. Accepted residual normalization (Milkdown AST behavior, not
configurable via stringify options):
- Lists serialize **loose** (blank line between items).
- A freshly-inserted **empty** table cell / hr renders `<br />` until typed into.

This is deterministic; treat it as Glyph's canonical formatting. Verified with Playwright
against the built bundle (commands + round-trip).

## Brand

- Mark: a single "G" — a clean ink bowl whose defining crossbar is struck in gold. The
  gold is the stroke that turns the C into a G. Theme: inscription / illuminated letter.
- Palette: ink `#1A1822`, illuminated gold `#E6B450`, paper `#F5F1E8`, muted `#6B6678`.
- Assets in `assets/logo/`.
