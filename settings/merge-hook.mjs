#!/usr/bin/env node
// Idempotently merge the agent-model-guard PreToolUse hook into
// ~/.claude/settings.json (creates the file/objects as needed, never
// clobbers existing hooks or other settings).
import { readFileSync, writeFileSync, existsSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

const path = join(homedir(), ".claude", "settings.json");
const settings = existsSync(path) ? JSON.parse(readFileSync(path, "utf8")) : {};

const COMMAND = 'node "$HOME/.claude/hooks/agent-model-guard.mjs"';
settings.hooks ??= {};
settings.hooks.PreToolUse ??= [];

const already = settings.hooks.PreToolUse.some(
  (entry) =>
    entry.matcher === "Agent" &&
    (entry.hooks || []).some((h) => (h.command || "").includes("agent-model-guard")),
);

if (already) {
  console.log("settings.json: agent-model-guard hook already present — no change");
} else {
  settings.hooks.PreToolUse.push({
    matcher: "Agent",
    hooks: [{ type: "command", command: COMMAND }],
  });
  writeFileSync(path, JSON.stringify(settings, null, 2) + "\n");
  console.log("settings.json: agent-model-guard hook added");
}
