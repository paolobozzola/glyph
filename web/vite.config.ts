import { defineConfig } from "vite";
import { viteSingleFile } from "vite-plugin-singlefile";

// The editor ships as ONE self-contained index.html (JS + CSS + assets inlined),
// so the macOS app can serve it over the app:// scheme with zero network access.
// Output goes straight into the app target's resources.
export default defineConfig({
  base: "./",
  plugins: [viteSingleFile()],
  build: {
    outDir: "../Glyph/Resources/editor",
    emptyOutDir: true,
    target: "es2020",
    cssCodeSplit: false,
    assetsInlineLimit: 100_000_000,
    chunkSizeWarningLimit: 100_000,
  },
});
