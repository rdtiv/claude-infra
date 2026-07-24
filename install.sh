#!/usr/bin/env bash
# Install/refresh the Claude Code delegation infrastructure into ~/.claude.
# Idempotent — safe to re-run after every git pull of this repo.
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"

mkdir -p "$HOME/.claude/agents" "$HOME/.claude/hooks" "$HOME/.claude/commands"
cp "$DIR"/agents/*.md "$HOME/.claude/agents/"
cp "$DIR"/hooks/* "$HOME/.claude/hooks/"
cp "$DIR"/commands/*.md "$HOME/.claude/commands/"
echo "agents, hook, commands copied to ~/.claude"

node "$DIR/settings/merge-hook.mjs"

if ! grep -q "## Delegation & session modes" "$HOME/.claude/CLAUDE.md" 2>/dev/null; then
  cat "$DIR/settings/claude-md-snippet.md" >> "$HOME/.claude/CLAUDE.md"
  echo "doctrine appended to ~/.claude/CLAUDE.md"
else
  echo "doctrine already present in ~/.claude/CLAUDE.md — not duplicated"
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
