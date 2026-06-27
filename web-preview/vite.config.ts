import { defineConfig } from "vite";
import { viteSingleFile } from "vite-plugin-singlefile";

// One self-contained preview.html (markdown-it + CSS inlined), served to the Quick
// Look preview extension's WKWebView over the app:// scheme. No network at runtime.
export default defineConfig({
  base: "./",
  plugins: [viteSingleFile()],
  build: {
    outDir: "../QuickLook/Resources/preview",
    emptyOutDir: true,
    target: "es2020",
    cssCodeSplit: false,
    assetsInlineLimit: 100_000_000,
    chunkSizeWarningLimit: 100_000,
    rollupOptions: { input: "index.html" },
  },
});
