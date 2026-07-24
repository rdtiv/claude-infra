#!/usr/bin/env node
/**
 * Generates setup-prompt.md from settings/setup-prompt.template.md.
 *
 * The template embeds the real agent/hook/doctrine files via
 * `<!-- include:PATH -->` marker lines (PATH is repo-root-relative). This
 * script substitutes each marker with the verbatim contents of PATH, so the
 * no-git fallback prompt can never drift from the files it's supposed to be
 * copying.
 *
 * Usage:
 *   node build-setup-prompt.mjs          # regenerate setup-prompt.md
 *   node build-setup-prompt.mjs --check  # verify setup-prompt.md is current; no writes
 */
import { readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = dirname(fileURLToPath(import.meta.url));
const TEMPLATE_PATH = join(ROOT, "settings", "setup-prompt.template.md");
const OUTPUT_PATH = join(ROOT, "setup-prompt.md");

const INCLUDE_RE = /^<!--\s*include:(\S+)\s*-->$/;

function render() {
  const template = readFileSync(TEMPLATE_PATH, "utf8");
  const lines = template.split("\n");

  const out = lines.map((line) => {
    const m = line.match(INCLUDE_RE);
    if (!m) return line;

    const relPath = m[1];
    const absPath = join(ROOT, relPath);
    let contents;
    try {
      contents = readFileSync(absPath, "utf8");
    } catch (err) {
      throw new Error(
        `build-setup-prompt: include marker points at a missing file: "${relPath}" ` +
          `(resolved to ${absPath}). Fix the marker in ${TEMPLATE_PATH} or restore the file. ` +
          `(${err.code || err.message})`,
      );
    }
    // Strip exactly one trailing newline so the included content sits cleanly
    // inside the surrounding ``` fence without introducing a blank line.
    if (contents.endsWith("\n")) contents = contents.slice(0, -1);
    return contents;
  });

  return out.join("\n");
}

function main() {
  const check = process.argv.includes("--check");
  const generated = render();

  if (!check) {
    writeFileSync(OUTPUT_PATH, generated);
    console.log(`build-setup-prompt: wrote ${OUTPUT_PATH}`);
    return;
  }

  let committed;
  try {
    committed = readFileSync(OUTPUT_PATH, "utf8");
  } catch (err) {
    console.error(
      `build-setup-prompt --check: cannot read ${OUTPUT_PATH} (${err.code || err.message})`,
    );
    process.exit(1);
  }

  if (generated === committed) {
    console.log("build-setup-prompt --check: setup-prompt.md is up to date");
    process.exit(0);
  }

  const genLines = generated.split("\n");
  const oldLines = committed.split("\n");
  const max = Math.max(genLines.length, oldLines.length);
  let firstDiff = -1;
  for (let i = 0; i < max; i++) {
    if (genLines[i] !== oldLines[i]) {
      firstDiff = i;
      break;
    }
  }

  console.error("build-setup-prompt --check: setup-prompt.md is STALE relative to the template.");
  console.error(`First differing line: ${firstDiff + 1}`);
  console.error(`  committed: ${JSON.stringify(oldLines[firstDiff] ?? "<end of file>")}`);
  console.error(`  generated: ${JSON.stringify(genLines[firstDiff] ?? "<end of file>")}`);
  console.error(
    `(${oldLines.length} lines committed vs ${genLines.length} lines generated) ` +
      "Run `node build-setup-prompt.mjs` to regenerate.",
  );
  process.exit(1);
}

main();
