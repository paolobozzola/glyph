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
:root{--glyph-body:16px;--glyph-h1:2.75;--glyph-h2:2;--glyph-h3:1.5;--glyph-h4:1.25;--glyph-h5:1.125;--glyph-h6:1;
  --glyph-font-title:ui-serif,"New York",Georgia,serif;
  --glyph-font-body:-apple-system,BlinkMacSystemFont,system-ui,sans-serif;
  --glyph-font-code:ui-monospace,"SF Mono",Menlo,monospace;}
.milkdown{--crepe-font-title:var(--glyph-font-title);--crepe-font-default:var(--glyph-font-body);--crepe-font-code:var(--glyph-font-code);}
.milkdown .ProseMirror,.milkdown .ProseMirror p{font-size:var(--glyph-body,16px);}
.milkdown .ProseMirror h1{font-size:calc(var(--glyph-body,16px)*var(--glyph-h1,2.75));line-height:1.15}
.milkdown .ProseMirror h2{font-size:calc(var(--glyph-body,16px)*var(--glyph-h2,2));line-height:1.2}
.milkdown .ProseMirror h3{font-size:calc(var(--glyph-body,16px)*var(--glyph-h3,1.5));line-height:1.25}
.milkdown .ProseMirror h4{font-size:calc(var(--glyph-body,16px)*var(--glyph-h4,1.25));line-height:1.3}
.milkdown .ProseMirror h5{font-size:calc(var(--glyph-body,16px)*var(--glyph-h5,1.125));line-height:1.4}
.milkdown .ProseMirror h6{font-size:calc(var(--glyph-body,16px)*var(--glyph-h6,1));line-height:1.5}
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

// Same friendly-name → CSS stack map as the editor (keep in sync). Lets the QL extension
// apply the user's typography so the preview is identical to the editor.
const FONT_STACKS: Record<string, string> = {
  "New York": 'ui-serif, "New York", Georgia, serif',
  "Charter": 'Charter, Georgia, "Times New Roman", serif',
  "Iowan Old Style": '"Iowan Old Style", Georgia, serif',
  "Georgia": 'Georgia, "Times New Roman", serif',
  "System": '-apple-system, BlinkMacSystemFont, system-ui, sans-serif',
  "Helvetica Neue": '"Helvetica Neue", Helvetica, Arial, sans-serif',
  "Avenir": '"Avenir Next", Avenir, sans-serif',
  "SF Mono": 'ui-monospace, "SF Mono", Menlo, monospace',
  "Menlo": 'Menlo, Monaco, monospace',
  "Monaco": 'Monaco, Menlo, monospace',
};

function applySettings(s: {
  bodyPx?: number; headings?: number[];
  fonts?: { heading?: string; body?: string; code?: string };
}): void {
  const root = document.documentElement.style;
  if (typeof s.bodyPx === "number") root.setProperty("--glyph-body", `${s.bodyPx}px`);
  if (Array.isArray(s.headings)) {
    ["h1", "h2", "h3", "h4", "h5", "h6"].forEach((h, i) => {
      if (typeof s.headings![i] === "number") root.setProperty(`--glyph-${h}`, String(s.headings![i]));
    });
  }
  if (s.fonts) {
    const set = (v: string, name?: string) => { if (name) root.setProperty(v, FONT_STACKS[name] ?? name); };
    set("--glyph-font-title", s.fonts.heading);
    set("--glyph-font-body", s.fonts.body);
    set("--glyph-font-code", s.fonts.code);
  }
}

declare global {
  interface Window {
    glyphRender: (src: string) => void;
    glyphApplySettings: (s: unknown) => void;
    webkit?: { messageHandlers?: { glyphPreview?: { postMessage: (m: unknown) => void } } };
  }
}

window.glyphRender = (src: string) => { void render(src); };
window.glyphApplySettings = (s: unknown) => applySettings(s as any);
window.webkit?.messageHandlers?.glyphPreview?.postMessage({ type: "ready" });
