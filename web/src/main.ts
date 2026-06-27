import { Crepe } from "@milkdown/crepe";
import { callCommand } from "@milkdown/kit/utils";
import { undoCommand, redoCommand } from "@milkdown/kit/plugin/history";
import { remarkStringifyOptionsCtx } from "@milkdown/kit/core";
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

import "@milkdown/crepe/theme/common/style.css";
import frameLight from "@milkdown/crepe/theme/frame.css?inline";
import frameDark from "@milkdown/crepe/theme/frame-dark.css?inline";

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
  await crepe.create();
  crepe.on((listener) => {
    listener.markdownUpdated((_ctx, md) => {
      if (md === lastMarkdown) return; // ignore initial render / no-op updates
      lastMarkdown = md;
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

function runCommand(name: string): void {
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
};

// Boot: mount a placeholder, tell the host we're ready; the host replies with the
// real document via window.glyph.setMarkdown(...).
void mount("# Glyph\n\nLoading…\n").then(() => postToHost({ type: "ready" }));
