# Glyph round-trip corpus

A document that exercises the GFM features the editor must preserve. Open it in Glyph,
make no edits, save, and `diff` against this file to measure normalization (see
docs/SHELL.md — Markdown round-trip is the one real risk).

## Inline

Plain text with **bold**, *italic*, ~~strikethrough~~, `inline code`, and a
[link](https://example.com).

## Lists

- Unordered one
- Unordered two
  - Nested
- [ ] Task open
- [x] Task done

1. Ordered one
2. Ordered two

## Quote

> A blockquote
> spanning two lines.

## Code

```swift
func greet(_ name: String) -> String {
    "Hello, \(name)"
}
```

## Table

| Feature | Status |
| ------- | ------ |
| Tables  | yes    |
| Tasks   | yes    |

## Rule

---

End.
