#!/usr/bin/env node
// Idempotently merge the delegation hooks into a settings.json:
//   - PreToolUse  : agent-model-guard (subagents never inherit the session model)
//   - SessionStart: session-protocol (surface the standing ritual at session open)
//   - PreToolUse  : git-destruction-guard (no destructive git without review)
// Creates the file/objects as needed; never clobbers existing hooks or settings.
//
// Serves two callers:
//   - install.sh (user scope), with no args: targets ~/.claude/settings.json and
//     emits $HOME-prefixed commands. Byte-identical to the pre-generalization
//     behavior — this default path must never change.
//   - sync-repo.sh (repo scope): --target <repo>/.claude/settings.json
//     --prefix '${CLAUDE_PROJECT_DIR:-$PWD}' emits project-relative commands.
import { readFileSync, writeFileSync, existsSync, mkdirSync } from "node:fs";
import { homedir } from "node:os";
import { join, dirname } from "node:path";

function parseArgs(argv) {
  const out = { target: null, prefix: null };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === "--target") out.target = argv[++i];
    else if (a === "--prefix") out.prefix = argv[++i];
  }
  return out;
}

const { target, prefix } = parseArgs(process.argv.slice(2));

const path = target || join(homedir(), ".claude", "settings.json");
const cmdPrefix = prefix || "$HOME";

mkdirSync(dirname(path), { recursive: true });

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
  `node "${cmdPrefix}/.claude/hooks/agent-model-guard.mjs"`,
  "agent-model-guard",
);
ensure(
  "SessionStart",
  "startup|clear",
  `bash "${cmdPrefix}/.claude/hooks/session-protocol.sh"`,
  "session-protocol",
);
ensure(
  "PreToolUse",
  "Bash",
  `node "${cmdPrefix}/.claude/hooks/git-destruction-guard.mjs"`,
  "git-destruction-guard",
);

if (changed) writeFileSync(path, JSON.stringify(settings, null, 2) + "\n");
