#!/usr/bin/env node
// Idempotently reconcile the delegation hooks in a settings.json:
//   - PreToolUse  : agent-model-guard (subagents never inherit model or effort)
//   - PreToolUse  : git-destruction-guard (no destructive git without review)
//   - removed     : session-protocol (the session banner, deleted upstream)
// Creates the file/objects as needed; never clobbers existing hooks or settings.
//
// `remove()` exists because this tooling was additive-only, and deleting a hook
// upstream left every installed machine with a settings.json entry pointing at a
// file that no longer exists — a failing command at every session start. Adding a
// hook and retiring one have to be equally expressible.
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

/**
 * Retire a hook by marker. Mirrors ensure()'s matching exactly, so it is as
 * conservative about unrelated entries: an entry is dropped only if one of its
 * hooks names the marker, and an event key is dropped only once it is empty.
 * Anything the installer did not put there — a repo's own UserPromptSubmit hook,
 * for instance — is untouched.
 */
function remove(marker) {
  let hit = false;
  for (const event of Object.keys(settings.hooks)) {
    const list = settings.hooks[event];
    if (!Array.isArray(list)) continue; // not ours to touch, and .filter would throw
    const before = list.length;
    const kept = list.filter(
      (entry) => !(entry.hooks || []).some((h) => (h.command || "").includes(marker)),
    );
    if (kept.length === before) continue; // this event had nothing of ours in it
    hit = true;
    // Drop the event key only when WE emptied it. An event left empty by someone
    // else is theirs, and deleting it here would be a silent edit to settings we
    // never wrote.
    if (kept.length === 0) delete settings.hooks[event];
    else settings.hooks[event] = kept;
  }
  if (hit) {
    changed = true;
    console.log(`settings.json: ${marker} removed (retired upstream)`);
  }
}

ensure(
  "PreToolUse",
  "Agent",
  `node "${cmdPrefix}/.claude/hooks/agent-model-guard.mjs"`,
  "agent-model-guard",
);
ensure(
  "PreToolUse",
  "Bash",
  `node "${cmdPrefix}/.claude/hooks/git-destruction-guard.mjs"`,
  "git-destruction-guard",
);

// The session banner was deleted upstream: ~250 words injected into every session
// in every repo, restating doctrine that lives in the rules file and /mission.
// Machines installed before that still carry the entry, so retire it on every run.
remove("session-protocol");

if (changed) writeFileSync(path, JSON.stringify(settings, null, 2) + "\n");
