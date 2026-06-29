# V2.1 content round-trip corpus

Open in Glyph, make no edits, save, and `diff` against this file. Everything here uses
features already bundled in the editor (code highlighting, math, footnotes, tables).

## Highlighted code

```swift
func greet(_ name: String) -> String {
    "Hello, \(name)"
}
```

```js
const sum = (a, b) => a + b;
```

## Math

Inline math like $E = mc^2$ sits in a sentence. Block math stands alone:

$$
\int_0^\infty e^{-x^2}\,dx = \frac{\sqrt{\pi}}{2}
$$

## Footnotes

Glyph supports footnotes[^note] via the GFM preset.

[^note]: This is the footnote definition; it round-trips as plain Markdown.

## Table

| Feature | Status |
| ------- | ------ |
| Code    | yes    |
| Math    | yes    |

End.
