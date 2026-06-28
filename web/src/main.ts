import { Crepe } from "@milkdown/crepe";
import { callCommand, $prose, getHTML } from "@milkdown/kit/utils";
import { undoCommand, redoCommand } from "@milkdown/kit/plugin/history";
import { remarkStringifyOptionsCtx, editorViewCtx } from "@milkdown/kit/core";
import {
  search,
  setSearchState,
  SearchQuery,
  findNext,
  findPrev,
  replaceNext,
  replaceAll,
} from "prosemirror-search";
import {
  toggleStrongCommand,
  toggleEmphasisCommand,
  toggleInlineCodeCommand,
  toggleLinkCommand,
  wrapInHeadingCommand,
  turnIntoTextCommand,
  wrapInBulletListCommand,
  wrapInOrderedListCommand,
  wrapInBlockquoteCommand,
  createCodeBlockCommand,
  insertHrCommand,
} from "@milkdown/kit/preset/commonmark";
import { toggleStrikethroughCommand, insertTableCommand } from "@milkdown/kit/preset/gfm";
import { Plugin, TextSelection } from "@milkdown/kit/prose/state";
import { Decoration, DecorationSet } from "@milkdown/kit/prose/view";

import "@milkdown/crepe/theme/common/style.css";
import frameLight from "@milkdown/crepe/theme/frame.css?inline";
import frameDark from "@milkdown/crepe/theme/frame-dark.css?inline";
import exportCss from "./export.css?inline";

// ---------------------------------------------------------------------------
// Glyph editor bundle.
//
// Contract with the Swift host (docs/SHELL.md §4):
//   JS  -> Swift : window.webkit.messageHandlers.glyph.postMessage(payload)
//                  { type: "ready" }                      on mount
//                  { type: "change", markdown: string }   debounced
//   Swift -> JS  : window.glyph.setMarkdown(text)         load a document
//                  window.glyph.getMarkdown()             read current text (save)
//                  window.glyph.setTheme("light"|"dark")  follow appearance
//                  window.glyph.cmd(name)                 menu/keyboard -> editor
//                    name ∈ undo redo bold italic code strike link paragraph
//                           heading:N bulletList orderedList blockquote
//                           codeBlock hr table
// ---------------------------------------------------------------------------

type ThemeMode = "light" | "dark";

type Bridge = {
  setMarkdown: (text: string) => void;
  getMarkdown: () => string;
  setTheme: (mode: ThemeMode) => void;
  cmd: (name: string) => void;
  exportHTML: () => string;
};

declare global {
  interface Window {
    glyph: Bridge;
    webkit?: {
      messageHandlers?: { glyph?: { postMessage: (msg: unknown) => void } };
    };
  }
}

const root = document.getElementById("app")!;
const DEBOUNCE_MS = 120;

let crepe: Crepe | null = null;
let debounceTimer: ReturnType<typeof setTimeout> | undefined;
// Last Markdown loaded or reported — used to ignore the no-op `markdownUpdated`
// that fires on initial render (otherwise the host marks the document dirty on open).
let lastMarkdown = "";

// --- theme ---------------------------------------------------------------
const themeStyle = document.createElement("style");
themeStyle.id = "glyph-theme";
document.head.appendChild(themeStyle);

function applyTheme(mode: ThemeMode): void {
  themeStyle.textContent = mode === "dark" ? frameDark : frameLight;
  document.documentElement.dataset.theme = mode;
  document.documentElement.style.colorScheme = mode;
}
applyTheme(window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light");

// --- host messaging ------------------------------------------------------
function postToHost(msg: unknown): void {
  window.webkit?.messageHandlers?.glyph?.postMessage(msg);
}

async function mount(markdown: string): Promise<void> {
  if (crepe) {
    await crepe.destroy();
    crepe = null;
  }
  lastMarkdown = markdown;
  crepe = new Crepe({ root, defaultValue: markdown });
  // Tame Markdown normalization: dash bullets and thematic breaks, compact indent.
  try {
    crepe.editor.config((ctx) => {
      ctx.update(remarkStringifyOptionsCtx, (prev) => ({
        ...prev,
        bullet: "-",
        rule: "-",
        listItemIndent: "one",
      }));
    });
  } catch {
    /* serializer config is best-effort; editor still works without it */
  }
  crepe.editor.use($prose(() => search()));        // find & replace engine
  crepe.editor.use($prose(() => focusPlugin()));    // focus / typewriter mode
  await crepe.create();
  ensureChrome();
  updateCount();
  refreshOutlineIfOpen();
  crepe.on((listener) => {
    listener.markdownUpdated((_ctx, md) => {
      if (md === lastMarkdown) return; // ignore initial render / no-op updates
      lastMarkdown = md;
      updateCount();
      refreshOutlineIfOpen();
      clearTimeout(debounceTimer);
      debounceTimer = setTimeout(() => postToHost({ type: "change", markdown: md }), DEBOUNCE_MS);
    });
  });
}

// Milkdown's `$command` plugins get `.key` / `.run(payload)` attached lazily, only
// after they're registered in an editor — so we keep the command objects and resolve
// at call time, not import time.
type MilkCommand = { key?: unknown; run?: (payload?: unknown) => unknown };

const COMMANDS: Record<string, { command: MilkCommand; payload?: (arg?: string) => unknown }> = {
  undo: { command: undoCommand },
  redo: { command: redoCommand },
  bold: { command: toggleStrongCommand },
  italic: { command: toggleEmphasisCommand },
  code: { command: toggleInlineCodeCommand },
  strike: { command: toggleStrikethroughCommand },
  link: { command: toggleLinkCommand },
  paragraph: { command: turnIntoTextCommand },
  heading: { command: wrapInHeadingCommand, payload: (arg) => Number(arg) },
  bulletList: { command: wrapInBulletListCommand },
  orderedList: { command: wrapInOrderedListCommand },
  blockquote: { command: wrapInBlockquoteCommand },
  codeBlock: { command: createCodeBlockCommand },
  hr: { command: insertHrCommand },
  table: { command: insertTableCommand },
};

// --- find & replace ------------------------------------------------------
// Drives the prosemirror-search plugin via a small find bar overlay.

function getView(): any {
  const editor = crepe?.editor;
  if (!editor) return null;
  try {
    return editor.action((ctx) => ctx.get(editorViewCtx));
  } catch {
    return null;
  }
}

// --- outline · word count · focus mode -----------------------------------

let focusMode = false;

// Dims every top-level block except the one holding the selection (focus mode).
function focusPlugin(): Plugin {
  return new Plugin({
    props: {
      decorations(state) {
        if (!focusMode) return null;
        const { $from } = state.selection;
        if ($from.depth < 1) return null;
        const from = $from.before(1);
        const to = $from.after(1);
        return DecorationSet.create(state.doc, [
          Decoration.node(from, to, { class: "glyph-active" }),
        ]);
      },
    },
    view() {
      return {
        update(view) {
          if (!focusMode) return;
          // Typewriter: keep the caret's block vertically centered.
          const dom = view.domAtPos(view.state.selection.head).node as Node;
          const el = dom.nodeType === 1 ? (dom as Element) : dom.parentElement;
          el?.scrollIntoView({ block: "center", behavior: "smooth" });
        },
      };
    },
  });
}

const CHROME_CSS = `
.glyph-status{position:fixed;left:0;right:0;bottom:0;z-index:9000;height:34px;
  display:flex;align-items:center;justify-content:space-between;gap:12px;
  padding:0 16px;font:12px/1 -apple-system,BlinkMacSystemFont,system-ui,sans-serif;
  color:#6b6678;background:rgba(245,241,232,.85);border-top:1px solid rgba(0,0,0,.07);
  -webkit-backdrop-filter:saturate(180%) blur(20px);backdrop-filter:saturate(180%) blur(20px);}
.glyph-count{font-variant-numeric:tabular-nums;letter-spacing:.01em;}
.glyph-status-actions{display:flex;gap:8px;}
.glyph-status button{border:0;background:transparent;color:#6b6678;
  border-radius:7px;padding:5px 11px;cursor:pointer;font:inherit;font-weight:550;
  transition:background .12s ease,color .12s ease;}
.glyph-status button:hover{background:rgba(0,0,0,.06);color:#1a1822;}
.glyph-status button.on{background:rgba(230,180,80,.22);color:#9a6a00;}
.ProseMirror{padding-bottom:48px;}
.glyph-outline{position:fixed;top:0;left:0;bottom:34px;z-index:9100;width:260px;
  background:rgba(245,241,232,.85);border-right:1px solid rgba(0,0,0,.08);overflow-y:auto;
  -webkit-backdrop-filter:saturate(180%) blur(20px);backdrop-filter:saturate(180%) blur(20px);
  padding:8px;font:13px -apple-system,BlinkMacSystemFont,system-ui,sans-serif;}
.glyph-outline[hidden]{display:none;}
.glyph-outline-head{padding:10px 10px 8px;font-weight:650;color:#9a93a8;
  letter-spacing:.08em;text-transform:uppercase;font-size:10.5px;}
.glyph-outline a{display:block;padding:5px 10px;margin:1px 0;color:#1a1822;text-decoration:none;
  cursor:pointer;border-radius:6px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;
  transition:background .12s ease;}
.glyph-outline a:hover{background:rgba(230,180,80,.18);}
.glyph-outline a:active{background:rgba(230,180,80,.32);}
.glyph-outline a.lvl1{font-weight:600;}
.glyph-outline a.lvl2{padding-left:24px;}
.glyph-outline a.lvl3{padding-left:38px;color:#6b6678;}
.glyph-outline a.lvl4,.glyph-outline a.lvl5,.glyph-outline a.lvl6{padding-left:52px;color:#6b6678;font-size:12.5px;}
.glyph-outline-empty{padding:6px 10px;color:#9a93a8;}
.glyph-focus-on .ProseMirror>*{opacity:.45;transition:opacity .25s ease;}
.glyph-focus-on .ProseMirror>.glyph-active,
.glyph-focus-on .ProseMirror .glyph-active,
.glyph-focus-on .ProseMirror>*:has(.glyph-active){opacity:1 !important;}
.glyph-focus-on .ProseMirror{padding-top:40vh;padding-bottom:40vh;}
@keyframes glyph-flash{0%{background:rgba(230,180,80,.45);}100%{background:transparent;}}
.glyph-flash{animation:glyph-flash 1s ease;border-radius:4px;}
[data-theme=dark] .glyph-status{background:rgba(35,32,48,.82);color:#9a93a8;border-top-color:rgba(255,255,255,.08);}
[data-theme=dark] .glyph-status button{color:#9a93a8;}
[data-theme=dark] .glyph-status button:hover{background:rgba(255,255,255,.09);color:#e8e6ef;}
[data-theme=dark] .glyph-status button.on{background:rgba(230,180,80,.2);color:#e6b450;}
[data-theme=dark] .glyph-outline{background:rgba(35,32,48,.82);border-right-color:rgba(255,255,255,.1);}
[data-theme=dark] .glyph-outline a{color:#e8e6ef;}
[data-theme=dark] .glyph-outline a:hover{background:rgba(230,180,80,.16);}
[data-theme=dark] .glyph-outline a.lvl3,[data-theme=dark] .glyph-outline a.lvl4{color:#9a93a8;}
`;

let chromeReady = false;
let countEl: HTMLElement;
let outlineEl: HTMLElement;
let outlineListEl: HTMLElement;
let outlineBtn: HTMLButtonElement;
let focusBtn: HTMLButtonElement;

function ensureChrome(): void {
  if (chromeReady) return;
  chromeReady = true;

  const style = document.createElement("style");
  style.textContent = CHROME_CSS;
  document.head.appendChild(style);

  const status = document.createElement("div");
  status.className = "glyph-status";
  status.innerHTML = `
    <span class="glyph-count"></span>
    <span class="glyph-status-actions">
      <button data-act="outline">Outline</button>
      <button data-act="focus">Focus</button>
    </span>`;
  document.body.appendChild(status);
  countEl = status.querySelector(".glyph-count") as HTMLElement;
  outlineBtn = status.querySelector('[data-act="outline"]') as HTMLButtonElement;
  focusBtn = status.querySelector('[data-act="focus"]') as HTMLButtonElement;
  status.addEventListener("click", (e) => {
    const btn = (e.target as HTMLElement).closest("button");
    if (!btn) return;
    if (btn.getAttribute("data-act") === "outline") toggleOutline();
    else if (btn.getAttribute("data-act") === "focus") toggleFocus();
  });

  const outline = document.createElement("div");
  outline.className = "glyph-outline";
  outline.hidden = true;
  outline.innerHTML = `<div class="glyph-outline-head">Outline</div><nav class="glyph-outline-list"></nav>`;
  document.body.appendChild(outline);
  outlineEl = outline;
  outlineListEl = outline.querySelector(".glyph-outline-list") as HTMLElement;
}

function updateCount(): void {
  if (!countEl) return;
  const view = getView();
  const text = view ? view.state.doc.textBetween(0, view.state.doc.content.size, " ", " ") : "";
  const words = (text.trim().match(/\S+/g) || []).length;
  const chars = text.length;
  countEl.textContent = `${words} word${words === 1 ? "" : "s"} · ${chars} character${chars === 1 ? "" : "s"}`;
}

type Heading = { level: number; text: string; pos: number };

function collectHeadings(): Heading[] {
  const view = getView();
  if (!view) return [];
  const out: Heading[] = [];
  view.state.doc.descendants((node: any, pos: number) => {
    if (node.type.name === "heading") {
      out.push({ level: node.attrs.level || 1, text: node.textContent || "Untitled", pos });
    }
    return true;
  });
  return out;
}

function refreshOutlineIfOpen(): void {
  if (!outlineEl || outlineEl.hidden) return;
  const headings = collectHeadings();
  outlineListEl.innerHTML = "";
  if (headings.length === 0) {
    const empty = document.createElement("div");
    empty.className = "glyph-outline-empty";
    empty.textContent = "No headings yet";
    outlineListEl.appendChild(empty);
    return;
  }
  for (const h of headings) {
    const a = document.createElement("a");
    a.className = `lvl${h.level}`;
    a.textContent = h.text;
    a.addEventListener("click", () => goToHeading(h.pos));
    outlineListEl.appendChild(a);
  }
}

function goToHeading(pos: number): void {
  const view = getView();
  if (!view) return;
  view.dispatch(view.state.tr.setSelection(TextSelection.near(view.state.doc.resolve(pos + 1))));
  // Scroll the heading's DOM node to center and flash it, so the jump is visible
  // even when the document already fits on screen.
  const domInfo = view.domAtPos(pos + 1);
  let node: Element | null =
    domInfo.node.nodeType === 1 ? (domInfo.node as Element) : domInfo.node.parentElement;
  while (node && node.parentElement && !/^H[1-6]$/.test(node.tagName)) {
    if (node.parentElement.classList?.contains("ProseMirror")) break;
    node = node.parentElement;
  }
  node?.scrollIntoView({ block: "center", behavior: "smooth" });
  if (node) {
    node.classList.remove("glyph-flash");
    void (node as HTMLElement).offsetWidth; // restart the animation
    node.classList.add("glyph-flash");
  }
  view.focus();
}

function toggleOutline(): void {
  ensureChrome();
  outlineEl.hidden = !outlineEl.hidden;
  outlineBtn?.classList.toggle("on", !outlineEl.hidden);
  refreshOutlineIfOpen();
}

function toggleFocus(): void {
  ensureChrome();
  focusMode = !focusMode;
  document.documentElement.classList.toggle("glyph-focus-on", focusMode);
  focusBtn?.classList.toggle("on", focusMode);
  // Force the focus plugin's decorations to recompute (empty transaction).
  const view = getView();
  if (view) view.dispatch(view.state.tr);
}

const FIND_CSS = `
.glyph-find{position:fixed;top:12px;right:16px;z-index:9999;background:var(--glyph-find-bg,#fff);
  color:inherit;border:1px solid rgba(0,0,0,.15);border-radius:10px;
  box-shadow:0 6px 24px rgba(0,0,0,.18);padding:8px;display:flex;flex-direction:column;gap:6px;
  font:13px -apple-system,BlinkMacSystemFont,system-ui,sans-serif;}
.glyph-find[hidden]{display:none;}
.glyph-find-row{display:flex;align-items:center;gap:6px;}
.glyph-find input{border:1px solid rgba(0,0,0,.2);border-radius:6px;padding:4px 8px;font:inherit;
  width:210px;background:transparent;color:inherit;outline:none;}
.glyph-find input:focus{border-color:#3b82f6;}
.glyph-find-count{min-width:62px;color:#888;font-size:12px;text-align:right;}
.glyph-find-btn{border:1px solid rgba(0,0,0,.15);background:transparent;color:inherit;border-radius:6px;
  padding:3px 9px;cursor:pointer;font:inherit;line-height:1.2;}
.glyph-find-btn:hover{background:rgba(0,0,0,.06);}
.ProseMirror-search-match{background:rgba(255,213,0,.35);border-radius:2px;}
.ProseMirror-active-search-match{background:rgba(255,145,0,.6);border-radius:2px;}
[data-theme=dark] .glyph-find{background:#2a2730;border-color:rgba(255,255,255,.15);}
[data-theme=dark] .glyph-find input,[data-theme=dark] .glyph-find-btn{border-color:rgba(255,255,255,.2);}
[data-theme=dark] .glyph-find-btn:hover{background:rgba(255,255,255,.1);}
[data-theme=dark] .ProseMirror-search-match{background:rgba(255,213,0,.28);}
[data-theme=dark] .ProseMirror-active-search-match{background:rgba(255,160,0,.55);}
`;

let findBarEl: HTMLDivElement | null = null;
let findInput: HTMLInputElement;
let replaceInput: HTMLInputElement;
let findCountEl: HTMLElement;
let replaceRow: HTMLElement;

function ensureFindBar(): void {
  if (findBarEl) return;
  const style = document.createElement("style");
  style.textContent = FIND_CSS;
  document.head.appendChild(style);

  const bar = document.createElement("div");
  bar.className = "glyph-find";
  bar.hidden = true;
  bar.innerHTML = `
    <div class="glyph-find-row">
      <input type="text" class="glyph-find-input" placeholder="Find" />
      <span class="glyph-find-count"></span>
      <button class="glyph-find-btn" data-act="prev" title="Previous (⇧⌘G)">‹</button>
      <button class="glyph-find-btn" data-act="next" title="Next (⌘G)">›</button>
      <button class="glyph-find-btn" data-act="close" title="Close (Esc)">✕</button>
    </div>
    <div class="glyph-find-row glyph-find-replace" hidden>
      <input type="text" class="glyph-replace-input" placeholder="Replace" />
      <button class="glyph-find-btn" data-act="replace">Replace</button>
      <button class="glyph-find-btn" data-act="replaceAll">All</button>
    </div>`;
  document.body.appendChild(bar);

  findBarEl = bar;
  findInput = bar.querySelector(".glyph-find-input") as HTMLInputElement;
  replaceInput = bar.querySelector(".glyph-replace-input") as HTMLInputElement;
  findCountEl = bar.querySelector(".glyph-find-count") as HTMLElement;
  replaceRow = bar.querySelector(".glyph-find-replace") as HTMLElement;

  findInput.addEventListener("input", applyQuery);
  replaceInput.addEventListener("input", applyQuery);
  findInput.addEventListener("keydown", (e) => {
    if (e.key === "Enter") { e.preventDefault(); e.shiftKey ? findPrevMatch() : findNextMatch(); }
    else if (e.key === "Escape") { e.preventDefault(); hideFind(); }
  });
  replaceInput.addEventListener("keydown", (e) => {
    if (e.key === "Enter") { e.preventDefault(); replaceOne(); }
    else if (e.key === "Escape") { e.preventDefault(); hideFind(); }
  });
  bar.addEventListener("click", (e) => {
    const btn = (e.target as HTMLElement).closest("button");
    if (!btn) return;
    switch (btn.getAttribute("data-act")) {
      case "next": findNextMatch(); break;
      case "prev": findPrevMatch(); break;
      case "close": hideFind(); break;
      case "replace": replaceOne(); break;
      case "replaceAll": replaceAllMatches(); break;
    }
  });
}

function currentQuery(): SearchQuery {
  return new SearchQuery({ search: findInput.value, replace: replaceInput.value });
}

function applyQuery(): void {
  const view = getView();
  if (!view) return;
  view.dispatch(setSearchState(view.state.tr, currentQuery()));
  updateFindCount(view);
}

function updateFindCount(view: any): void {
  const term = findInput.value;
  if (!term) { findCountEl.textContent = ""; return; }
  const text: string = view.state.doc.textBetween(0, view.state.doc.content.size, "\n", "\n");
  const hay = text.toLowerCase();
  const needle = term.toLowerCase();
  let n = 0, i = 0;
  while ((i = hay.indexOf(needle, i)) !== -1) { n++; i += needle.length; }
  findCountEl.textContent = n === 1 ? "1 match" : `${n} matches`;
}

function findNextMatch(): void {
  if (!findBarEl || findBarEl.hidden) { showFind(false); return; }
  const view = getView();
  if (view) { findNext(view.state, view.dispatch); updateFindCount(view); }
}

function findPrevMatch(): void {
  if (!findBarEl || findBarEl.hidden) { showFind(false); return; }
  const view = getView();
  if (view) { findPrev(view.state, view.dispatch); updateFindCount(view); }
}

function replaceOne(): void {
  const view = getView();
  if (view) { replaceNext(view.state, view.dispatch); updateFindCount(getView()); }
}

function replaceAllMatches(): void {
  const view = getView();
  if (view) { replaceAll(view.state, view.dispatch); updateFindCount(getView()); }
}

function showFind(withReplace: boolean): void {
  ensureFindBar();
  replaceRow.hidden = !withReplace;
  findBarEl!.hidden = false;
  const view = getView();
  if (view) {
    const { from, to } = view.state.selection;
    if (to > from) findInput.value = view.state.doc.textBetween(from, to);
  }
  findInput.focus();
  findInput.select();
  if (findInput.value) applyQuery();
}

function hideFind(): void {
  if (!findBarEl) return;
  findBarEl.hidden = true;
  const view = getView();
  if (view) {
    view.dispatch(setSearchState(view.state.tr, new SearchQuery({ search: "" })));
    view.focus();
  }
}

function runCommand(name: string): void {
  switch (name) {
    case "find": showFind(false); return;
    case "findReplace": showFind(true); return;
    case "findNext": findNextMatch(); return;
    case "findPrev": findPrevMatch(); return;
    case "toggleOutline": toggleOutline(); return;
    case "toggleFocus": toggleFocus(); return;
  }
  const editor = crepe?.editor;
  if (!editor) return;
  const [cmd, arg] = name.split(":");
  const entry = COMMANDS[cmd];
  if (!entry) return;
  const payload = entry.payload ? entry.payload(arg) : undefined;
  const command = entry.command;
  if (typeof command.run === "function") {
    command.run(payload); // bound to the editor after create()
  } else if (command.key != null) {
    editor.action(callCommand(command.key as never, payload as never));
  }
}

window.glyph = {
  setMarkdown: (text: string) => {
    void mount(text);
  },
  getMarkdown: () => crepe?.getMarkdown() ?? "",
  setTheme: (mode) => applyTheme(mode),
  cmd: (name) => runCommand(name),
  exportHTML: () => {
    const body = crepe ? crepe.editor.action(getHTML()) : "";
    return `<!doctype html><html><head><meta charset="utf-8">` +
      `<meta name="viewport" content="width=device-width, initial-scale=1">` +
      `<style>${exportCss}</style></head>` +
      `<body class="markdown-body">${body}</body></html>`;
  },
};

// Boot: mount a placeholder, tell the host we're ready; the host replies with the
// real document via window.glyph.setMarkdown(...).
void mount("# Glyph\n\nLoading…\n").then(() => postToHost({ type: "ready" }));
