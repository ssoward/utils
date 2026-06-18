import { defineConfig } from "vite";
import webExtension from "vite-plugin-web-extension";
import { copyFileSync, mkdirSync } from "fs";
import { resolve } from "path";

// Custom plugin to copy static assets into dist/
function copyAssets() {
  return {
    name: "copy-assets",
    closeBundle() {
      const icons = ["icon-16", "icon-32", "icon-48", "icon-128"];
      mkdirSync("dist/assets/icons", { recursive: true });
      for (const icon of icons) {
        copyFileSync(
          resolve(__dirname, `assets/icons/${icon}.png`),
          resolve(__dirname, `dist/assets/icons/${icon}.png`)
        );
      }
    },
  };
}

export default defineConfig({
  plugins: [
    webExtension({
      manifest: "manifest.json",
    }),
    copyAssets(),
  ],
  build: {
    outDir: "dist",
    emptyOutDir: true,
    sourcemap: false,
  },
});
