#!/usr/bin/env bash
# Install/refresh the Claude Code delegation infrastructure into ~/.claude.
# Idempotent — safe to re-run after every git pull of this repo.
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"

# Marker claiming a workflow file as installer-owned. See the workflows/ block below.
WF_MARKER="^// claude-infra-owned"

mkdir -p "$HOME/.claude/agents" "$HOME/.claude/hooks" "$HOME/.claude/commands" \
         "$HOME/.claude/rules" "$HOME/.claude/scripts" "$HOME/.claude/workflows"
cp "$DIR"/agents/*.md "$HOME/.claude/agents/"
cp "$DIR"/hooks/* "$HOME/.claude/hooks/"
cp "$DIR"/commands/*.md "$HOME/.claude/commands/"
# scripts/ holds executables the doctrine tells you to RUN (as opposed to hooks,
# which the harness runs for you). They have to land wherever the doctrine that
# references them lands, or /mission points at a file that isn't there.
cp "$DIR"/scripts/* "$HOME/.claude/scripts/"
chmod +x "$HOME"/.claude/scripts/* 2>/dev/null || true

# workflows/ holds dynamic-workflow scripts the harness DISCOVERS by name and runs
# itself — no chmod, it reads them rather than executing them.
#
# Unlike hooks/ and scripts/, which this repo owns outright, ~/.claude/workflows/ is
# SHARED GROUND: it is a general Claude Code directory an operator may already have
# populated by hand. A same-name collision there is not ours to resolve by
# overwriting. So we claim only files carrying WF_MARKER and leave anything else
# exactly as found — the same ownership split that keeps agent BODIES repo-owned.
for f in "$DIR"/workflows/*.js; do
  [ -f "$f" ] || continue
  name="$(basename "$f")"
  dest="$HOME/.claude/workflows/$name"
  if [ -f "$dest" ] && ! head -n 1 "$dest" | grep -q "$WF_MARKER"; then
    echo "  ! $name already exists in ~/.claude/workflows and is not claude-infra-owned"
    echo "    — left untouched. Delete it to accept the claude-infra version."
    continue
  fi
  cp "$f" "$dest"
done
echo "agents, hooks, commands, scripts, workflows copied to ~/.claude"

# Retire artifacts deleted upstream, per settings/retired.md. Copying is not enough:
# a file removed from this repo stays on every machine that installed it before the
# removal, and in the hook case it stays wired in settings.json and fails at every
# session start. merge-hook.mjs (below) strips the matching settings entries.
#
# Driven by the manifest rather than "delete anything not in the repo" — the latter
# would remove the operator's own agents, hooks, and commands from ~/.claude.
#
# Ownership applies to DELETION too, not just to writing. The copy loop above
# refuses to overwrite an unmarked workflow because ~/.claude/workflows/ is shared
# ground — but retirement deletes by path, so without this the same unmarked file
# the copy loop protects would be removed outright the moment a workflows/ entry
# lands in the manifest. Retiring our own file must never take an operator's file
# that merely shares its name.
while IFS= read -r rel; do
  case "$rel" in ""|"<!--"*|*"-->"|" "*) continue ;; esac
  target="$HOME/.claude/$rel"
  if [ -f "$target" ]; then
    case "$rel" in
      workflows/*)
        if ! head -n 1 "$target" | grep -q "$WF_MARKER"; then
          echo "  ! .claude/$rel is listed for retirement but is not claude-infra-owned"
          echo "    — left untouched. Delete it yourself if you no longer want it."
          continue
        fi
        ;;
    esac
    rm -f "$target"
    echo "retired: .claude/$rel"
  fi
done < "$DIR/settings/retired.md"

node "$DIR/settings/merge-hook.mjs"

# Doctrine lives in an installer-OWNED rules file, overwritten wholesale every
# run. ~/.claude/rules/*.md is auto-loaded at user scope, so this needs no entry
# in CLAUDE.md and no marker parsing inside it.
#
# It used to be appended into ~/.claude/CLAUDE.md behind a "heading already
# present?" guard, which made every update after the first a silent no-op — the
# doctrine on an installed machine could never change again. That is the bug
# this replaces; do not reintroduce a conditional here.
cp -f "$DIR/settings/delegation-rule.md" "$HOME/.claude/rules/claude-infra-delegation.md"
echo "doctrine written to ~/.claude/rules/claude-infra-delegation.md"

# Legacy installs: warn, never migrate. The old section has no reliable end
# boundary — on a real machine it is followed by the operator's own preferences
# with no intervening "## " heading, so a "replace to the next heading" migration
# would eat them. The operator deletes it by hand; we only make sure they know.
if grep -q "^## Delegation & session modes" "$HOME/.claude/CLAUDE.md" 2>/dev/null; then
  cat <<'WARN'

  ! ~/.claude/CLAUDE.md still contains a legacy "## Delegation & session modes"
    section. Doctrine now ships as ~/.claude/rules/claude-infra-delegation.md,
    so that section is a stale second copy and will be loaded alongside it.
    Delete it by hand — this installer will not touch your CLAUDE.md.

WARN
fi

# Post-install sanity: did the copy actually land, and is settings.json still valid?
for f in "$HOME/.claude/hooks/agent-model-guard.mjs" \
         "$HOME/.claude/hooks/git-destruction-guard.mjs" \
         "$HOME/.claude/rules/claude-infra-delegation.md"; do
  [ -f "$f" ] || { echo "install: FAILED — $f missing after copy"; exit 1; }
done
node -e "JSON.parse(require('fs').readFileSync(process.env.HOME+'/.claude/settings.json'));console.log('settings.json valid')"

# Behavior is verified by the suite, against the source tree. Skipped when the
# suite is what invoked us — verify.sh runs install.sh against scratch HOMEs, and
# without this guard that would recurse.
if [ -z "${CLAUDE_INFRA_SKIP_VERIFY:-}" ]; then
  echo
  bash "$DIR/verify.sh"
fi

echo
echo "Done. Restart Claude Code sessions to pick up the agent types and commands."
echo "Note: the guard now requires every house agent to pin model AND effort, so"
echo "hooks and agents must move together — always re-run this after a git pull."
