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
  insertImageCommand,
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
  imageSaved: (id: number, path: string | null) => void;
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
  ensureImageHandlers();
  updateCount();
  refreshOutlineIfOpen();
  crepe.on((listener) => {
    listener.markdownUpdated((_ctx, md) => {
      if (md === lastMarkdown) return; // ignore initial render / no-op updates
      lastMarkdown = md;
      updateCount();
      refreshOutlineIfOpen();
      clearTimeout(debounceTimer);
      // Prepend any frontmatter so the saved document keeps its properties.
      debounceTimer = setTimeout(() => postToHost({ type: "change", markdown: fullMarkdown(md) }), DEBOUNCE_MS);
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

// --- image paste / drag --------------------------------------------------
// Intercept image files, hand the bytes to the host (which saves them next to the
// document and returns a relative path), then insert a Markdown image.

let imgSeq = 0;
const pendingImages = new Map<number, (path: string | null) => void>();

function saveImageViaHost(base64: string, mime: string): Promise<string | null> {
  return new Promise((resolve) => {
    const id = ++imgSeq;
    pendingImages.set(id, resolve);
    postToHost({ type: "saveImage", id, base64, mime });
    setTimeout(() => {
      if (pendingImages.has(id)) { pendingImages.delete(id); resolve(null); }
    }, 20000);
  });
}

function fileToBase64(file: File): Promise<{ base64: string; mime: string }> {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => {
      const res = String(reader.result); // data:<mime>;base64,XXXX
      resolve({ base64: res.slice(res.indexOf(",") + 1), mime: file.type || "image/png" });
    };
    reader.onerror = () => reject(reader.error);
    reader.readAsDataURL(file);
  });
}

function insertImageSrc(src: string): void {
  const cmd = insertImageCommand as unknown as {
    run?: (p: unknown) => unknown; key?: unknown;
  };
  if (typeof cmd.run === "function") {
    cmd.run({ src });
  } else if (crepe && cmd.key != null) {
    crepe.editor.action(callCommand(cmd.key as never, { src } as never));
  }
}

async function handleImageFiles(files: File[]): Promise<void> {
  for (const file of files) {
    if (!file.type.startsWith("image/")) continue;
    try {
      const { base64, mime } = await fileToBase64(file);
      const path = await saveImageViaHost(base64, mime);
      if (path) insertImageSrc(path);
    } catch {
      /* skip a file that fails to read/save */
    }
  }
}

function imageFilesFrom(dt: DataTransfer | null): File[] {
  if (!dt || !dt.files) return [];
  return Array.from(dt.files).filter((f) => f.type.startsWith("image/"));
}

let imageHandlersReady = false;
function ensureImageHandlers(): void {
  if (imageHandlersReady) return;
  imageHandlersReady = true;
  // Capture phase so we pre-empt the editor's own paste/drop handling.
  root.addEventListener("paste", (e) => {
    const files = imageFilesFrom((e as ClipboardEvent).clipboardData);
    if (files.length) { e.preventDefault(); e.stopPropagation(); void handleImageFiles(files); }
  }, true);
  root.addEventListener("dragover", (e) => {
    if ((e as DragEvent).dataTransfer?.types?.includes("Files")) e.preventDefault();
  }, true);
  root.addEventListener("drop", (e) => {
    const files = imageFilesFrom((e as DragEvent).dataTransfer);
    if (files.length) { e.preventDefault(); e.stopPropagation(); void handleImageFiles(files); }
  }, true);
}

// --- YAML frontmatter (editable properties panel) ------------------------
// Simple top-level `key: value` frontmatter becomes an editable panel; anything
// more complex (nested maps, block lists, comments) is preserved verbatim and
// edited via Markdown source. The .md stays the source of truth.

type FMRow = { key: string; value: string };
let fmMode: "none" | "rows" | "raw" = "none";
let fmRows: FMRow[] = [];
let fmRaw = "";
let propsEl: HTMLElement | null = null;
let propsRowsEl: HTMLElement | null = null;

function splitFrontmatter(text: string): { inner: string | null; body: string } {
  const m = /^---[ \t]*\r?\n([\s\S]*?)\r?\n---[ \t]*(?:\r?\n|$)/.exec(text);
  if (!m || m.index !== 0) return { inner: null, body: text };
  return { inner: m[1], body: text.slice(m[0].length) };
}

const FM_SIMPLE = /^([A-Za-z0-9_][\w .\-]*?):[ \t]?(.*)$/;

function parseFrontmatter(inner: string): void {
  const lines = inner.split(/\r?\n/);
  const rows: FMRow[] = [];
  for (const line of lines) {
    // Empty, indented, or comment lines → too complex for the panel; keep raw.
    if (line.trim() === "" || /^\s/.test(line) || line.trimStart().startsWith("#")) {
      fmMode = "raw"; fmRaw = inner; fmRows = []; return;
    }
    const mm = FM_SIMPLE.exec(line);
    if (!mm) { fmMode = "raw"; fmRaw = inner; fmRows = []; return; }
    rows.push({ key: mm[1], value: mm[2] });
  }
  fmMode = "rows"; fmRows = rows; fmRaw = "";
}

function buildFrontmatterInner(): string | null {
  if (fmMode === "raw") return fmRaw;
  if (fmMode === "rows") {
    const ls = fmRows
      .filter((r) => r.key.trim())
      .map((r) => (r.value ? `${r.key}: ${r.value}` : `${r.key}:`));
    return ls.length ? ls.join("\n") : null;
  }
  return null;
}

function fullMarkdown(body: string): string {
  const inner = buildFrontmatterInner();
  const b = body.replace(/^\n+/, "");
  return inner != null ? `---\n${inner}\n---\n\n${b}` : b;
}

/// Load a complete document: separate frontmatter, render the panel, mount the body.
function applyFullMarkdown(text: string): void {
  const { inner, body } = splitFrontmatter(text);
  if (inner == null) { fmMode = "none"; fmRows = []; fmRaw = ""; }
  else parseFrontmatter(inner);
  renderProps();
  void mount(body);
}

function postFullChange(): void {
  if (sourceMode) return;
  postToHost({ type: "change", markdown: fullMarkdown(crepe?.getMarkdown() ?? lastMarkdown) });
}

function ensureProps(): void {
  if (propsEl) return;
  const style = document.createElement("style");
  style.textContent = `
.glyph-props{flex:0 0 auto;max-height:38vh;overflow-y:auto;box-sizing:border-box;
  padding:14px max(18px,calc(50% - 380px));background:rgba(245,241,232,.6);
  border-bottom:1px solid rgba(0,0,0,.08);
  font:13px -apple-system,BlinkMacSystemFont,system-ui,sans-serif;}
.glyph-props[hidden]{display:none;}
.glyph-outline-on .glyph-props{padding-left:268px;}
.glyph-props-head{display:flex;align-items:center;justify-content:space-between;
  margin-bottom:8px;}
.glyph-props-head span{font-weight:700;font-size:10.5px;letter-spacing:.09em;
  text-transform:uppercase;color:#9a6a00;}
.glyph-props-head button{border:0;background:transparent;color:#6b6678;cursor:pointer;
  font:inherit;font-weight:550;border-radius:6px;padding:3px 8px;}
.glyph-props-head button:hover{background:rgba(0,0,0,.06);color:#1a1822;}
.glyph-props-row{display:flex;gap:8px;align-items:center;margin:3px 0;}
.glyph-props-row input{border:1px solid rgba(0,0,0,.14);border-radius:6px;padding:4px 8px;
  font:inherit;background:#fff;color:#1a1822;}
.glyph-props-key{flex:0 0 32%;font-weight:560;}
.glyph-props-val{flex:1 1 auto;font-family:ui-monospace,"SF Mono",Menlo,monospace;}
.glyph-props-del{flex:0 0 auto;border:0;background:transparent;color:#9a93a8;cursor:pointer;
  font-size:15px;line-height:1;padding:2px 6px;border-radius:6px;}
.glyph-props-del:hover{background:rgba(0,0,0,.08);color:#1a1822;}
.glyph-props-raw{width:100%;box-sizing:border-box;border:1px dashed rgba(0,0,0,.2);border-radius:8px;
  padding:8px 10px;background:transparent;color:#6b6678;resize:vertical;min-height:60px;
  font:12px/1.5 ui-monospace,"SF Mono",Menlo,monospace;}
.glyph-props-hint{margin:6px 0 0;color:#9a93a8;font-size:12px;}
[data-theme=dark] .glyph-props{background:rgba(35,32,48,.5);border-bottom-color:rgba(255,255,255,.08);}
[data-theme=dark] .glyph-props-head span{color:#e6b450;}
[data-theme=dark] .glyph-props-row input{background:#232030;color:#e8e6ef;border-color:rgba(255,255,255,.16);}
[data-theme=dark] .glyph-props-head button:hover,[data-theme=dark] .glyph-props-del:hover{background:rgba(255,255,255,.1);color:#e8e6ef;}
`;
  document.head.appendChild(style);

  const panel = document.createElement("div");
  panel.className = "glyph-props";
  panel.hidden = true;
  panel.innerHTML = `
    <div class="glyph-props-head"><span>Properties</span>
      <button data-act="add">+ Add field</button></div>
    <div class="glyph-props-rows"></div>`;
  document.body.insertBefore(panel, root);
  propsEl = panel;
  propsRowsEl = panel.querySelector(".glyph-props-rows") as HTMLElement;
  panel.querySelector('[data-act="add"]')!.addEventListener("click", () => {
    if (fmMode !== "rows") { fmMode = "rows"; fmRows = []; }
    fmRows.push({ key: "", value: "" });
    renderProps();
    (propsRowsEl!.querySelector(".glyph-props-row:last-child .glyph-props-key") as HTMLInputElement)?.focus();
  });
}

function renderProps(): void {
  ensureProps();
  if (sourceMode || fmMode === "none") { propsEl!.hidden = true; return; }
  propsEl!.hidden = false;
  propsRowsEl!.innerHTML = "";

  if (fmMode === "raw") {
    const ta = document.createElement("textarea");
    ta.className = "glyph-props-raw";
    ta.value = fmRaw;
    ta.readOnly = true;
    propsRowsEl!.appendChild(ta);
    const hint = document.createElement("p");
    hint.className = "glyph-props-hint";
    hint.textContent = "This document's properties use nested YAML — edit them in Markdown source (⌥⌘M).";
    propsRowsEl!.appendChild(hint);
    return;
  }

  fmRows.forEach((row, i) => {
    const el = document.createElement("div");
    el.className = "glyph-props-row";
    const key = document.createElement("input");
    key.className = "glyph-props-key";
    key.placeholder = "name";
    key.value = row.key;
    const val = document.createElement("input");
    val.className = "glyph-props-val";
    val.placeholder = "value";
    val.value = row.value;
    const del = document.createElement("button");
    del.className = "glyph-props-del";
    del.textContent = "×";
    del.title = "Remove field";
    key.addEventListener("input", () => { fmRows[i].key = key.value; postFullChange(); });
    val.addEventListener("input", () => { fmRows[i].value = val.value; postFullChange(); });
    del.addEventListener("click", () => { fmRows.splice(i, 1); if (fmRows.length === 0) fmMode = "none"; renderProps(); postFullChange(); });
    el.append(key, val, del);
    propsRowsEl!.appendChild(el);
  });
}

function addProperties(): void {
  ensureProps();
  if (fmMode === "none") { fmMode = "rows"; fmRows = [{ key: "", value: "" }]; }
  renderProps();
  postFullChange();
  (propsRowsEl?.querySelector(".glyph-props-key") as HTMLInputElement)?.focus();
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
#app{transition:padding-left .2s ease;}
.glyph-outline-on #app{padding-left:260px;}
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
let sourceBtn: HTMLButtonElement | undefined;

// --- help / cheat sheet --------------------------------------------------

const HELP_CSS = `
.glyph-help-scrim{position:fixed;inset:0;z-index:9500;display:flex;align-items:center;
  justify-content:center;background:rgba(26,24,34,.38);
  -webkit-backdrop-filter:blur(3px);backdrop-filter:blur(3px);}
.glyph-help-scrim[hidden]{display:none;}
.glyph-help{width:min(720px,92vw);max-height:84vh;overflow-y:auto;background:#f5f1e8;
  color:#1a1822;border-radius:16px;box-shadow:0 30px 80px -20px rgba(0,0,0,.55);
  padding:26px 30px 30px;font:14px/1.5 -apple-system,BlinkMacSystemFont,system-ui,sans-serif;}
.glyph-help h2{margin:0 0 2px;font-size:20px;font-weight:680;letter-spacing:-.01em;}
.glyph-help .sub{margin:0 0 20px;color:#6b6678;font-size:13px;}
.glyph-help-cols{display:grid;grid-template-columns:1fr 1fr;gap:10px 32px;}
@media(max-width:560px){.glyph-help-cols{grid-template-columns:1fr;}}
.glyph-help section{break-inside:avoid;margin-bottom:14px;}
.glyph-help h3{margin:0 0 7px;font-size:11px;font-weight:700;letter-spacing:.09em;
  text-transform:uppercase;color:#9a6a00;}
.glyph-help-row{display:flex;align-items:baseline;justify-content:space-between;gap:14px;
  padding:3px 0;}
.glyph-help-row span{color:#3a3646;}
.glyph-help kbd{display:inline-block;font:12px ui-monospace,"SF Mono",Menlo,monospace;
  background:#fff;border:1px solid rgba(0,0,0,.18);border-bottom-width:2px;border-radius:6px;
  padding:1px 6px;color:#1a1822;white-space:nowrap;}
.glyph-help-foot{margin-top:14px;text-align:center;color:#9a93a8;font-size:12px;}
[data-theme=dark] .glyph-help{background:#232030;color:#e8e6ef;}
[data-theme=dark] .glyph-help .sub{color:#9a93a8;}
[data-theme=dark] .glyph-help h3{color:#e6b450;}
[data-theme=dark] .glyph-help-row span{color:#c8c4d4;}
[data-theme=dark] .glyph-help kbd{background:#1a1822;border-color:rgba(255,255,255,.2);color:#e8e6ef;}
`;

type HelpSection = { title: string; rows: [string, string][] };

const HELP_SECTIONS: HelpSection[] = [
  { title: "Type to format", rows: [
    ["# ␣ … ###### ␣", "Heading 1–6"],
    ["- ␣", "Bulleted list"],
    ["1. ␣", "Numbered list"],
    ["> ␣", "Block quote"],
    ["``` ␣", "Code block"],
    ["--- ", "Horizontal rule"],
    ["**text**", "Bold"],
    ["*text*", "Italic"],
  ]},
  { title: "Format", rows: [
    ["⌘B", "Bold"],
    ["⌘I", "Italic"],
    ["⌘K", "Link"],
    ["⌥⌘1 … ⌥⌘6", "Heading 1–6"],
    ["⌥⌘0", "Body text"],
    ["⇧⌘8 / ⇧⌘7", "Bulleted / Numbered list"],
  ]},
  { title: "Edit & find", rows: [
    ["⌘Z / ⇧⌘Z", "Undo / Redo"],
    ["⌘F", "Find"],
    ["⌥⌘F", "Find & Replace"],
    ["⌘G / ⇧⌘G", "Find Next / Previous"],
  ]},
  { title: "View", rows: [
    ["⌥⌘O", "Show / hide Outline"],
    ["⌥⌘M", "Markdown source ⇄ rich text"],
    ["View ▸ Focus Mode", "Dim all but the current line"],
    ["⌃⌘F", "Full Screen"],
  ]},
  { title: "Images", rows: [
    ["Paste / drag", "Saved beside the file, linked"],
  ]},
  { title: "Properties", rows: [
    ["Format ▸ Add Properties", "YAML frontmatter panel"],
  ]},
  { title: "Document", rows: [
    ["⌘N / ⌘O", "New / Open"],
    ["⌘S / ⇧⌘S", "Save / Save As"],
    ["⌘P", "Print"],
    ["File ▸ Export", "Export as HTML / PDF"],
  ]},
  { title: "Help", rows: [
    ["⇧⌘H", "Show this cheat sheet"],
    ["Esc", "Close it"],
  ]},
];

let helpScrim: HTMLElement | null = null;

function ensureHelp(): void {
  if (helpScrim) return;
  const style = document.createElement("style");
  style.textContent = HELP_CSS;
  document.head.appendChild(style);

  const cols = HELP_SECTIONS.map((s) => {
    const rows = s.rows
      .map(([k, d]) => `<div class="glyph-help-row"><span>${d}</span><kbd>${k}</kbd></div>`)
      .join("");
    return `<section><h3>${s.title}</h3>${rows}</section>`;
  }).join("");

  const scrim = document.createElement("div");
  scrim.className = "glyph-help-scrim";
  scrim.hidden = true;
  scrim.innerHTML = `
    <div class="glyph-help" role="dialog" aria-label="Glyph keyboard shortcuts">
      <h2>Glyph cheat sheet</h2>
      <p class="sub">Markdown shortcuts and keyboard commands.</p>
      <div class="glyph-help-cols">${cols}</div>
      <p class="glyph-help-foot">Press Esc or click outside to close · reopen with ⇧⌘H</p>
    </div>`;
  document.body.appendChild(scrim);
  helpScrim = scrim;

  scrim.addEventListener("click", (e) => {
    if (e.target === scrim) toggleHelp();   // click on backdrop closes
  });
  document.addEventListener("keydown", (e) => {
    if (e.key === "Escape" && helpScrim && !helpScrim.hidden) {
      e.preventDefault();
      toggleHelp();
    }
  });
}

function toggleHelp(): void {
  ensureHelp();
  helpScrim!.hidden = !helpScrim!.hidden;
}

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
      <button data-act="source">Markdown</button>
      <button data-act="outline">Outline</button>
      <button data-act="focus">Focus</button>
    </span>`;
  document.body.appendChild(status);
  countEl = status.querySelector(".glyph-count") as HTMLElement;
  outlineBtn = status.querySelector('[data-act="outline"]') as HTMLButtonElement;
  focusBtn = status.querySelector('[data-act="focus"]') as HTMLButtonElement;
  sourceBtn = status.querySelector('[data-act="source"]') as HTMLButtonElement;
  status.addEventListener("click", (e) => {
    const btn = (e.target as HTMLElement).closest("button");
    if (!btn) return;
    const act = btn.getAttribute("data-act");
    if (act === "outline") toggleOutline();
    else if (act === "focus") toggleFocus();
    else if (act === "source") toggleSource();
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
  let text: string;
  if (sourceMode && sourceEl) {
    text = sourceEl.value;
  } else {
    const view = getView();
    text = view ? view.state.doc.textBetween(0, view.state.doc.content.size, " ", " ") : "";
  }
  const words = (text.trim().match(/\S+/g) || []).length;
  const chars = text.length;
  const parts = [
    `${words.toLocaleString()} word${words === 1 ? "" : "s"}`,
    `${chars.toLocaleString()} character${chars === 1 ? "" : "s"}`,
  ];
  if (words > 0) parts.push(`${Math.max(1, Math.round(words / 200))} min read`);
  countEl.textContent = parts.join("  ·  ");
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
  // Narrow the reading pane so the panel sits beside the text, not over it.
  document.documentElement.classList.toggle("glyph-outline-on", !outlineEl.hidden);
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

// --- source (raw Markdown) mode ------------------------------------------

let sourceMode = false;
let sourceEl: HTMLTextAreaElement | null = null;
let sourceDebounce: ReturnType<typeof setTimeout> | undefined;

function ensureSource(): void {
  if (sourceEl) return;
  const style = document.createElement("style");
  style.textContent = `
.glyph-source{position:fixed;left:0;right:0;top:0;bottom:34px;z-index:8500;margin:0;border:0;
  outline:0;resize:none;box-sizing:border-box;padding:36px max(24px,calc(50% - 380px));
  background:#f5f1e8;color:#1a1822;font:14px/1.7 ui-monospace,"SF Mono",Menlo,monospace;tab-size:2;}
.glyph-source[hidden]{display:none;}
[data-theme=dark] .glyph-source{background:#1a1822;color:#e8e6ef;}
`;
  document.head.appendChild(style);

  const ta = document.createElement("textarea");
  ta.className = "glyph-source";
  ta.spellcheck = false;
  ta.hidden = true;
  document.body.appendChild(ta);
  sourceEl = ta;
  ta.addEventListener("input", () => {
    lastMarkdown = ta.value;
    updateCount();
    clearTimeout(sourceDebounce);
    sourceDebounce = setTimeout(() => postToHost({ type: "change", markdown: ta.value }), DEBOUNCE_MS);
  });
}

function toggleSource(): void {
  if (sourceMode) exitSource();
  else enterSource();
}

function enterSource(): void {
  ensureChrome();
  ensureSource();
  if (outlineEl && !outlineEl.hidden) toggleOutline();   // close distractions
  if (focusMode) toggleFocus();
  const md = fullMarkdown(crepe ? crepe.getMarkdown() : lastMarkdown);  // include frontmatter
  sourceEl!.value = md;
  sourceMode = true;
  root.style.display = "none";
  if (propsEl) propsEl.hidden = true;             // panel hidden while editing raw
  sourceEl!.hidden = false;
  sourceBtn?.classList.add("on");
  sourceEl!.focus();
  updateCount();
}

function exitSource(): void {
  if (!sourceEl) return;
  const md = sourceEl.value;
  sourceMode = false;
  sourceEl.hidden = true;
  root.style.display = "";
  sourceBtn?.classList.remove("on");
  postToHost({ type: "change", markdown: md });   // flush any pending edit
  applyFullMarkdown(md);                           // re-split frontmatter + render
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
    case "toggleSource": toggleSource(); return;
    case "addProperties": addProperties(); return;
    case "help": toggleHelp(); return;
  }
  if (sourceMode) return;   // formatting commands don't apply to raw source
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
    if (sourceMode && sourceEl) {
      sourceEl.value = text;
      lastMarkdown = text;
      updateCount();
    } else {
      applyFullMarkdown(text);
    }
  },
  getMarkdown: () =>
    sourceMode && sourceEl ? sourceEl.value : fullMarkdown(crepe?.getMarkdown() ?? ""),
  setTheme: (mode) => applyTheme(mode),
  cmd: (name) => runCommand(name),
  exportHTML: () => {
    const body = crepe ? crepe.editor.action(getHTML()) : "";
    return `<!doctype html><html><head><meta charset="utf-8">` +
      `<meta name="viewport" content="width=device-width, initial-scale=1">` +
      `<style>${exportCss}</style></head>` +
      `<body class="markdown-body">${body}</body></html>`;
  },
  imageSaved: (id, path) => {
    const resolve = pendingImages.get(id);
    if (resolve) { pendingImages.delete(id); resolve(path); }
  },
};

// Boot: mount a placeholder, tell the host we're ready; the host replies with the
// real document via window.glyph.setMarkdown(...).
void mount("# Glyph\n\nLoading…\n").then(() => postToHost({ type: "ready" }));
