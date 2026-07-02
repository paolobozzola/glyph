# Glyph — Refinement Phases (P1–P8)

Fine "wow"/polish refinements within the **current** functional scope — no new v2.0
milestones (LaTeX, code highlighting, slash menu, Spotlight, Shortcuts stay in `docs/V2.md`).
Ordered by the owner's priority. Each can ship as **pre-1.0 polish** or roll up into a **v1.1**;
they're independent enough to land one at a time.

**Per-phase workflow (mandatory, in order):**
0. **Design & interaction review** — before any code, write a short spec of *how it looks and
   behaves*, with explicit care for user interaction (triggers, states, edge cases, motion,
   accessibility). The owner reviews/approves it; open UX forks are decided here. This is the
   gate — implementation does not start until the design is signed off.
1. **Implement** — in the layer noted per phase.
2. **Verify** — acceptance criteria below; serialization-touching phases add a round-trip case.

**Ground rules (all phases):**
- The `.md` on disk stays the single source of truth — anything that changes serialization
  (P3, P6, P8) must round-trip and gets a case added to the Playwright corpus.
- Editor features live in `web/` (Milkdown Crepe in the `WKWebView`); native shell features
  live in the Swift app (`Glyph/*.swift`). The preview bundle (`web-preview/`) mirrors editor
  CSS where relevant (headings already shared).
- Effort key: **S** ≈ ½–1 day · **M** ≈ 2–3 days · **L** ≈ 4+ days.

---

## P1 — Refined Focus / Typewriter mode  *(proposal #6)*  · Effort: M

**Goal / wow:** writing *feels* calm and premium — non-active paragraphs fade back, the caret
line stays vertically centered as you type.

**Scope (in):** dim non-focused top-level blocks with a gentle opacity transition; keep the
active block fully inked; optional "typewriter" vertical centering of the caret. **(out):**
sentence-level focus, sound, per-word effects.

**Approach:** extend the existing `focusPlugin()` in `web/src/main.ts`. Track the block at the
selection; apply a ProseMirror decoration / class to non-active blocks; CSS
`transition: opacity .2s`. Typewriter: on selection change, scroll so the caret's client rect
sits at ~45% viewport height.

**Plain-Markdown:** view-only, no serialization impact.

**Acceptance:** toggling Focus dims siblings and crisps the active block; caret line stays
centered while typing/arrowing; toggling off restores full opacity and normal scroll.

**Verify:** Playwright (class/decoration present on non-active blocks) + manual scroll feel.

---

## P2 — Ergonomic links + table controls  *(proposal #10)*  · Effort: S–M

**Goal / wow:** links and tables behave the way people expect in a modern editor.

**Scope (in):** `⌘K` to insert/edit a link on the selection; hover card on a link showing the
URL with edit/remove; `⌘`-click to open a link in the default browser; hover add/remove
row·column controls on tables. **(out):** link autocompletion, backlinks.

**Approach:** ensure Crepe's **LinkTooltip** and **Table** features are enabled in the editor
(they're the interactive UI). Add a `⌘K` native menu item (Format menu) → bridge command that
runs the link command in `web/src/main.ts`. `⌘`-click → `postToHost({type:"openURL"})` →
`NSWorkspace.shared.open`. Style tooltip/table controls with the brand palette.

**Plain-Markdown:** standard `[text](url)` and GFM tables.

**Acceptance:** `⌘K` on selected text inserts a link (and re-opens for edit); hovering a link
shows URL + edit/remove; `⌘`-click opens the browser; tables show +/− controls on hover.

**Verify:** Playwright for command wiring; manual for hover/⌘-click.

---

## P3 — Smart paste → clean Markdown  *(proposal #1)*  · Effort: M

**Goal / wow:** the everyday delight — paste anything, get clean Markdown.

**Scope (in):** URL on a non-empty selection → wrap as link; HTML clipboard (web/Slack) →
faithful Markdown (headings/bold/lists/links, drop inline styles & spans); tabular clipboard
from Numbers/Excel/web → GFM table. **(out):** pasting images (handled in P8).

**Approach:** a `$prose` plugin in `web/src/main.ts` with a ProseMirror `handlePaste`:
inspect `clipboardData` — plain-text URL + selection → link command; `text/html` → sanitize →
let Milkdown parse; TSV/`text/html` table → build a GFM table node. Prefer parsing to Markdown
so the doc model stays canonical.

**Plain-Markdown:** all outputs are CommonMark/GFM; add web-table & rich-paste cases to the
round-trip corpus.

**Acceptance:** paste a URL over a word → link; paste a spreadsheet range → GFM table; paste a
formatted web paragraph → clean Markdown with no style cruft.

**Verify:** Playwright with synthetic clipboard payloads (html/text/tsv) → assert serialized MD.

---

## P4 — Copy as Rich Text / HTML  *(proposal #2)*  · Effort: S–M

**Goal / wow:** paste Glyph content into Mail/Pages/Docs/Slack with formatting intact.

**Scope (in):** Edit-menu "Copy as Rich Text" and "Copy as HTML"; selection-aware (whole doc if
nothing selected). **(out):** copy as image/PDF.

**Approach:** reuse the export pipeline — `getHTML()` (already imported) for doc/selection,
inline `web/src/export.css` → standalone HTML string, returned to Swift over the bridge. Native
writes `NSPasteboard`: Rich Text = `NSAttributedString(html:)` → RTF **and** `.html`; HTML =
`.html` + `.string`.

**Plain-Markdown:** clipboard-only, file untouched.

**Acceptance:** Copy as Rich Text → paste into Pages keeps headings/bold/lists/tables; Copy as
HTML → paste gives clean HTML; both honor a selection.

**Verify:** manual paste into Pages/Mail; unit-check the HTML string shape.

---

## P5 — Proxy icon + title-bar craft  *(proposal #5)*  · Effort: S–M · native-only

**Goal / wow:** "this feels like an Apple app" — draggable document proxy icon, edited
indicator, tidy unified toolbar.

**Scope (in):** title-bar proxy icon (drag the doc out of the title); `⌘`-click title → path
popover; edited dot; `toolbarStyle = .unified` with a restrained toolbar. **(out):** custom
traffic-light layout, full theming.

**Approach:** in `MarkdownDocument.makeWindowControllers()` / window setup: set
`window.representedURL = fileURL` and let `NSDocument` drive `title`/`isDocumentEdited`
(already using `updateChangeCount`). Add a minimal `NSToolbar`. Verify the edited dot appears.

**Plain-Markdown:** none.

**Acceptance:** proxy icon shows and drags; `⌘`-click title shows the file path; the close
button shows the edited dot when dirty; unified toolbar renders.

**Verify:** manual in the running app.

---

## P6 — Typed frontmatter properties  *(proposal #7)*  · Effort: M

**Goal / wow:** the YAML panel becomes a real properties editor (Obsidian/iA-grade), still
saving plain YAML.

**Scope (in):** infer field type from the value — ISO date → date picker; array → tag chips
(add/remove); boolean → toggle; number → number field; else text. **(out):** schema/templates,
custom field types.

**Approach:** extend the existing `glyph-props` panel in `web/src/main.ts`. Parse each YAML
value, pick a control, and on change re-serialize preserving key order; write back through the
existing `fullMarkdown()` frontmatter merge.

**Plain-Markdown:** must emit YAML byte-compatible in meaning; add typed-frontmatter cases to
the round-trip corpus (dates, arrays, bools, quoting edge cases).

**Acceptance:** `date:` → date picker; `tags: [a, b]` → chips; `draft: true` → toggle; edits
save valid YAML that round-trips; unknown/complex values fall back to a text field.

**Verify:** Playwright round-trip on a frontmatter-heavy corpus doc.

---

## P7 — Empty state + first-run  *(proposal #8)*  · Effort: S–M

**Goal / wow:** a considered first impression instead of a literal `# New Document` you must
delete.

**Scope (in):** truly empty new documents with a tasteful placeholder ("Start writing…", muted
ink, faint gold "G"); a one-time welcome (opens the `Welcome.md` tour + cheat-sheet hint).
**(out):** multi-step onboarding, accounts.

**Approach:** replace `MarkdownDocument.text` default (currently seeded content) with empty +
Crepe **Placeholder** styled in `web/src/main.ts`. First-run: `UserDefaults` guard →
open the bundled `Welcome.md` (copied to `~/…/Glyph` or opened read-in) once.

**Plain-Markdown:** new file saves empty until typed (no seeded text on disk).

**Acceptance:** new doc is empty with a placeholder (saving an untouched new doc yields an empty
file); first launch shows the welcome/tour exactly once.

**Verify:** manual; check a brand-new doc saved immediately is empty.

---

## P8 — Portable image assets  *(proposal #9)*  · Effort: M–L

**Goal / wow:** makes "save plain, portable" concrete — pasted/dragged images land beside the
doc with relative links, no lock-in.

**Scope (in):** on image paste/drag, write the file to a configurable folder (default
`./assets/` next to the doc) with a slugified, de-duplicated name; insert a **relative**
`![](assets/…)` link; a preference for the folder name. **(out):** remote upload, image editing.

**Note:** the base already ships — paste/drag saves to `<doc>.assets/` with a relative link
(see `PLAN.md`). This phase is *refinement*: de-duplicated/slugified names, a configurable
folder, and clean untitled-doc handling — not a rebuild.

**Approach:** extend the existing `ensureImageHandlers()` (`web/src/main.ts`) + the native
write path in `EditorViewController`/`MarkdownDocument`. Untitled docs: prompt to save first
(need a base URL), or stage in temp and relink on first save.

**Plain-Markdown:** relative links only; add an image-link case to the corpus.

**Acceptance:** drag a PNG → saved under `./assets/name.png`, link is relative; moving the doc +
folder together keeps images working; duplicate names are de-duped; untitled-doc path handled.

**Verify:** manual drag/paste; open the saved `.md` from a copied folder and confirm the image
resolves.

---

## Sequencing notes

- **Quick wins first:** P1 and P2 are low-risk and visible — good momentum before the heavier
  paste/assets work.
- **Shared code:** P3 (smart paste) and P8 (image paste) both hook the paste path — land P3's
  plugin structure first, then P8 extends it. P4 reuses the same `getHTML()` + `export.css`
  export pipeline.
- **Parallelizable:** P5 is native-only and touches no web code — can run alongside any web-side
  phase.
- **Round-trip gate:** P3, P6, P8 change serialization → each must add a Playwright corpus case
  and pass before merge (per the CLAUDE.md round-trip policy).
- **Pre-1.0 vs v1.1:** P1, P2, P4, P5 are safe to fold into 1.0; P3, P6, P8 (serialization-
  touching) are natural v1.1 candidates if you'd rather ship 1.0 now.
