---
title: Welcome to Glyph
author: Paolo Bozzola
tags: [markdown, macos, demo]
draft: false
---

# Welcome to Glyph 👋

This document is a **live tour** of what Glyph can do. The properties box above is this
file's *YAML frontmatter* — edit it as fields, and it saves back as plain YAML.

> The `.md` file is the single source of truth — the editor is just a view over the text.

## Text formatting

You can write **bold**, *italic*, ~~strikethrough~~, and `inline code`. Links look like
[this](https://github.com/paolobozzola/glyph). Select any text to get the formatting
pop-up — it includes **H1 / H2 / H3** buttons.

## Lists & tasks

- Bulleted lists
  - with nesting
- and more items

1. Numbered lists
2. in order

- [x] A completed task
- [ ] A task still to do

## Highlighted code

```swift
func greet(_ name: String) -> String {
    "Hello, \(name)"
}
```

```js
const sum = (a, b) => a + b;
console.log(sum(2, 3));
```

## Math

Inline math such as $E = mc^2$ flows in a sentence. Block math stands on its own:

$$
\int_0^\infty e^{-x^2}\,dx = \frac{\sqrt{\pi}}{2}
$$

## Footnotes

Glyph supports footnotes[^1] that round-trip as plain Markdown.

[^1]: This is the footnote text — it lives at the bottom of the source file.

## Tables

| Feature        | Shortcut        | Status |
| -------------- | --------------- | ------ |
| Find & Replace | ⌘F / ⌥⌘F        | ✅      |
| Outline        | ⌥⌘O             | ✅      |
| Markdown source| ⌥⌘M             | ✅      |
| Cheat sheet    | ⇧⌘H             | ✅      |

## Try these

- Press **⇧⌘H** for the full cheat sheet.
- Type `/` on an empty line for the insert menu.
- Toggle **Focus** and **Outline** from the status bar.
- Paste or drag an image straight into the editor — it's saved next to this file.

---

*Edit freely — this copy is regenerated each time you run `make run`.*
