#!/usr/bin/env bash
# Install/refresh the Claude Code delegation infrastructure into ~/.claude.
# Idempotent — safe to re-run after every git pull of this repo.
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"

mkdir -p "$HOME/.claude/agents" "$HOME/.claude/hooks" "$HOME/.claude/commands" \
         "$HOME/.claude/rules"
cp "$DIR"/agents/*.md "$HOME/.claude/agents/"
cp "$DIR"/hooks/* "$HOME/.claude/hooks/"
cp "$DIR"/commands/*.md "$HOME/.claude/commands/"
echo "agents, hooks, commands copied to ~/.claude"

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

# Verify
node --check "$HOME/.claude/hooks/agent-model-guard.mjs"
echo '{"tool_name":"Agent","tool_input":{"prompt":"x"}}' \
  | node "$HOME/.claude/hooks/agent-model-guard.mjs" | grep -q '"deny"' \
  && echo "hook verify: deny-on-inherit OK"
echo '{"tool_name":"Agent","tool_input":{"prompt":"x","subagent_type":"finder"}}' \
  | node "$HOME/.claude/hooks/agent-model-guard.mjs" | grep -q . \
  && { echo "hook verify: FAILED — pinned type was denied"; exit 1; } \
  || echo "hook verify: allow-pinned-type OK"

node --check "$HOME/.claude/hooks/git-destruction-guard.mjs"
echo '{"tool_name":"Bash","cwd":"/repo","tool_input":{"command":"git clean --force -d"}}' \
  | node "$HOME/.claude/hooks/git-destruction-guard.mjs" | grep -q '"deny"' \
  && echo "git-guard verify: deny-destructive-in-main OK" \
  || { echo "git-guard verify: FAILED — destructive git not denied"; exit 1; }
echo '{"tool_name":"Bash","cwd":"/repo","tool_input":{"command":"git status"}}' \
  | node "$HOME/.claude/hooks/git-destruction-guard.mjs" | grep -q . \
  && { echo "git-guard verify: FAILED — safe git was denied"; exit 1; } \
  || echo "git-guard verify: allow-safe-git OK"

node -e "JSON.parse(require('fs').readFileSync(process.env.HOME+'/.claude/settings.json'));console.log('settings.json valid')"

echo
echo "Done. Restart Claude Code sessions to pick up the agent types and commands."
