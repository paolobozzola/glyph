import { Crepe } from "@milkdown/crepe";
import "@milkdown/crepe/theme/common/style.css";
import frameLight from "@milkdown/crepe/theme/frame.css?inline";
import frameDark from "@milkdown/crepe/theme/frame-dark.css?inline";

// Quick Look preview renderer. The extension loads this page, then calls
// window.glyphRender(markdownString) (see QuickLook/Preview/PreviewViewController.swift).
//
// It renders with the SAME engine + theme as the editor (Milkdown Crepe, "frame" theme),
// but read-only and with editing chrome disabled — so a preview looks exactly like the
// document does in the editor.

const themeStyle = document.createElement("style");
themeStyle.id = "glyph-theme";
document.head.appendChild(themeStyle);

function applyTheme(): void {
  const dark = window.matchMedia("(prefers-color-scheme: dark)").matches;
  themeStyle.textContent = dark ? frameDark : frameLight;
  document.documentElement.dataset.theme = dark ? "dark" : "light";
  document.documentElement.style.colorScheme = dark ? "dark" : "light";
}
applyTheme();
window.matchMedia("(prefers-color-scheme: dark)").addEventListener("change", applyTheme);

// Harmonic heading scale — keep in sync with web/src/main.ts so the preview matches the
// editor. The frame theme's default steps are only ~1.17 apart (H1≈H2); this 1.25 modular
// scale anchored to the 16px body makes each level clearly distinct.
const headingScale = document.createElement("style");
headingScale.id = "glyph-heading-scale";
headingScale.textContent = `
.milkdown .ProseMirror h1{font-size:49px;line-height:1.15}
.milkdown .ProseMirror h2{font-size:39px;line-height:1.2}
.milkdown .ProseMirror h3{font-size:31px;line-height:1.25}
.milkdown .ProseMirror h4{font-size:25px;line-height:1.3}
.milkdown .ProseMirror h5{font-size:20px;line-height:1.4}
.milkdown .ProseMirror h6{font-size:16px;line-height:1.5}
`;
document.head.appendChild(headingScale);

// The editor surfaces YAML frontmatter in a properties panel rather than the body, so
// strip a leading frontmatter block to match what the editor shows.
function stripFrontmatter(text: string): string {
  const lines = text.split("\n");
  if ((lines[0] ?? "").trim() !== "---") return text;
  for (let i = 1; i < lines.length; i++) {
    const t = lines[i].trim();
    if (t === "---" || t === "...") {
      let rest = lines.slice(i + 1);
      while (rest.length && rest[0].trim() === "") rest = rest.slice(1);
      return rest.join("\n");
    }
  }
  return text;
}

let crepe: Crepe | null = null;

async function render(src: string): Promise<void> {
  const root = document.getElementById("app");
  if (!root) return;
  if (crepe) {
    await crepe.destroy();
    crepe = null;
  }
  crepe = new Crepe({
    root,
    defaultValue: stripFrontmatter(src ?? ""),
    // Disable interactive editing chrome — a preview is read-only.
    features: {
      [Crepe.Feature.Toolbar]: false,
      [Crepe.Feature.BlockEdit]: false,
      [Crepe.Feature.Placeholder]: false,
      [Crepe.Feature.LinkTooltip]: false,
      [Crepe.Feature.Cursor]: false,
    },
  });
  await crepe.create();
  crepe.setReadonly(true);
}

declare global {
  interface Window {
    glyphRender: (src: string) => void;
    webkit?: { messageHandlers?: { glyphPreview?: { postMessage: (m: unknown) => void } } };
  }
}

window.glyphRender = (src: string) => { void render(src); };
window.webkit?.messageHandlers?.glyphPreview?.postMessage({ type: "ready" });
