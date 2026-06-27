# Glyph — Local Setup (M0)

How to build and run the M0 bridge spike on your Mac.

## Prerequisites

1. **Xcode 16+** (full Xcode, not just Command Line Tools). Install from the App Store,
   then run once and accept the license. Confirm:
   ```sh
   sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
   xcodebuild -version
   ```
2. **Node 20+** and **npm** (for building the editor bundle).
3. **XcodeGen** (generates the Xcode project from `project.yml`):
   ```sh
   brew install xcodegen
   ```

## Build & run

From the repo root:

```sh
make          # 1) builds the editor bundle  2) generates Glyph.xcodeproj
open Glyph.xcodeproj
```

In Xcode: select the **Glyph** scheme and press **⌘R**.

What `make` does:
- `make web` → `npm install` + `vite build` → emits one self-contained
  `Glyph/Resources/editor/index.html` (the Milkdown editor; works fully offline).
- `make project` → `xcodegen generate` → creates `Glyph.xcodeproj`.

> Both `Glyph.xcodeproj` and `Glyph/Resources/editor/` are generated and git-ignored.
> Re-run `make` after pulling changes or editing `web/` or `project.yml`.

## What M0 proves

A document window opens showing the Milkdown WYSIWYG editor. As you type, the Swift host
receives debounced Markdown over the bridge — visible in the Xcode console / Console.app:

```
[Glyph] change: 142 chars
```

That is the round-trip working: **edits in the web editor → Markdown back in Swift.**

## Round-trip fidelity check (the one real risk)

1. Run Glyph, **File ▸ Open** `tests/corpus/sample.md`.
2. Save it to a new file (don't edit anything).
3. `diff tests/corpus/sample.md /path/to/saved.md`

Differences are Milkdown's normalization (list markers, wrapping, trailing whitespace).
Decide the normalization policy here before building M1 features on top (see CLAUDE.md).

## Not in M0 yet

Saving/dirty-state, undo wiring, native menus, find & replace, Quick Look — those are
M1+ in `docs/PLAN.md`. M0 is intentionally just the bridge.

## Quick Look (preview + thumbnail)

The two extensions build and embed into `Glyph.app/Contents/PlugIns/`, but macOS only
**activates** Quick Look app extensions from a properly **signed** app in **/Applications**:

```sh
# build, copy to /Applications, then launch once so the system registers the extensions
xcodebuild -project Glyph.xcodeproj -scheme Glyph -configuration Release build
cp -R <DerivedData>/Build/Products/Release/Glyph.app /Applications/
open /Applications/Glyph.app
pluginkit -m | grep -i glyph     # should now list the preview + thumbnail extensions
```

Then in Finder: select a `.md` file and press **space** (preview), and view it in a folder
(thumbnail). Reliable activation really wants Developer ID signing — that's **M4**.

Notes:
- `qlmanage -p` cannot host app-extension previews (crashes in ExtensionFoundation); use Finder.
- Ad-hoc builds in DerivedData are **not** discovered by `pluginkit` — install to /Applications.
- **Free Personal-Team (Apple Development) signing runs the app fine but did not get the QL
  extensions registered by `pluginkit` on macOS Tahoe.** Reliable QL extension registration
  in practice needs **Developer ID + notarization** (M4). The extension code itself is
  verified (preview renders in a browser; thumbnail via a bitmap harness).
- **UTI ownership matters:** on a Mac with iA Writer installed, `.md` is typed as
  `net.ia.markdown` (not `net.daringfireball.markdown`). Glyph now declares
  `net.daringfireball.markdown`, `net.ia.markdown`, and `public.markdown` for both the
  document type and the QL extensions so it matches `.md` whoever typed it.

## Troubleshooting

- **Blank window** → the editor bundle wasn't built. Run `make web`, regenerate, rebuild.
- **`xcodegen: command not found`** → `brew install xcodegen`.
- **Web Inspector** → the web view is inspectable; right-click ▸ *Inspect Element*, or
  Safari ▸ Develop ▸ (your Mac) ▸ Glyph, to debug the editor.
