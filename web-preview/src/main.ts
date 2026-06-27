import MarkdownIt from "markdown-it";
import "./preview.css";

// Quick Look preview renderer. The extension loads this page, then calls
// window.glyphRender(markdownString) (see QuickLook/Preview/PreviewViewController.swift).
const md = new MarkdownIt({ html: false, linkify: true, typographer: true });

function render(src: string): void {
  const el = document.getElementById("content");
  if (el) el.innerHTML = md.render(src ?? "");
}

declare global {
  interface Window {
    glyphRender: (src: string) => void;
    webkit?: { messageHandlers?: { glyphPreview?: { postMessage: (m: unknown) => void } } };
  }
}

window.glyphRender = render;
window.webkit?.messageHandlers?.glyphPreview?.postMessage({ type: "ready" });
