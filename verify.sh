#!/usr/bin/env bash
# claude-infra regression suite.
#
# Run directly (`./verify.sh`) or via ./install.sh, which calls it after copying.
# Everything runs against scratch copies — this suite never writes to $HOME, to
# the repo it is run from, or to any downstream repo.
#
# Why the fixtures can live inline here: git-destruction-guard inspects the Bash
# *command text* of the calling tool call. Invoking this file as `bash verify.sh`
# means the command text is just that, so fixtures containing destructive git are
# never seen by the guard. Inlining the same fixtures directly into a tool call
# gets the call denied. Keep them here.
set -uo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
fail=0
section() { printf '\n=== %s ===\n' "$1"; }
ok()  { echo "  PASS  $1"; }
bad() { echo "  FAIL  $1"; fail=$((fail + 1)); }

SCRATCH="$(mktemp -d)"
trap 'rm -rf "$SCRATCH"' EXIT

# ---------------------------------------------------------------------------
section "syntax"
for f in "$DIR"/hooks/*.mjs "$DIR"/settings/*.mjs "$DIR"/build-setup-prompt.mjs; do
  [ -f "$f" ] || continue
  if node --check "$f" > "$SCRATCH/syn.log" 2>&1; then
    ok "node --check $(basename "$f")"
  else
    bad "node --check $(basename "$f") — $(cat "$SCRATCH/syn.log")"
  fi
done
if bash -n "$DIR/install.sh" 2>/dev/null; then ok "bash -n install.sh"; else bad "bash -n install.sh"; fi
[ -f "$DIR/sync-repo.sh" ] && { bash -n "$DIR/sync-repo.sh" 2>/dev/null && ok "bash -n sync-repo.sh" || bad "bash -n sync-repo.sh"; }

# ---------------------------------------------------------------------------
GG="$DIR/hooks/git-destruction-guard.mjs"
gg() { # $1=label $2=expect $3=cwd $4=command
  local json out
  json=$(node -e 'process.stdout.write(JSON.stringify({tool_name:"Bash",cwd:process.argv[1],tool_input:{command:process.argv[2]}}))' "$3" "$4")
  out=$(printf '%s' "$json" | node "$GG"); rc=$?
  if [ $rc -ne 0 ]; then bad "$1 (node exit $rc)"; return; fi
  case "$2:$out" in
    deny:*'"deny"'*) ok "$1" ;;
    allow:)          ok "$1" ;;
    *)               bad "$1 — expected $2, got: ${out:-<silent>}" ;;
  esac
}

section "git-destruction-guard"
R=/repo; W=/repo/.claude/worktrees/wt-x
gg "deny  clean --force -d"          deny  "$R" 'git clean --force -d'
gg "deny  clean -fd"                 deny  "$R" 'git clean -fd'
gg "deny  reset --hard"              deny  "$R" 'git reset --hard HEAD'
gg "deny  checkout ."                deny  "$R" 'git checkout .'
gg "deny  checkout <ref> -- path"    deny  "$R" 'git checkout main -- src/a.ts'
gg "deny  checkout -f"               deny  "$R" 'git checkout -f main'
gg "deny  stash drop"                deny  "$R" 'git stash drop'
gg "deny  stash clear"               deny  "$R" 'git stash clear'
gg "deny  restore (worktree)"        deny  "$R" 'git restore a.ts'
gg "deny  restore -W with -S"        deny  "$R" 'git restore -S -W a.ts'
gg "allow clean -fd in worktree"     allow "$W" 'git clean -fd'
gg "allow -C worktree reset --hard"  allow "$R" "git -C $W reset --hard"
gg "allow /tmp scratch"              allow "/tmp/x" 'git reset --hard'
gg "allow restore --staged only"     allow "$R" 'git restore --staged a.ts'
gg "allow status"                    allow "$R" 'git status'
gg "allow log"                       allow "$R" 'git log --oneline -5'
gg "allow destructive-in-a-string"   allow "$R" 'echo "git reset --hard"'
gg "allow non-git"                   allow "$R" 'rm -rf build'

# ---------------------------------------------------------------------------
AG="$DIR/hooks/agent-model-guard.mjs"
FIX="$SCRATCH/agentfix"
mkdir -p "$FIX/.claude/agents"
cp "$DIR"/agents/*.md "$FIX/.claude/agents/" 2>/dev/null

mkfix() { printf -- "---\nname: %s\n%s\n---\nbody\n" "$1" "$2" > "$FIX/.claude/agents/$1.md"; }
mkfix no-effort       "description: x
model: sonnet"
mkfix no-model        "description: x
effort: medium"
mkfix frontier-pinned "description: x
model: fable
effort: high"
mkfix bad-effort      "description: x
model: opus
effort: extreme"
mkfix inherit-model   "description: x
model: inherit
effort: medium"
printf 'no frontmatter at all\n' > "$FIX/.claude/agents/no-frontmatter.md"

ag() { # $1=label $2=expect $3=type $4=model
  local json out
  json=$(node -e '
    const [type,model,fix]=process.argv.slice(1);
    const ti={prompt:"x"};
    if(type) ti.subagent_type=type;
    if(model) ti.model=model;
    process.stdout.write(JSON.stringify({tool_name:"Agent",cwd:fix,tool_input:ti}));
  ' "$3" "$4" "$FIX")
  out=$(printf '%s' "$json" | env -u CLAUDE_PROJECT_DIR HOME="$FIX" node "$AG"); rc=$?
  if [ $rc -ne 0 ]; then bad "$1 (node exit $rc)"; return; fi
  case "$2:$out" in
    deny:*'"deny"'*) ok "$1" ;;
    allow:)          ok "$1" ;;
    *)               bad "$1 — expected $2, got: ${out:-<silent>}" ;;
  esac
}

section "agent-model-guard"
ag "deny  inherit (no type, no model)"  deny  ''    ''
ag "deny  model fable"                  deny  ''    'fable'
ag "deny  model mythos"                 deny  ''    'mythos'
ag "deny  model claude-fable-5"         deny  ''    'claude-fable-5'
ag "deny  model claude-mythos-5"        deny  ''    'claude-mythos-5'
ag "deny  model inherit"                deny  ''    'inherit'
# The two that prove the guard fails CLOSED rather than by enumeration:
ag "deny  unknown alias (gpt-5)"        deny  ''    'gpt-5'
ag "deny  unknown future alias"         deny  ''    'some-future-frontier'
ag "deny  fork + explicit sonnet"       deny  'fork' 'sonnet'
ag "deny  fork alone"                   deny  'fork' ''
# Definition validation — the reason the hook reads the file at all:
ag "deny  definition missing effort:"   deny  'no-effort'       ''
ag "deny  definition missing model:"    deny  'no-model'        ''
ag "deny  definition pins frontier"     deny  'frontier-pinned' ''
ag "deny  definition invalid effort"    deny  'bad-effort'      ''
ag "deny  definition model: inherit"    deny  'inherit-model'   ''
ag "deny  definition has no frontmatter" deny 'no-frontmatter'  ''
for a in scout finder implementor architect verifier documentarian; do
  ag "allow house type $a" allow "$a" ''
done
ag "allow model sonnet"                 allow ''    'sonnet'
ag "allow model opus"                   allow ''    'opus'
ag "allow model haiku"                  allow ''    'haiku'
ag "allow version-pinned claude-opus-5" allow ''    'claude-opus-5'
ag "allow builtin + explicit model"     allow 'general-purpose' 'sonnet'
ag "deny  builtin without model"        deny  'general-purpose' ''

out=$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"ls"}}' | env -u CLAUDE_PROJECT_DIR HOME="$FIX" node "$AG")
[ -z "$out" ] && ok "non-Agent tool ignored" || bad "non-Agent tool: $out"
out=$(printf '%s' 'not json' | env -u CLAUDE_PROJECT_DIR HOME="$FIX" node "$AG")
[ -z "$out" ] && ok "unparseable input fails open" || bad "unparseable: $out"

# ---------------------------------------------------------------------------
section "agent definitions pin both axes"
for f in "$DIR"/agents/*.md; do
  n=$(basename "$f" .md)
  m=$(awk -F': *' '/^model:/{print $2; exit}'  "$f")
  e=$(awk -F': *' '/^effort:/{print $2; exit}' "$f")
  if [ -n "$m" ] && [ -n "$e" ]; then ok "$n pins model=$m effort=$e"
  else bad "$n missing a pin (model='$m' effort='$e')"; fi
done

# ---------------------------------------------------------------------------
# Doctrine propagation. Runs against a COPY of the repo so the temporary edit in
# the propagation test can never touch the real source tree.
section "doctrine propagation (scratch repo + scratch HOME)"
REPO="$SCRATCH/repo"; mkdir -p "$REPO"
cp -R "$DIR"/. "$REPO"/ 2>/dev/null
rm -rf "$REPO/.git" "$REPO/.claude"
RULE_SRC="$REPO/settings/delegation-rule.md"

H1="$SCRATCH/home1"; mkdir -p "$H1"
if CLAUDE_INFRA_SKIP_VERIFY=1 HOME="$H1" bash "$REPO/install.sh" > "$SCRATCH/i1.log" 2>&1; then ok "fresh install exits 0"
else bad "fresh install failed: $(tail -3 "$SCRATCH/i1.log")"; fi
[ -d "$H1/.claude/rules" ] && ok "rules/ created" || bad "rules/ not created"
diff -q "$RULE_SRC" "$H1/.claude/rules/claude-infra-delegation.md" >/dev/null 2>&1 \
  && ok "doctrine matches source" || bad "doctrine differs from source"
[ -f "$H1/.claude/CLAUDE.md" ] && bad "installer created a CLAUDE.md" || ok "CLAUDE.md untouched (absent)"

H2="$SCRATCH/home2"; mkdir -p "$H2/.claude"
cat > "$H2/.claude/CLAUDE.md" <<'LEGACY'
# Global Preferences

## Delegation & session modes

- old doctrine bullet one
- old doctrine bullet two

- Always use uv for Python dependency management
- Use ruff for linting and formatting
LEGACY
before=$(shasum "$H2/.claude/CLAUDE.md" | cut -d' ' -f1)
CLAUDE_INFRA_SKIP_VERIFY=1 HOME="$H2" bash "$REPO/install.sh" > "$SCRATCH/i2.log" 2>&1
after=$(shasum "$H2/.claude/CLAUDE.md" | cut -d' ' -f1)
[ "$before" = "$after" ] && ok "legacy CLAUDE.md byte-identical" || bad "legacy CLAUDE.md was modified"
grep -q "Always use uv" "$H2/.claude/CLAUDE.md" && ok "operator preferences survived" || bad "operator preferences lost"
grep -qi "legacy" "$SCRATCH/i2.log" && ok "legacy warning fired" || bad "legacy warning missing"

CLAUDE_INFRA_SKIP_VERIFY=1 HOME="$H2" bash "$REPO/install.sh" > "$SCRATCH/i3.log" 2>&1
after2=$(shasum "$H2/.claude/CLAUDE.md" | cut -d' ' -f1)
[ "$before" = "$after2" ] && ok "second run still byte-identical" || bad "second run modified CLAUDE.md"

# The regression the rules-file move exists to fix.
printf '\n- SENTINEL BULLET\n' >> "$RULE_SRC"
CLAUDE_INFRA_SKIP_VERIFY=1 HOME="$H2" bash "$REPO/install.sh" > "$SCRATCH/i4.log" 2>&1
grep -q "SENTINEL BULLET" "$H2/.claude/rules/claude-infra-delegation.md" \
  && ok "an edited rule file reaches an installed machine" \
  || bad "edit did NOT propagate — the bug this replaced"

H3="$SCRATCH/home3"; mkdir -p "$H3/.claude"
printf '# Global Preferences\n\n- Always use uv\n' > "$H3/.claude/CLAUDE.md"
CLAUDE_INFRA_SKIP_VERIFY=1 HOME="$H3" bash "$REPO/install.sh" > "$SCRATCH/i5.log" 2>&1
grep -qi "legacy" "$SCRATCH/i5.log" && bad "spurious legacy warning" || ok "no spurious legacy warning"

# ---------------------------------------------------------------------------
section "setup-prompt is generated, not hand-maintained"
if [ -f "$DIR/build-setup-prompt.mjs" ]; then
  if node "$DIR/build-setup-prompt.mjs" --check > "$SCRATCH/gen.log" 2>&1; then
    ok "committed setup-prompt.md matches a fresh generation"
  else
    bad "setup-prompt.md is stale — re-run build-setup-prompt.mjs ($(head -2 "$SCRATCH/gen.log"))"
  fi
else
  bad "build-setup-prompt.mjs missing"
fi

# ---------------------------------------------------------------------------
section "sync-repo (scratch downstream copy)"
if [ -f "$DIR/sync-repo.sh" ]; then
  DOWN="$SCRATCH/downstream"
  mkdir -p "$DOWN/.claude/agents" "$DOWN/.claude/hooks"
  # A downstream whose agent BODIES are customized, as the real one is.
  for f in "$DIR"/agents/*.md; do
    n=$(basename "$f")
    sed 's/^You are/House-customized. You are/' "$f" > "$DOWN/.claude/agents/$n"
  done
  printf '{\n  "hooks": {\n    "UserPromptSubmit": [{"hooks":[{"type":"command","command":"echo vercel-env-pull"}]}]\n  }\n}\n' \
    > "$DOWN/.claude/settings.json"
  bodies_before=$(cat "$DOWN"/.claude/agents/*.md | shasum | cut -d' ' -f1)

  if bash "$DIR/sync-repo.sh" "$DOWN" > "$SCRATCH/sync.log" 2>&1; then ok "sync-repo exits 0"
  else bad "sync-repo failed: $(tail -3 "$SCRATCH/sync.log")"; fi

  bodies_after=$(sed -n '/^---$/,/^---$/!p' /dev/null 2>/dev/null; \
    for f in "$DOWN"/.claude/agents/*.md; do awk 'f{print} /^---$/{c++} c==2 && !f{f=1}' "$f"; done | shasum | cut -d' ' -f1)
  # Compare bodies only (frontmatter is expected to change).
  bodies_src=$(for f in "$DIR"/agents/*.md; do
      n=$(basename "$f"); sed 's/^You are/House-customized. You are/' "$f" \
        | awk 'f{print} /^---$/{c++} c==2 && !f{f=1}'; done | shasum | cut -d' ' -f1)
  [ "$bodies_after" = "$bodies_src" ] && ok "agent bodies byte-identical after sync" \
    || bad "agent bodies were modified by sync"

  miss=0
  for f in "$DOWN"/.claude/agents/*.md; do
    grep -q '^effort:' "$f" || { bad "no effort: patched into $(basename "$f")"; miss=1; }
  done
  [ $miss -eq 0 ] && ok "effort: patched into every downstream agent"

  [ -f "$DOWN/.claude/hooks/git-destruction-guard.mjs" ] && ok "missing hook backfilled" \
    || bad "git-destruction-guard not copied"
  node -e "JSON.parse(require('fs').readFileSync('$DOWN/.claude/settings.json'))" 2>/dev/null \
    && ok "downstream settings.json parses" || bad "downstream settings.json broken"
  grep -q 'vercel-env-pull' "$DOWN/.claude/settings.json" \
    && ok "pre-existing UserPromptSubmit hook preserved" || bad "pre-existing hook clobbered"
  [ -f "$DOWN/.claude/.claude-infra-version" ] && ok "provenance stamp written" \
    || bad "no provenance stamp"

  # A repo that tracks .claude/hooks/ gives every mission worktree its own copy.
  # --scan must count the repo once, and syncing INTO a worktree must be refused.
  mkdir -p "$DOWN/.claude/worktrees/wt-fake/.claude/hooks"
  cp "$DIR/hooks/agent-model-guard.mjs" "$DOWN/.claude/worktrees/wt-fake/.claude/hooks/"
  n=$(bash "$DIR/sync-repo.sh" --scan "$SCRATCH" 2>/dev/null | grep -c 'unstamped\|—' || true)
  hits=$(bash "$DIR/sync-repo.sh" --scan "$SCRATCH" 2>/dev/null | grep -c '/.claude/worktrees/' || true)
  [ "$hits" -eq 0 ] && ok "--scan ignores nested mission worktrees" \
    || bad "--scan counted $hits mission worktree(s) as installs"
  if bash "$DIR/sync-repo.sh" "$DOWN/.claude/worktrees/wt-fake" > "$SCRATCH/wt.log" 2>&1; then
    bad "syncing into a mission worktree was allowed"
  else
    ok "syncing into a mission worktree is refused"
  fi
else
  bad "sync-repo.sh missing"
fi

# ---------------------------------------------------------------------------
printf '\n'
if [ "$fail" -eq 0 ]; then
  echo "verify.sh: ALL CHECKS PASSED"
  exit 0
else
  echo "verify.sh: $fail CHECK(S) FAILED"
  exit 1
fi
