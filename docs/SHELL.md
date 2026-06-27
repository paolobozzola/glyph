# Glyph — Shell Build Spec (M0–M1)

How to build the first native shell: a document-based macOS app that hosts the Milkdown
editor and round-trips Markdown faithfully. This is the blueprint for the first coding
sessions. For locked decisions see `../CLAUDE.md`; for the roadmap see `PLAN.md`.

---

## 0. Toolchain

- **Xcode 16+** (macOS 15 SDK). Deployment target **macOS 15 Sequoia**.
- **Node 20+** + npm — only to build the editor web bundle (not needed at app runtime).
- Apple Developer Program account (for signing/notarization later; not needed to build locally).

## 1. Targets

| Target | Type | Role |
|--------|------|------|
| `Glyph` | macOS App (SwiftUI) | The editor app shell |
| `GlyphQuickLookPreview` | Quick Look Preview Extension | Spacebar preview of `.md` |
| `GlyphQuickLookThumbnail` | Quick Look Thumbnail Extension | Finder thumbnails for `.md` |
| `GlyphRender` | local Swift Package | Shared Markdown→styled-HTML renderer used by app + both extensions |

A Quick Look extension hosts exactly one extension point, so preview and thumbnail are two
separate `.appex` targets; both depend on `GlyphRender` so the rendered look is identical
everywhere (and matches the editor theme CSS).

## 2. Repository layout (target state)

```
glyph/
├─ Glyph.xcodeproj
├─ Glyph/                      # app target
│  ├─ GlyphApp.swift           # @main, DocumentGroup
│  ├─ MarkdownDocument.swift   # ReferenceFileDocument (UTType .markdown)
│  ├─ EditorWebView.swift      # NSViewRepresentable wrapping WKWebView
│  ├─ EditorBridge.swift       # WKScriptMessageHandler + JS command API
│  ├─ AppCommands.swift        # menu/shortcut → editor commands
│  ├─ Assets.xcassets          # AppIcon (from assets/logo/Glyph.iconset)
│  ├─ Info.plist               # UTI / document-type declarations (§5)
│  └─ Resources/editor/        # built Milkdown bundle (copied from web/dist)
├─ GlyphQuickLookPreview/
├─ GlyphQuickLookThumbnail/
├─ Packages/GlyphRender/       # SwiftPM: Markdown -> HTML (+ shared theme CSS)
├─ web/                        # editor source (built into Glyph/Resources/editor)
│  ├─ package.json  vite.config.ts
│  └─ src/ (Milkdown + remark-gfm, slash menu, input rules, theme)
└─ assets/logo/                # marks + AppIcon.icns (done)
```

## 3. Document model

Use **`ReferenceFileDocument`** (a class / `ObservableObject`), not the value-type
`FileDocument` — an editor wants a stable mutable model and a long-lived `WKWebView`.

- `readableContentTypes = [.markdown]` (see §5 for the `UTType`).
- `init(configuration:)` reads file `Data` → UTF-8 `String` (the Markdown text).
- `snapshot(contentType:)` returns the current Markdown string; `fileWrapper(snapshot:)`
  writes it back. This is what enables **autosave-in-place + Versions** for free.
- The document holds `@Published var markdown: String` — the **single source of truth**.

## 4. Editor host + bridge

**Lifecycle rule (critical):** load the document's Markdown into the `WKWebView`
**once**, when the document opens. Do **not** push model→webview on every keystroke — that
would reset the caret. Flow during editing is **JS → Swift only**. Only re-load the webview
on explicit revert / external-file reload.

- `EditorWebView: NSViewRepresentable`
  - `makeNSView`: create `WKWebView` with a `WKWebViewConfiguration` that registers a
    `WKURLSchemeHandler` for `app://` (serves `Resources/editor/`), and a
    `WKScriptMessageHandler` named e.g. `glyph`. Enable `isContinuousSpellCheckingEnabled`.
    Load `app://editor/index.html`.
  - `updateNSView`: **no-op for content**; only react to commands (bold/italic/…) by
    calling JS, never by reloading.

**Bridge protocol** (see also CLAUDE.md):
- JS → Swift (`window.webkit.messageHandlers.glyph.postMessage(...)`):
  - `{type:"ready"}` — editor mounted; Swift then sends the initial Markdown.
  - `{type:"change", markdown:"..."}` — debounced ~300ms; Swift sets `document.markdown` + dirty.
- Swift → JS (`evaluateJavaScript`):
  - `glyph.setMarkdown(text)` — load a document (initial open / revert).
  - `glyph.cmd("toggleBold" | "toggleItalic" | "heading:2" | "insertTable" | …)` — menu commands.
  - `glyph.setTheme("light"|"dark")` — follow system appearance.

## 5. File-type association (Info.plist)

Import the de-facto Markdown UTI and register Glyph as an editor so double-click and
"Open With" work, and the Quick Look extensions bind to it.

```xml
<key>UTImportedTypeDeclarations</key>
<array><dict>
  <key>UTTypeIdentifier</key><string>net.daringfireball.markdown</string>
  <key>UTTypeConformsTo</key><array><string>public.plain-text</string></array>
  <key>UTTypeDescription</key><string>Markdown Document</string>
  <key>UTTypeTagSpecification</key><dict>
    <key>public.filename-extension</key>
    <array><string>md</string><string>markdown</string><string>mdown</string><string>markdn</string></array>
  </dict>
</dict></array>

<key>CFBundleDocumentTypes</key>
<array><dict>
  <key>CFBundleTypeName</key><string>Markdown Document</string>
  <key>LSItemContentTypes</key><array><string>net.daringfireball.markdown</string></array>
  <key>CFBundleTypeRole</key><string>Editor</string>
  <key>LSHandlerRank</key><string>Alternate</string>
</dict></array>
```

In Swift: `extension UTType { static let markdown = UTType(importedAs: "net.daringfireball.markdown") }`.

## 6. Editor web bundle (`web/`)

- Vite + TypeScript. Deps: `@milkdown/core`, `@milkdown/preset-commonmark`,
  `@milkdown/preset-gfm` (tables/tasklists/strikethrough), plus slash-menu + input-rule plugins.
- Build to a **single-file-ish** bundle (inline assets) so it loads over `app://` with no
  network. Output → `Glyph/Resources/editor/`. Add a build phase (or Makefile) that runs
  `npm --prefix web run build` before the app compiles.
- Expose a tiny `window.glyph` API matching §4 (`setMarkdown`, `getMarkdown`, `cmd`,
  `setTheme`, and the `change`/`ready` postMessage calls).

## 7. Native features — where each is wired

- **Autosave + Versions** → free from `ReferenceFileDocument` snapshot/write (§3).
- **State/window restoration** → `DocumentGroup` default; verify "reopen windows" works.
- **System text services** → `isContinuousSpellCheckingEnabled = true` on the `WKWebView`;
  emoji picker / Look Up / dictation come automatically inside web content.
- **Printing (⌘P)** → render current Markdown via `GlyphRender`, print the HTML (or
  `WKWebView.printOperation`); the same HTML path feeds PDF export later.
- **Share menu** → toolbar button → `NSSharingServicePicker` over the Markdown/HTML/PDF.
- **Quick Look** → both extensions call `GlyphRender` to produce styled HTML for preview /
  a rasterized thumbnail.

## 8. Milestones

- **M0 — Bridge spike (first session).** Minimal `DocumentGroup` app, hardcoded Markdown
  string loaded into Milkdown in a `WKWebView`, edits posted back to Swift and logged.
  *Acceptance:* type in the editor → Swift receives debounced Markdown that round-trips
  cleanly (run the fidelity check against a small `.md` corpus here, per CLAUDE.md risk).
- **M1 — Real documents.** `ReferenceFileDocument` wired to open/save real `.md`; dirty
  state; tabs; recent files; autosave + Versions; window restoration; file-type association;
  follow system light/dark. *Acceptance:* double-click a `.md` in Finder → opens in Glyph,
  edit, ⌘S writes valid Markdown, "Browse All Versions" works.
- **M2 — Editor completeness + natives.** GFM features, slash menu, input rules, native
  menus/shortcuts, find & replace, spellcheck, printing, share menu, external-change reload.
- **M3 — Quick Look.** Preview + thumbnail extensions on `GlyphRender`.
- **M4 — Packaging.** AppIcon, signing, notarize, DMG, Sparkle.

## 9. First coding session = M0

Scaffold the Xcode project (`Glyph` app target, macOS 15) + the `web/` Milkdown bundle, and
prove the bridge. Keep it ugly; the only goal is **faithful Markdown round-trip through the
WKWebView**. Everything else builds on a green M0.
```
