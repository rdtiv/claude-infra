#!/usr/bin/env bash
# Push claude-infra's canonical hooks/agents/settings/commands into a downstream
# repo's .claude/ directory, without destroying repo-owned customizations.
#
# Governing decision: frontmatter (model:/effort:) is claude-infra-owned and
# gets patched in place. Agent BODIES are repo-owned and are NEVER written —
# only reported on. Hooks are pure mechanism and are overwritten verbatim.
#
# Usage:
#   ./sync-repo.sh <repo-path> [--dry-run] [--with-commands] [--allow-worktree]
#   ./sync-repo.sh --scan <dir>
#
# Recommended flow — sync into a worktree, not the main checkout, so the commit
# does not happen on the integration ground:
#   git -C <repo> worktree add .claude/worktrees/wt-infra-sync -b chore/sync origin/main
#   ./sync-repo.sh <repo>/.claude/worktrees/wt-infra-sync --allow-worktree
#   # commit + PR from that worktree, then remove it
#
# Never commits, never pushes — always leaves a dirty tree so the change lands
# through the target repo's own PR gate.
set -euo pipefail

CI_DIR="$(cd "$(dirname "$0")" && pwd)"

# ---------------------------------------------------------------------------
# --scan mode: find claude-infra installs under a directory tree.
# ---------------------------------------------------------------------------
if [ "${1:-}" = "--scan" ]; then
  SCAN_DIR="${2:-}"
  if [ -z "$SCAN_DIR" ]; then
    echo "usage: $0 --scan <dir>" >&2
    exit 1
  fi
  if [ ! -d "$SCAN_DIR" ]; then
    echo "error: scan dir does not exist: $SCAN_DIR" >&2
    exit 1
  fi
  echo "=== scanning $SCAN_DIR for claude-infra installs ==="
  found=0
  while IFS= read -r -d '' guard; do
    found=1
    repo_claude_hooks="$(dirname "$guard")"     # .../.claude/hooks
    repo_claude="$(dirname "$repo_claude_hooks")"  # .../.claude
    repo="$(dirname "$repo_claude")"                # repo root
    version_file="$repo_claude/.claude-infra-version"
    if [ -f "$version_file" ]; then
      stamp="$(tr '\n' ' ' < "$version_file" | sed 's/ *$//')"
      echo "  $repo  —  $stamp"
    else
      echo "  $repo  —  unstamped"
    fi
  done < <(find "$SCAN_DIR" -type f -path '*/.claude/hooks/agent-model-guard.mjs' \
             -not -path '*/node_modules/*' \
             -not -path '*/.claude/worktrees/*' \
             -print0)
  # The worktrees exclusion is load-bearing, not tidiness. A repo that tracks
  # .claude/hooks/ in git gives every mission worktree its own full copy, so
  # without it one repo with four live missions reports as five installs — and
  # invites someone to sync into an ephemeral checkout that is about to be
  # removed.
  if [ "$found" -eq 0 ]; then
    echo "  (none found)"
  fi
  exit 0
fi

# ---------------------------------------------------------------------------
# normal mode: ./sync-repo.sh <repo-path> [--dry-run] [--with-commands]
# ---------------------------------------------------------------------------
REPO_ARG="${1:-}"
if [ -z "$REPO_ARG" ] || [[ "$REPO_ARG" == --* ]]; then
  echo "usage: $0 <repo-path> [--dry-run] [--with-commands]" >&2
  echo "       $0 --scan <dir>" >&2
  exit 1
fi
shift

DRY_RUN=0
WITH_COMMANDS=0
ALLOW_WORKTREE=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --with-commands) WITH_COMMANDS=1 ;;
    --allow-worktree) ALLOW_WORKTREE=1 ;;
    *)
      echo "error: unknown argument: $arg" >&2
      exit 1
      ;;
  esac
done

if [ ! -d "$REPO_ARG" ]; then
  echo "error: repo path does not exist: $REPO_ARG" >&2
  exit 1
fi
REPO="$(cd "$REPO_ARG" && pwd)"

# Syncing into a worktree is refused BY DEFAULT but permitted with
# --allow-worktree, because the two cases look identical on disk and mean
# opposite things:
#
#   accidental — pointing at a live MISSION worktree. Ephemeral, removed at
#     /mission end, so the sync is thrown away. This is what the default catches.
#   deliberate — a worktree provisioned specifically to carry the sync PR. This
#     is the RECOMMENDED flow: the alternative is syncing into the main checkout
#     and committing from there, which the mission doctrine forbids ("the main
#     checkout is the integration ground; feature commits never happen there").
#
# An earlier revision refused both, which forced every sync through the main
# checkout and put the tool in direct conflict with the doctrine it ships beside.
case "$REPO" in
  */.claude/worktrees/*)
    if [ "$ALLOW_WORKTREE" -eq 0 ]; then
      echo "error: $REPO is a worktree, not a repo checkout." >&2
      echo "" >&2
      echo "  If this is a live MISSION worktree, sync the repo instead:" >&2
      echo "      $0 ${REPO%%/.claude/worktrees/*}" >&2
      echo "" >&2
      echo "  If you provisioned this worktree to carry the sync PR, re-run with" >&2
      echo "  --allow-worktree. That is the recommended flow, since syncing the" >&2
      echo "  main checkout means committing from it." >&2
      exit 1
    fi
    echo "note: syncing into a worktree (--allow-worktree). Commit and PR from here;" >&2
    echo "      do not let /mission end remove it before the PR is open." >&2
    echo >&2
    ;;
esac
TARGET_CLAUDE="$REPO/.claude"
TARGET_HOOKS="$TARGET_CLAUDE/hooks"
TARGET_AGENTS="$TARGET_CLAUDE/agents"
TARGET_COMMANDS="$TARGET_CLAUDE/commands"
TARGET_SCRIPTS="$TARGET_CLAUDE/scripts"
TARGET_WORKFLOWS="$TARGET_CLAUDE/workflows"

# Marker claiming a workflow file as claude-infra-owned. See the workflows/ block.
WF_MARKER="^// claude-infra-owned"

WRITTEN=()
SKIPPED=()
WARNINGS=()
RETIRED=()

# Retirement is driven by settings/retired.md — an explicit list of paths this repo
# used to install and no longer does.
#
# It is NOT "delete anything downstream I don't recognise." That deletes repo-OWNED
# artifacts: a repo's own hook, its own slash commands. Absence from claude-infra is
# not evidence of retirement, and where .claude/ is gitignored the deletion is
# unrecoverable. Only paths named in the manifest are removed.
retired_paths() { # $1 = subdir filter ("hooks" | "commands" | "scripts" | "workflows")
  local manifest="$CI_DIR/settings/retired.md" line
  [ -f "$manifest" ] || return 0
  while IFS= read -r line; do
    case "$line" in
      ""|"<!--"*|*"-->"|" "*) continue ;;
      "$1"/*) printf '%s\n' "$line" ;;
    esac
  done < "$manifest"
}

retire_from() { # $1 = subdir ("hooks" | "commands" | "scripts" | "workflows")
  local rel dest
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    dest="$TARGET_CLAUDE/$rel"
    [ -f "$dest" ] || continue          # -f, not -e: never try to rm a directory
    # Ownership governs DELETION as well as writing. The workflows/ copy loop
    # refuses to overwrite an unmarked file because that directory is shared
    # ground; retirement deletes by path, so without this check the very file the
    # copy loop protects gets removed the moment a workflows/ entry is listed.
    case "$rel" in
      workflows/*)
        if ! head -n 1 "$dest" | grep -q "$WF_MARKER"; then
          echo "  $(basename "$rel"): listed for retirement but NOT claude-infra-owned — left untouched"
          WARNINGS+=("$rel is listed in settings/retired.md but the downstream file lacks a claude-infra-owned marker comment on line 1; left untouched — delete it yourself if it is unwanted")
          continue
        fi
        ;;
    esac
    echo "  $(basename "$rel"): retired (listed in settings/retired.md)"
    RETIRED+=("$rel")
    # An `if`, not `[ ... ] && cmd`. As the last statement of the loop body this
    # sets the loop's — and therefore the function's — exit status, so under
    # `set -euo pipefail` a false test made `retire_from` return 1 and aborted the
    # whole run. --dry-run took that branch by definition, so the preview the
    # README tells operators to run first died silently at the first retirement
    # candidate and never reached the summary.
    if [ "$DRY_RUN" -eq 0 ]; then rm -f "$dest"; fi
  done < <(retired_paths "$1")
}

echo "=== sync-repo: $CI_DIR -> $REPO ==="
if [ "$DRY_RUN" -eq 1 ]; then
  echo "(dry run — no files will be written)"
fi
echo

# ---------------------------------------------------------------------------
# 1. Hooks — overwrite verbatim. Pure mechanism; drift here is staleness.
# ---------------------------------------------------------------------------
echo "--- hooks ---"
for f in "$CI_DIR"/hooks/*; do
  name="$(basename "$f")"
  dest="$TARGET_HOOKS/$name"
  if [ -f "$dest" ] && cmp -s "$f" "$dest"; then
    echo "  $name: already up to date"
    continue
  fi
  if [ -f "$dest" ]; then
    echo "  $name: updated (was stale)"
  else
    echo "  $name: created"
  fi
  WRITTEN+=("hooks/$name")
  if [ "$DRY_RUN" -eq 0 ]; then
    mkdir -p "$TARGET_HOOKS"
    cp "$f" "$dest"
  fi
done
retire_from "hooks"
echo

# ---------------------------------------------------------------------------
# 1b. Scripts — overwrite verbatim, same as hooks.
#
# These are executables the doctrine tells a session to RUN (hooks are what the
# harness runs on its behalf). They must travel with the doctrine that references
# them: commands/mission.md points at landed.sh, and a cloud session in a synced
# repo has no claude-infra checkout to fall back on — without this the reference
# dangles. Root-level scripts were outside every sync path until this existed.
# ---------------------------------------------------------------------------
echo "--- scripts ---"
if [ -d "$CI_DIR/scripts" ]; then
  for f in "$CI_DIR"/scripts/*; do
    [ -f "$f" ] || continue
    name="$(basename "$f")"
    dest="$TARGET_SCRIPTS/$name"
    if [ -f "$dest" ] && cmp -s "$f" "$dest"; then
      echo "  $name: already up to date"
      continue
    fi
    [ -f "$dest" ] && echo "  $name: updated (was stale)" || echo "  $name: created"
    WRITTEN+=("scripts/$name")
    if [ "$DRY_RUN" -eq 0 ]; then
      mkdir -p "$TARGET_SCRIPTS"
      cp "$f" "$dest"
      chmod +x "$dest"
    fi
  done
  retire_from "scripts"
else
  echo "  (none in claude-infra)"
fi
echo

# ---------------------------------------------------------------------------
# 1c. Workflows — copy, but never clobber a workflow this repo does not own.
#
# .claude/workflows/ is SHARED GROUND in a way hooks/ and scripts/ are not: it is
# a general Claude Code directory a downstream repo may already be using for its
# own dynamic workflows. The loop below is source-driven, so a repo's own workflow
# with no counterpart here is never visited and never removed — that is what makes
# every category in this script additive, and it is why retirement is manifest-
# driven rather than "delete what I don't recognise" (see retired_paths above).
#
# What source-driven does NOT cover is a NAME COLLISION. A plain `cp` would
# overwrite a repo-owned file that merely shares our filename, and report it as
# routine staleness. So ownership is explicit: we write only when the destination
# is absent or already carries WF_MARKER on its first line. Anything else belongs
# to the repo, and we warn instead of writing — the same ownership split that
# keeps agent BODIES repo-owned and reports them as drift.
# ---------------------------------------------------------------------------
echo "--- workflows ---"
if [ -d "$CI_DIR/workflows" ]; then
  for f in "$CI_DIR"/workflows/*.js; do
    [ -f "$f" ] || continue
    name="$(basename "$f")"
    dest="$TARGET_WORKFLOWS/$name"
    if [ -f "$dest" ] && cmp -s "$f" "$dest"; then
      echo "  $name: already up to date"
      continue
    fi
    if [ -f "$dest" ] && ! head -n 1 "$dest" | grep -q "$WF_MARKER"; then
      echo "  $name: exists downstream and is NOT claude-infra-owned — left untouched"
      WARNINGS+=("workflows/$name exists downstream without a claude-infra-owned marker comment on line 1; left untouched — delete it to accept the claude-infra version")
      continue
    fi
    [ -f "$dest" ] && echo "  $name: updated (was stale)" || echo "  $name: created"
    WRITTEN+=("workflows/$name")
    if [ "$DRY_RUN" -eq 0 ]; then
      mkdir -p "$TARGET_WORKFLOWS"
      cp "$f" "$dest"
    fi
  done
  retire_from "workflows"
else
  echo "  (none in claude-infra)"
fi
echo

# ---------------------------------------------------------------------------
# 2. Agents — narrow frontmatter patch. model:/effort: only; body untouched.
# ---------------------------------------------------------------------------
echo "--- agents ---"
AGENT_LOG="$(mktemp)"
CI_DIR="$CI_DIR" REPO="$REPO" DRY_RUN="$DRY_RUN" node --input-type=commonjs <<'NODE_AGENTS_EOF' | tee "$AGENT_LOG"
const { readFileSync, writeFileSync, existsSync, readdirSync } = require("node:fs");
const { join } = require("node:path");

const CI_DIR = process.env.CI_DIR;
const REPO = process.env.REPO;
const DRY_RUN = process.env.DRY_RUN === "1";

const canonicalDir = join(CI_DIR, "agents");
const targetDir = join(REPO, ".claude", "agents");

// 'd' flag gives per-group character indices, so the frontmatter block can be
// sliced out and replaced without touching a single byte outside it.
const FM_RE = /^---\r?\n([\s\S]*?)\r?\n---/d;

function splitFrontmatter(content) {
  const m = FM_RE.exec(content);
  if (!m) return null;
  const [innerStart, innerEnd] = m.indices[1];
  const bodyStart = m.indices[0][1]; // end of the full "---...---" match
  return { inner: m[1], innerStart, innerEnd, bodyStart };
}

function readKV(inner) {
  const out = {};
  for (const line of inner.split(/\r?\n/)) {
    const kv = line.match(/^([A-Za-z_][\w-]*)\s*:\s*(.*)$/);
    if (kv) out[kv[1].toLowerCase()] = kv[2].trim();
  }
  return out;
}

let canonicalNames = [];
try {
  canonicalNames = readdirSync(canonicalDir)
    .filter((f) => f.endsWith(".md"))
    .map((f) => f.slice(0, -3))
    .sort();
} catch {
  canonicalNames = [];
}

let downstreamNames = [];
try {
  downstreamNames = readdirSync(targetDir)
    .filter((f) => f.endsWith(".md"))
    .map((f) => f.slice(0, -3))
    .sort();
} catch {
  downstreamNames = [];
}

for (const name of canonicalNames) {
  const canonicalPath = join(canonicalDir, `${name}.md`);
  const targetPath = join(targetDir, `${name}.md`);

  if (!existsSync(targetPath)) {
    console.log(`[agent:${name}] MISSING downstream (present in claude-infra only)`);
    continue;
  }

  const canonicalContent = readFileSync(canonicalPath, "utf8");
  const canonicalFm = splitFrontmatter(canonicalContent);
  if (!canonicalFm) {
    console.log(`[agent:${name}] WARN — canonical file has no frontmatter block; skipping`);
    continue;
  }
  const canonicalKV = readKV(canonicalFm.inner);
  const canonicalModel = canonicalKV.model;
  const canonicalEffort = canonicalKV.effort;
  const canonicalBody = canonicalContent.slice(canonicalFm.bodyStart);

  const original = readFileSync(targetPath, "utf8");
  const targetFm = splitFrontmatter(original);
  if (!targetFm) {
    console.log(`[agent:${name}] SKIP — no leading frontmatter block found downstream; not touching`);
    continue;
  }

  const preBody = original.slice(targetFm.bodyStart);
  const targetLineCount = preBody.split(/\r?\n/).length;
  const canonicalLineCount = canonicalBody.split(/\r?\n/).length;
  if (preBody !== canonicalBody) {
    console.log(
      `[agent:${name}] body drift vs canonical (info only): target=${targetLineCount} lines, canonical=${canonicalLineCount} lines`,
    );
  }

  const eol = targetFm.inner.includes("\r\n") ? "\r\n" : "\n";
  const lines = targetFm.inner.split(/\r?\n/);

  let modelIdx = lines.findIndex((l) => /^model\s*:/.test(l));
  if (modelIdx === -1) {
    lines.unshift(`model: ${canonicalModel}`);
    modelIdx = 0;
    console.log(`[agent:${name}] WARN — downstream had no model: key; inserted one`);
  } else {
    lines[modelIdx] = `model: ${canonicalModel}`;
  }

  const effortIdx = lines.findIndex((l) => /^effort\s*:/.test(l));
  if (effortIdx === -1) {
    lines.splice(modelIdx + 1, 0, `effort: ${canonicalEffort}`);
  } else {
    lines[effortIdx] = `effort: ${canonicalEffort}`;
  }

  const newInner = lines.join(eol);
  const newContent =
    original.slice(0, targetFm.innerStart) + newInner + original.slice(targetFm.innerEnd);

  if (newContent === original) {
    console.log(
      `[agent:${name}] already up to date (model=${canonicalModel}, effort=${canonicalEffort}) — no change`,
    );
    continue;
  }

  if (DRY_RUN) {
    console.log(
      `[agent:${name}] would patch frontmatter (model=${canonicalModel}, effort=${canonicalEffort})`,
    );
    continue;
  }

  writeFileSync(targetPath, newContent);
  const reread = readFileSync(targetPath, "utf8");
  const rereadFm = splitFrontmatter(reread);
  const postBody = rereadFm ? reread.slice(rereadFm.bodyStart) : null;
  if (postBody !== preBody) {
    writeFileSync(targetPath, original); // restore — body must never move
    console.log(`[agent:${name}] FAILED — body changed after write; restored original content`);
  } else {
    console.log(
      `[agent:${name}] patched frontmatter (model=${canonicalModel}, effort=${canonicalEffort})`,
    );
  }
}

for (const name of downstreamNames) {
  if (!canonicalNames.includes(name)) {
    console.log(`[agent:${name}] EXTRA downstream (not present in claude-infra)`);
  }
}
NODE_AGENTS_EOF
echo

while IFS= read -r line; do
  case "$line" in
    *"patched frontmatter"*) WRITTEN+=("$line") ;;
    *"would patch frontmatter"*) WRITTEN+=("$line (dry run)") ;;
    *"SKIP —"*|*"WARN —"*|*"FAILED —"*|*"MISSING downstream"*|*"EXTRA downstream"*)
      WARNINGS+=("$line") ;;
    *"already up to date"*) SKIPPED+=("$line") ;;
  esac
done < "$AGENT_LOG"
rm -f "$AGENT_LOG"

# ---------------------------------------------------------------------------
# 3. settings.json — via the generalized merge-hook. Marker-based ensure()
#    leaves any pre-existing unrelated hook (e.g. sartora's Vercel env-pull)
#    untouched.
# ---------------------------------------------------------------------------
echo "--- settings.json ---"
PREFIX='${CLAUDE_PROJECT_DIR:-$PWD}'
if [ "$DRY_RUN" -eq 1 ]; then
  TMP_SETTINGS="$(mktemp)"
  if [ -f "$TARGET_CLAUDE/settings.json" ]; then
    cp "$TARGET_CLAUDE/settings.json" "$TMP_SETTINGS"
  else
    rm -f "$TMP_SETTINGS"
  fi
  node "$CI_DIR/settings/merge-hook.mjs" --target "$TMP_SETTINGS" --prefix "$PREFIX"
  rm -f "$TMP_SETTINGS"
  echo "  (dry run — settings.json on disk left untouched)"
else
  node "$CI_DIR/settings/merge-hook.mjs" --target "$TARGET_CLAUDE/settings.json" --prefix "$PREFIX"
  WRITTEN+=("settings.json (merged)")
fi
echo

# ---------------------------------------------------------------------------
# 4. commands/ — only if the dir already exists downstream, or --with-commands.
# ---------------------------------------------------------------------------
echo "--- commands ---"
if [ -d "$TARGET_COMMANDS" ] || [ "$WITH_COMMANDS" -eq 1 ]; then
  for f in "$CI_DIR"/commands/*.md; do
    name="$(basename "$f")"
    dest="$TARGET_COMMANDS/$name"
    if [ -f "$dest" ] && cmp -s "$f" "$dest"; then
      echo "  $name: already up to date"
      continue
    fi
    if [ -f "$dest" ]; then
      echo "  $name: updated (was stale)"
    else
      echo "  $name: created"
    fi
    WRITTEN+=("commands/$name")
    if [ "$DRY_RUN" -eq 0 ]; then
      mkdir -p "$TARGET_COMMANDS"
      cp "$f" "$dest"
    fi
  done
  retire_from "commands"
else
  echo "  .claude/commands/ does not exist downstream and --with-commands was not passed."
  echo "  Skipping — cloud sessions in this repo will not see /mission."
  WARNINGS+=("commands/ absent downstream — pass --with-commands to create it")
fi
echo

# ---------------------------------------------------------------------------
# 5. .gitignore — report only, never edit.
# ---------------------------------------------------------------------------
echo "--- .gitignore ---"
GITIGNORE="$REPO/.gitignore"
if [ -f "$GITIGNORE" ] && grep -qE '^\.claude/\*[[:space:]]*$' "$GITIGNORE"; then
  missing=()
  # .claude-infra-version belongs in this list: a blanket .claude/* sweeps the
  # provenance stamp up too, so it gets written but never tracked — every fresh
  # clone then reports "unstamped" and --scan quietly lies about what is deployed.
  for pat in '!.claude/agents/' '!.claude/hooks/' '!.claude/commands/' \
             '!.claude/scripts/' '!.claude/workflows/' \
             '!.claude/.claude-infra-version'; do
    grep -qF "$pat" "$GITIGNORE" || missing+=("$pat")
  done
  if [ "${#missing[@]}" -gt 0 ]; then
    echo "  WARNING: .gitignore ignores .claude/* but does not whitelist: ${missing[*]}"
    WARNINGS+=(".gitignore ignores .claude/* without whitelisting: ${missing[*]}")
  else
    echo "  .claude/* is ignored, but agents/hooks/commands are whitelisted — OK"
  fi
else
  echo "  no blanket .claude/* ignore found — OK"
fi
echo

# ---------------------------------------------------------------------------
# 6. Provenance stamp.
# ---------------------------------------------------------------------------
echo "--- provenance ---"
SHA="$(git -C "$CI_DIR" rev-parse HEAD)"
TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
if [ "$DRY_RUN" -eq 1 ]; then
  echo "  would write .claude-infra-version: $SHA @ $TS"
else
  mkdir -p "$TARGET_CLAUDE"
  printf '%s\n%s\n' "$SHA" "$TS" > "$TARGET_CLAUDE/.claude-infra-version"
  echo "  wrote .claude-infra-version: $SHA @ $TS"
  WRITTEN+=(".claude-infra-version")
fi
echo

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo "=== summary ==="
echo "written (${#WRITTEN[@]}):"
for w in "${WRITTEN[@]:-}"; do [ -n "$w" ] && echo "  - $w"; done
echo "skipped/no-op (${#SKIPPED[@]}):"
for s in "${SKIPPED[@]:-}"; do [ -n "$s" ] && echo "  - $s"; done
echo "retired (${#RETIRED[@]}):"
for r in "${RETIRED[@]:-}"; do [ -n "$r" ] && echo "  - $r"; done
echo "warnings (${#WARNINGS[@]}):"
for w in "${WARNINGS[@]:-}"; do [ -n "$w" ] && echo "  - $w"; done
echo
if [ "$DRY_RUN" -eq 1 ]; then
  echo "Dry run complete — nothing was written."
else
  echo "Done. This intentionally leaves a dirty tree in $REPO —"
  echo "commit and open a PR there through its own review gate. Not committed here."
fi
