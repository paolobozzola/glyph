import { Crepe } from "@milkdown/crepe";
import { callCommand } from "@milkdown/kit/utils";
import { undoCommand, redoCommand } from "@milkdown/kit/plugin/history";

import "@milkdown/crepe/theme/common/style.css";
// Theme layers are imported as raw strings so we can swap light/dark at runtime.
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
//                  window.glyph.getMarkdown()             read current text (for save)
//                  window.glyph.setTheme("light"|"dark")  follow appearance
//                  window.glyph.cmd("undo"|"redo")        menu/keyboard -> editor
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
  crepe = new Crepe({ root, defaultValue: markdown });
  await crepe.create();
  crepe.on((listener) => {
    listener.markdownUpdated((_ctx, md) => {
      clearTimeout(debounceTimer);
      debounceTimer = setTimeout(() => postToHost({ type: "change", markdown: md }), DEBOUNCE_MS);
    });
  });
}

function runCommand(name: string): void {
  const editor = crepe?.editor;
  if (!editor) return;
  if (name === "undo") editor.action(callCommand(undoCommand.key));
  else if (name === "redo") editor.action(callCommand(redoCommand.key));
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
