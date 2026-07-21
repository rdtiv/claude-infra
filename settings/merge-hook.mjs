#!/usr/bin/env node
// Idempotently merge the delegation hooks into ~/.claude/settings.json:
//   - PreToolUse  : agent-model-guard (subagents never inherit the session model)
//   - SessionStart: session-protocol (surface the standing ritual at session open)
// Creates the file/objects as needed; never clobbers existing hooks or settings.
import { readFileSync, writeFileSync, existsSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

const path = join(homedir(), ".claude", "settings.json");
const settings = existsSync(path) ? JSON.parse(readFileSync(path, "utf8")) : {};
settings.hooks ??= {};

let changed = false;

function ensure(event, matcher, command, marker) {
  settings.hooks[event] ??= [];
  const present = settings.hooks[event].some((entry) =>
    (entry.hooks || []).some((h) => (h.command || "").includes(marker)),
  );
  if (present) {
    console.log(`settings.json: ${marker} already present — no change`);
    return;
  }
  const entry = { hooks: [{ type: "command", command }] };
  if (matcher) entry.matcher = matcher;
  settings.hooks[event].push(entry);
  changed = true;
  console.log(`settings.json: ${marker} added (${event})`);
}

ensure(
  "PreToolUse",
  "Agent",
  'node "$HOME/.claude/hooks/agent-model-guard.mjs"',
  "agent-model-guard",
);
ensure(
  "SessionStart",
  "startup|clear",
  'bash "$HOME/.claude/hooks/session-protocol.sh"',
  "session-protocol",
);

if (changed) writeFileSync(path, JSON.stringify(settings, null, 2) + "\n");
