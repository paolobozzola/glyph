import { Crepe } from "@milkdown/crepe";
import "@milkdown/crepe/theme/common/style.css";
import "@milkdown/crepe/theme/frame.css";

// ---------------------------------------------------------------------------
// Glyph editor bundle — M0 bridge spike.
//
// Contract with the Swift host (see docs/SHELL.md §4):
//   JS  -> Swift : window.webkit.messageHandlers.glyph.postMessage(payload)
//                  { type: "ready" }                       on mount
//                  { type: "change", markdown: string }    debounced ~300ms
//   Swift -> JS  : window.glyph.setMarkdown(text)          load a document
//                  window.glyph.getMarkdown()              read current text
//                  window.glyph.setTheme("light"|"dark")   follow appearance
// ---------------------------------------------------------------------------

type Bridge = {
  setMarkdown: (text: string) => void;
  getMarkdown: () => string;
  setTheme: (mode: "light" | "dark") => void;
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
const DEBOUNCE_MS = 300;

let crepe: Crepe | null = null;
let debounceTimer: ReturnType<typeof setTimeout> | undefined;

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
      debounceTimer = setTimeout(() => {
        postToHost({ type: "change", markdown: md });
      }, DEBOUNCE_MS);
    });
  });
}

window.glyph = {
  setMarkdown: (text: string) => {
    void mount(text);
  },
  getMarkdown: () => crepe?.getMarkdown() ?? "",
  setTheme: (mode) => {
    document.documentElement.dataset.theme = mode;
  },
};

// Boot: mount a placeholder, then tell the host we're ready. The host replies by
// calling window.glyph.setMarkdown(...) with the real document contents.
void mount("# Glyph\n\nLoading…\n").then(() => postToHost({ type: "ready" }));
