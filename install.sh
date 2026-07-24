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
