# Glyph

A pure **WYSIWYG Markdown editor for macOS**. Open, read, and edit `.md` files with live
rich-text rendering — while the file on disk stays plain, portable Markdown.

> Status: **planning**. No application code yet. See [`docs/PLAN.md`](docs/PLAN.md) and
> [`CLAUDE.md`](CLAUDE.md).

## At a glance

- **Native shell** — Swift + SwiftUI `DocumentGroup` (document-based, tabbed).
- **WYSIWYG engine** — Milkdown (ProseMirror + remark) in a `WKWebView`; Markdown-first round-trip.
- **The file is the source of truth** — never editor-internal JSON on disk.
- **Quick Look** — spacebar preview of `.md` in Finder.
- **Direct download** — Developer ID, notarized, DMG; Sparkle for updates.

## Repo layout

```
CLAUDE.md          Locked stack decisions, bridge contract, project memory
docs/PLAN.md       Roadmap, architecture, feature set, build order
docs/SHELL.md      Shell build spec: targets, document model, bridge, milestones
assets/logo/       Brand marks (SVG) + AppIcon.icns / .iconset
```
