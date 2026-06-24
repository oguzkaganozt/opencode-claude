import { defineConfig } from "tsup"

export default defineConfig({
  entry: ["src/index.ts"],
  format: ["esm"],
  target: "es2022",
  clean: true,
  dts: false,
  minify: true,
  external: ["@rynfar/meridian", "@opencode-ai/plugin"],
})
