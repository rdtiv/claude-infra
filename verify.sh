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
section "doctrine covers task tracking"
# The system was silent on the task list while mandating "externalize state to a
# tracker" — which reads as a substitute, so missions satisfied the instruction
# via an issue and never opened the task list. These assertions exist so that
# silence cannot quietly return.
#
# orchestrate.md and session-protocol.sh are gone (folded into mission.md), and
# delegation-rule.md deliberately no longer mentions the task list — it moved to
# /mission, which loads on demand. commands/mission.md is the sole surviving home
# for both assertions.
for f in commands/mission.md; do
  if grep -qi 'task list' "$DIR/$f"; then ok "$f mentions the task list"
  else bad "$f no longer mentions the task list"; fi
done
if grep -qi 'not.*substitute\|does not substitute\|separate obligation\|different artifact' \
     "$DIR/commands/mission.md"; then
  ok "doctrine distinguishes task list from externalized state"
else
  bad "doctrine no longer says the task list and externalized state are distinct"
fi

section "deletion is complete (orchestrate.md, session-protocol.sh)"
# commands/orchestrate.md and hooks/session-protocol.sh were deleted upstream;
# their contract folded into commands/mission.md.
#
# Scoped to what actually loads into a session — commands/, hooks/, settings/.
# A stale name in those is an operative bug: doctrine referring a live session to
# something that no longer exists. Two categories are deliberately outside it:
#
#   settings/merge-hook.mjs — IS the retirement mechanism, and must keep the
#     "session-protocol" marker to strip the stale settings.json entry each run.
#   README.md, install.sh   — have to NAME retired artifacts to tell an operator
#     what an update removes. Prose about a deletion is not a dangling reference.
#
# setup-prompt.md is generated and covered by the generation check above.
hit=0
while IFS= read -r -d '' f; do
  # settings/merge-hook.mjs keeps the marker string to strip the settings entry;
  # settings/retired.md IS the manifest and exists to name retired paths.
  case "$f" in
    "$DIR/settings/merge-hook.mjs"|"$DIR/settings/retired.md") continue ;;
  esac
  if grep -qiE 'orchestrate|session-protocol' "$f"; then
    bad "deletion incomplete — $f still mentions orchestrate/session-protocol"
    hit=1
  fi
done < <(find "$DIR/commands" "$DIR/hooks" "$DIR/settings" -type f -print0 2>/dev/null
          # Root-level scripts too: an earlier revision left a dangling /orchestrate
          # in sync-repo.sh's skip message precisely because they were out of scope.
          for s in "$DIR"/*.sh "$DIR"/*.mjs; do [ -f "$s" ] && printf '%s\0' "$s"; done)
[ "$hit" -eq 0 ] && ok "no surviving orchestrate/session-protocol references"

# Deleting a file from hooks/ or commands/ without adding it to the manifest means
# it lives on forever in every installed machine and synced repo — the exact failure
# this branch exists to fix. Catch the omission at the point it is made.
# landed.sh decides whether a worktree is safe to remove. Three prior versions of
# this logic shipped broken, so it gets a real fixture repo rather than inspection:
# a branch that modifies, adds, AND deletes, checked before and after a merge.
section "landed.sh (decommission gate)"
if [ ! -x "$DIR/scripts/landed.sh" ]; then
  bad "landed.sh missing or not executable"
else
  L="$SCRATCH/landed"; mkdir -p "$L"
  (
    cd "$L" || exit 1
    git init -q . && git config user.email t@t && git config user.name t
    printf 'keep\n' > keep.txt; printf 'edit\n' > edit.txt; printf 'doomed\n' > doomed.txt
    git add -A && git commit -qm base
    git branch -q base-ref
    git checkout -qb feature
    printf 'edited\n' > edit.txt      # modify
    printf 'new\n' > added.txt        # add
    rm doomed.txt                     # DELETE — the case that was broken
    git add -A && git commit -qm work
  ) > /dev/null 2>&1

  # Before merging: every touched file should report unlanded.
  (cd "$L" && bash "$DIR/scripts/landed.sh" feature base-ref) > "$SCRATCH/l1.log" 2>&1
  rc=$?
  [ "$rc" -ne 0 ] && ok "landed.sh refuses an unmerged branch (exit $rc)" \
    || bad "landed.sh approved an unmerged branch"
  grep -q 'UNLANDED: doomed.txt' "$SCRATCH/l1.log" \
    && ok "landed.sh sees an unmerged DELETION as unlanded" \
    || bad "landed.sh missed the unmerged deletion"

  # Merge it, then the same call must approve — including the deletion. The old
  # snippet failed exactly here: rev-parse printed its argument for the missing
  # path, so two absent files compared unequal and the deletion never cleared.
  (cd "$L" && git checkout -q base-ref && git merge -q --no-edit feature) > /dev/null 2>&1
  (cd "$L" && bash "$DIR/scripts/landed.sh" feature base-ref) > "$SCRATCH/l2.log" 2>&1
  rc=$?
  [ "$rc" -eq 0 ] && ok "landed.sh approves after the merge" \
    || bad "landed.sh still refuses a fully-merged branch: $(grep UNLANDED "$SCRATCH/l2.log" | head -2)"
  grep -q 'UNLANDED' "$SCRATCH/l2.log" \
    && bad "landed.sh reports a landed file as unlanded (deletion regression)" \
    || ok "a landed deletion compares equal (absent == absent)"

  # Squash-merge shape: content identical, ancestry broken. Ancestry checks fail
  # here; content checks must not.
  (
    cd "$L" && git checkout -qb squash-base base-ref~1 2>/dev/null \
      && git merge -q --squash feature && git commit -qm squashed
  ) > /dev/null 2>&1
  (cd "$L" && bash "$DIR/scripts/landed.sh" feature squash-base) > "$SCRATCH/l3.log" 2>&1
  [ $? -eq 0 ] && ok "landed.sh approves a squash-merged branch (ancestry broken, content equal)" \
    || bad "landed.sh refuses a squash-merged branch — the original false positive"
fi

# Doctrine that references an executable is only as good as the executable being
# there. scripts/ was root-level and outside EVERY install path — install.sh copied
# agents/hooks/commands, sync-repo copied hooks/agents/commands, and landed.sh
# reached neither. mission.md pointed at a file that did not exist downstream.
section "scripts/ reaches both install paths"
if [ ! -d "$DIR/scripts" ]; then
  bad "scripts/ directory missing"
else
  for s in "$DIR"/scripts/*; do
    n=$(basename "$s")
    grep -q "scripts" "$DIR/install.sh" && ok "install.sh copies scripts/ (for $n)" \
      || bad "install.sh does not copy scripts/ — $n never reaches ~/.claude"
    # sync-repo's half is asserted behaviorally in the sync-repo section below,
    # by running it against a scratch downstream — a grep here would pass on a
    # rename that broke the copy.
    break   # one representative file is enough; the copy is per-directory
  done
  # Every scripts/ path mission.md tells you to run must actually ship. Scoped to
  # `scripts/<name>` references — a passing mention of another file (verify.sh,
  # say) is prose, not an invocation of something that has to travel.
  refs=$(grep -oE 'scripts/[A-Za-z0-9_.-]+\.sh' "$DIR/commands/mission.md" | sort -u)
  if [ -z "$refs" ]; then
    bad "mission.md no longer references any scripts/ path — the gate is undocumented"
  else
    while IFS= read -r ref; do
      [ -f "$DIR/$ref" ] \
        && ok "mission.md references $ref, which ships" \
        || bad "mission.md references $ref but it does not exist"
    done <<< "$refs"
  fi
  # And the downstream .gitignore advice has to cover it, or the synced copy is
  # written and never tracked — the same defect as the provenance stamp.
  grep -q "'!.claude/scripts/'" "$DIR/sync-repo.sh" \
    && ok ".gitignore check requires the scripts/ whitelist" \
    || bad ".gitignore check omits scripts/ — synced scripts would stay untracked"
fi

section "workflows/ reaches both install paths"
if [ ! -d "$DIR/workflows" ]; then
  bad "workflows/ directory missing"
else
  ok "workflows/ directory exists"
  grep -q "workflows" "$DIR/install.sh" && ok "install.sh references workflows/" \
    || bad "install.sh does not reference workflows/ — workflow files never reach ~/.claude"
  grep -q "'!.claude/workflows/'" "$DIR/sync-repo.sh" \
    && ok ".gitignore check requires the workflows/ whitelist" \
    || bad ".gitignore check omits workflows/ — synced workflows would stay untracked"

  # node --check rejects this file: workflow scripts legally use top-level
  # `return` and top-level `await`, both of which plain module/script parsing
  # rejects. Instead, wrap the body (after the `meta` export) in an async
  # function and let the Function constructor parse it — that accepts both
  # top-level return and top-level await, which is what the harness actually does.
  if node -e '
const fs=require("fs");
const raw=fs.readFileSync(process.argv[1],"utf8");
const stripped=raw.replace(/^\s*(\/\/[^\n]*\n|\/\*[\s\S]*?\*\/\s*)*/,"");
if(!/^export\s+const\s+meta\s*=/.test(stripped)){console.error("meta is not the first statement");process.exit(1)}
const body=raw.replace(/^(\s*(?:\/\/[^\n]*\n|\/\*[\s\S]*?\*\/\s*)*)export\s+const\s+meta/,"$1const meta");
try{ new Function("args","budget","agent","parallel","pipeline","phase","log","workflow","return (async()=>{"+body+"})()"); }
catch(e){ console.error(e.message); process.exit(1) }
' "$DIR/workflows/code-review-pinned.js" > "$SCRATCH/wf.log" 2>&1; then
    ok "code-review-pinned.js parses (meta-first, async-wrapped body)"
  else
    bad "code-review-pinned.js failed to parse — $(cat "$SCRATCH/wf.log")"
  fi

  # Every shipped workflow must carry the ownership marker on line 1, or the
  # sync/install guard above would refuse to update its own file on the next
  # run — a silent freeze on whatever revision happened to ship first.
  for f in "$DIR"/workflows/*.js; do
    [ -f "$f" ] || continue
    n=$(basename "$f")
    head -n 1 "$f" | grep -q "claude-infra-owned" \
      && ok "$n carries the claude-infra-owned marker on line 1" \
      || bad "$n missing the claude-infra-owned marker on line 1 — sync/install would never update it"
  done

  # Regression guard: naming this workflow "code-review" would shadow the
  # vendor's built-in workflow of the same name, which we deliberately keep
  # reachable (see commands/review-pinned.md). It must be named
  # "code-review-pinned" instead.
  if grep -q 'name: "code-review"' "$DIR/workflows/code-review-pinned.js"; then
    bad "code-review-pinned.js sets name: \"code-review\" — this shadows the vendor workflow"
  else
    ok "code-review-pinned.js does not shadow the vendor's code-review workflow"
  fi
  grep -q 'name: "code-review-pinned"' "$DIR/workflows/code-review-pinned.js" \
    && ok "code-review-pinned.js declares meta.name = code-review-pinned" \
    || bad "code-review-pinned.js does not declare meta.name = code-review-pinned"

  # commands/review-pinned.md must name a workflow that actually ships. Another
  # session is authoring that command file in parallel; if it hasn't landed yet
  # this just fails like any other assertion until it does.
  cmd="$DIR/commands/review-pinned.md"
  if [ ! -f "$cmd" ]; then
    bad "commands/review-pinned.md missing — cannot verify it names a shipped workflow"
  else
    wfname=$(grep -oE 'name:[[:space:]]*"[A-Za-z0-9_-]+"' "$cmd" | head -1 | sed -E 's/name:[[:space:]]*"([^"]+)"/\1/')
    if [ -z "$wfname" ]; then
      bad "commands/review-pinned.md does not name a workflow"
    elif [ -f "$DIR/workflows/$wfname.js" ]; then
      ok "commands/review-pinned.md names workflow '$wfname', which ships as workflows/$wfname.js"
    else
      bad "commands/review-pinned.md names workflow '$wfname', but workflows/$wfname.js does not exist"
    fi
  fi
fi

section "retirement manifest covers what this branch deleted"
mf="$DIR/settings/retired.md"
if [ ! -f "$mf" ]; then
  bad "settings/retired.md is missing"
else
  # Widened from (hooks|commands) to also cover scripts/ and workflows/. This
  # also closes a pre-existing gap: scripts/ retirement already runs in
  # sync-repo.sh (retire_from "scripts") but this cross-check never covered it.
  gone=$(git -C "$DIR" diff --name-only --diff-filter=D origin/main...HEAD 2>/dev/null \
         | grep -E '^(hooks|commands|scripts|workflows)/' || true)
  miss=0
  for p in $gone; do
    grep -qxF "$p" "$mf" || { bad "$p deleted but absent from settings/retired.md"; miss=1; }
  done
  [ "$miss" -eq 0 ] && ok "every deleted hook/command is listed in the manifest"
  # A stale entry is the other direction: still listed, but back in the repo.
  stale=0
  while IFS= read -r rel; do
    case "$rel" in ""|"<!--"*|*"-->"|" "*) continue ;; esac
    [ -e "$DIR/$rel" ] && { bad "settings/retired.md lists $rel, which still exists"; stale=1; }
  done < "$mf"
  [ "$stale" -eq 0 ] && ok "no stale manifest entries"
fi

section "tier-conditional delegation (mission.md)"
if grep -q 'Delegation, on Opus' "$DIR/commands/mission.md" \
   && grep -q 'Delegation, on Fable' "$DIR/commands/mission.md"; then
  ok "commands/mission.md has both an Opus and a Fable delegation block"
  opus_block=$(sed -n '/Delegation, on Opus/,/Delegation, on Fable/p' "$DIR/commands/mission.md")
  fable_block=$(sed -n '/Delegation, on Fable/,/^4\./p' "$DIR/commands/mission.md")
  # Flatten to single lines first — the prose wraps mid-phrase (e.g. "spawn\n
  # counts low"), which a line-oriented grep against the raw block would miss.
  opus_flat=$(printf '%s' "$opus_block" | tr '\n' ' ')
  fable_flat=$(printf '%s' "$fable_block" | tr '\n' ' ')
  if [ "$opus_block" != "$fable_block" ] \
     && printf '%s' "$opus_flat" | grep -qiE 'spawn[[:space:]]+count' \
     && ! printf '%s' "$fable_flat" | grep -qiE 'spawn[[:space:]]+count'; then
    ok "Opus and Fable delegation blocks differ on spawn counts"
  else
    bad "Opus and Fable delegation blocks no longer differ on spawn counts"
  fi
else
  bad "commands/mission.md missing an Opus and/or Fable delegation block"
fi

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
section "merge-hook remove() (scratch settings.json)"
MHDIR="$SCRATCH/mergehook"; mkdir -p "$MHDIR"
MHSET="$MHDIR/settings.json"
cat > "$MHSET" <<'JSON'
{
  "hooks": {
    "PreToolUse": [
      {"matcher": "Agent", "hooks": [{"type": "command", "command": "node \"$HOME/.claude/hooks/agent-model-guard.mjs\""}]}
    ],
    "SessionStart": [
      {"hooks": [{"type": "command", "command": "bash \"$HOME/.claude/hooks/session-protocol.sh\""}]}
    ],
    "UserPromptSubmit": [
      {"hooks": [{"type": "command", "command": "echo unrelated"}]}
    ]
  }
}
JSON
node "$DIR/settings/merge-hook.mjs" --target "$MHSET" --prefix '$HOME' > "$SCRATCH/mh1.log" 2>&1
grep -q 'session-protocol' "$MHSET" && bad "session-protocol entry survived merge-hook remove()" \
  || ok "session-protocol entry removed by merge-hook"
grep -q '"SessionStart"' "$MHSET" && bad "empty SessionStart key left behind" \
  || ok "empty SessionStart key removed"
grep -q 'agent-model-guard' "$MHSET" && ok "agent-model-guard present after remove()" \
  || bad "agent-model-guard missing after remove()"
grep -q 'git-destruction-guard' "$MHSET" && ok "git-destruction-guard present after remove()" \
  || bad "git-destruction-guard missing after remove()"
grep -q 'echo unrelated' "$MHSET" && ok "unrelated UserPromptSubmit entry survived remove()" \
  || bad "unrelated entry was removed by remove()"
node -e "JSON.parse(require('fs').readFileSync('$MHSET'))" 2>/dev/null \
  && ok "settings.json still parses after remove()" || bad "settings.json broken after remove()"
node "$DIR/settings/merge-hook.mjs" --target "$MHSET" --prefix '$HOME' > "$SCRATCH/mh2.log" 2>&1
grep -qi 'removed' "$SCRATCH/mh2.log" && bad "second merge-hook run reported further removal" \
  || ok "second merge-hook run reports no further removal"

# ---------------------------------------------------------------------------
section "install.sh migrates the old layout (scratch HOME)"
H4="$SCRATCH/home4"; mkdir -p "$H4/.claude/hooks"
cp "$DIR/hooks/agent-model-guard.mjs" "$H4/.claude/hooks/" 2>/dev/null
printf '#!/usr/bin/env bash\necho legacy-banner\n' > "$H4/.claude/hooks/session-protocol.sh"
cat > "$H4/.claude/settings.json" <<'JSON'
{
  "hooks": {
    "SessionStart": [
      {"hooks": [{"type": "command", "command": "bash \"$HOME/.claude/hooks/session-protocol.sh\""}]}
    ]
  }
}
JSON
CLAUDE_INFRA_SKIP_VERIFY=1 HOME="$H4" bash "$DIR/install.sh" > "$SCRATCH/i6.log" 2>&1
[ -f "$H4/.claude/hooks/session-protocol.sh" ] && bad "install.sh left session-protocol.sh in place" \
  || ok "install.sh removed retired session-protocol.sh"
grep -q 'session-protocol' "$H4/.claude/settings.json" && bad "settings.json still references session-protocol after install.sh" \
  || ok "install.sh stripped session-protocol from settings.json"

# ---------------------------------------------------------------------------
# install.sh has its OWN copy of the workflows ownership guard, on the user-scope
# path. The sync-repo section below covers the repo-scope half; without this, a
# regression in one path would hide behind the other passing.
section "install.sh does not clobber an operator's own workflow (scratch HOME)"
H5="$SCRATCH/home5"; mkdir -p "$H5"
CLAUDE_INFRA_SKIP_VERIFY=1 HOME="$H5" bash "$DIR/install.sh" > "$SCRATCH/i7.log" 2>&1
[ -f "$H5/.claude/workflows/code-review-pinned.js" ] \
  && ok "install.sh delivered workflows/code-review-pinned.js to ~/.claude" \
  || bad "install.sh did not deliver the workflow to ~/.claude"
# An operator's hand-written file at the same path carries no marker.
printf '// hand-written by the operator, not ours\nexports.meta={name:"mine"}\n' \
  > "$H5/.claude/workflows/code-review-pinned.js"
cp "$H5/.claude/workflows/code-review-pinned.js" "$SCRATCH/home5-seed.js"
CLAUDE_INFRA_SKIP_VERIFY=1 HOME="$H5" bash "$DIR/install.sh" > "$SCRATCH/i8.log" 2>&1
cmp -s "$SCRATCH/home5-seed.js" "$H5/.claude/workflows/code-review-pinned.js" \
  && ok "install.sh left an unmarked same-named workflow untouched" \
  || bad "install.sh overwrote an operator-owned workflow merely because the name collided"
grep -q 'not claude-infra-owned' "$SCRATCH/i8.log" \
  && ok "install.sh warns about the unmarked collision" \
  || bad "install.sh overwrote or skipped silently — no collision warning"
# The other direction: a marked file must still be refreshed, or ours freezes.
cp "$DIR/workflows/code-review-pinned.js" "$H5/.claude/workflows/code-review-pinned.js"
printf '\n// stale tail\n' >> "$H5/.claude/workflows/code-review-pinned.js"
CLAUDE_INFRA_SKIP_VERIFY=1 HOME="$H5" bash "$DIR/install.sh" > "$SCRATCH/i9.log" 2>&1
cmp -s "$DIR/workflows/code-review-pinned.js" "$H5/.claude/workflows/code-review-pinned.js" \
  && ok "install.sh refreshed a stale marked workflow" \
  || bad "install.sh left a marked (claude-infra-owned) workflow stale"

# ---------------------------------------------------------------------------
section "sync-repo (scratch downstream copy)"
if [ -f "$DIR/sync-repo.sh" ]; then
  DOWN="$SCRATCH/downstream"
  mkdir -p "$DOWN/.claude/agents" "$DOWN/.claude/hooks" "$DOWN/.claude/commands"
  # A downstream whose agent BODIES are customized, as the real one is.
  for f in "$DIR"/agents/*.md; do
    n=$(basename "$f")
    sed 's/^You are/House-customized. You are/' "$f" > "$DOWN/.claude/agents/$n"
  done
  printf '{\n  "hooks": {\n    "UserPromptSubmit": [{"hooks":[{"type":"command","command":"echo vercel-env-pull"}]}]\n  }\n}\n' \
    > "$DOWN/.claude/settings.json"
  # Retirement candidates: named in settings/retired.md.
  printf '# orchestrate (retired)\n' > "$DOWN/.claude/commands/orchestrate.md"
  printf '#!/usr/bin/env bash\necho legacy-banner\n' > "$DOWN/.claude/hooks/session-protocol.sh"
  # Repo-OWNED artifacts claude-infra knows nothing about. These must SURVIVE.
  # An earlier revision retired anything without an upstream counterpart, which
  # deleted exactly these — unrecoverable where .claude/ is gitignored.
  printf '#!/usr/bin/env bash\necho repo-owned\n' > "$DOWN/.claude/hooks/vercel-env-pull.sh"
  printf 'repo-owned slash command\n' > "$DOWN/.claude/commands/deploy.md"
  mkdir -p "$DOWN/.claude/hooks/lib"   # a subdir must not abort the run
  printf 'shared\n' > "$DOWN/.claude/hooks/lib/shared.sh"
  # Workflows collision fixtures. workflows/ is SHARED GROUND — a repo may
  # already have its own unrelated workflow AND may happen to have one with the
  # same filename as ours. Neither is ours to overwrite without the marker.
  mkdir -p "$DOWN/.claude/workflows"
  printf 'exports.meta = { name: "custom" };\n// a repo-owned workflow, no counterpart upstream\n' \
    > "$DOWN/.claude/workflows/custom.js"
  printf '// this is a downstream-owned file that happens to share our filename\nexports.meta = { name: "not-ours" };\n' \
    > "$DOWN/.claude/workflows/code-review-pinned.js"
  cp "$DOWN/.claude/workflows/custom.js" "$SCRATCH/custom-seed.js"
  cp "$DOWN/.claude/workflows/code-review-pinned.js" "$SCRATCH/collision-seed.js"
  bodies_before=$(cat "$DOWN"/.claude/agents/*.md | shasum | cut -d' ' -f1)

  # --dry-run must retire nothing: recursive checksum identical before and after.
  DOWN_SUM_BEFORE=$(find "$DOWN" -type f -exec shasum {} \; | sort | shasum | cut -d' ' -f1)
  bash "$DIR/sync-repo.sh" "$DOWN" --dry-run > "$SCRATCH/sync-dry.log" 2>&1
  DOWN_SUM_AFTER=$(find "$DOWN" -type f -exec shasum {} \; | sort | shasum | cut -d' ' -f1)
  [ "$DOWN_SUM_BEFORE" = "$DOWN_SUM_AFTER" ] && ok "--dry-run retires nothing (checksum unchanged)" \
    || bad "--dry-run modified/removed files in the downstream tree"
  grep -qi 'retired' "$SCRATCH/sync-dry.log" && ok "--dry-run reports the retirements it would make" \
    || bad "--dry-run did not report retirements"

  if bash "$DIR/sync-repo.sh" "$DOWN" > "$SCRATCH/sync.log" 2>&1; then ok "sync-repo exits 0"
  else bad "sync-repo failed: $(tail -3 "$SCRATCH/sync.log")"; fi

  [ -f "$DOWN/.claude/commands/orchestrate.md" ] && bad "orchestrate.md not retired by sync-repo" \
    || ok "sync-repo retired commands/orchestrate.md"
  [ -f "$DOWN/.claude/hooks/session-protocol.sh" ] && bad "hooks/session-protocol.sh not retired by sync-repo" \
    || ok "sync-repo retired hooks/session-protocol.sh"

  # The other half, and the more expensive one to get wrong.
  [ -f "$DOWN/.claude/hooks/vercel-env-pull.sh" ] \
    && ok "repo-owned hook survived the sync" \
    || bad "sync-repo DELETED a repo-owned hook — retirement must be manifest-driven"
  [ -f "$DOWN/.claude/commands/deploy.md" ] \
    && ok "repo-owned slash command survived the sync" \
    || bad "sync-repo DELETED a repo-owned command — retirement must be manifest-driven"
  [ -f "$DOWN/.claude/hooks/lib/shared.sh" ] \
    && ok "subdirectory under hooks/ survived and did not abort the run" \
    || bad "a subdirectory under hooks/ was removed or aborted the sync"

  # workflows/ collision handling — the important one. A source-driven copy
  # loop must never touch a downstream file it doesn't own, even when the
  # filename happens to match.
  cmp -s "$SCRATCH/custom-seed.js" "$DOWN/.claude/workflows/custom.js" \
    && ok "custom.js (no upstream counterpart) is untouched by sync" \
    || bad "custom.js was modified by sync — the copy loop touched a file it doesn't own"
  cmp -s "$SCRATCH/collision-seed.js" "$DOWN/.claude/workflows/code-review-pinned.js" \
    && ok "unmarked code-review-pinned.js (name collision) was NOT overwritten" \
    || bad "sync-repo overwrote a downstream-owned file merely because the filename collided"
  # Match the refusal text, not just the filename — the filename also appears on a
  # routine "created"/"updated" line, so grepping for it alone would pass even if
  # the guard never fired and the file had simply been overwritten.
  grep -q 'NOT claude-infra-owned' "$SCRATCH/sync.log" \
    && ok "sync warns that the colliding workflow is not claude-infra-owned" \
    || bad "sync did not warn about the unmarked code-review-pinned.js collision"

  # The other direction: a MARKED file (claude-infra-owned) must still be
  # updated. A guard that never writes is as broken as one that always writes.
  printf 'claude-infra-owned — installed by claude-infra\nexports.meta = { name: "stale-marked-version" };\n' \
    > "$DOWN/.claude/workflows/code-review-pinned.js"
  bash "$DIR/sync-repo.sh" "$DOWN" > "$SCRATCH/sync2.log" 2>&1
  cmp -s "$DIR/workflows/code-review-pinned.js" "$DOWN/.claude/workflows/code-review-pinned.js" \
    && ok "marked code-review-pinned.js WAS overwritten with the claude-infra version" \
    || bad "sync-repo left a marked (claude-infra-owned) workflow file stale"
  # The sync must have run to completion, not died partway on the subdir.
  [ -f "$DOWN/.claude/.claude-infra-version" ] \
    && ok "sync ran to completion (provenance stamp written)" \
    || bad "sync aborted before the provenance stamp — later steps never ran"
  grep -q 'session-protocol' "$DOWN/.claude/settings.json" && bad "downstream settings.json still references session-protocol" \
    || ok "sync-repo stripped session-protocol from downstream settings.json"
  grep -q 'vercel-env-pull' "$DOWN/.claude/settings.json" && ok "unrelated UserPromptSubmit hook survived sync retirement" \
    || bad "unrelated hook lost during sync retirement"

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

  # The executables the doctrine tells a session to run must travel with it. A
  # cloud session in a synced repo has no claude-infra checkout to fall back on.
  if [ -x "$DOWN/.claude/scripts/landed.sh" ]; then
    ok "sync-repo delivered scripts/landed.sh, executable"
  else
    bad "scripts/landed.sh did not reach the downstream repo — mission.md would dangle"
  fi

  # A repo that tracks .claude/hooks/ gives every mission worktree its own copy.
  # --scan must count the repo once, and syncing INTO a worktree must be refused.
  mkdir -p "$DOWN/.claude/worktrees/wt-fake/.claude/hooks"
  cp "$DIR/hooks/agent-model-guard.mjs" "$DOWN/.claude/worktrees/wt-fake/.claude/hooks/"
  n=$(bash "$DIR/sync-repo.sh" --scan "$SCRATCH" 2>/dev/null | grep -c 'unstamped\|—' || true)
  hits=$(bash "$DIR/sync-repo.sh" --scan "$SCRATCH" 2>/dev/null | grep -c '/.claude/worktrees/' || true)
  [ "$hits" -eq 0 ] && ok "--scan ignores nested mission worktrees" \
    || bad "--scan counted $hits mission worktree(s) as installs"
  if bash "$DIR/sync-repo.sh" "$DOWN/.claude/worktrees/wt-fake" > "$SCRATCH/wt.log" 2>&1; then
    bad "syncing into a worktree was allowed without --allow-worktree"
  else
    ok "syncing into a worktree is refused by default"
  fi
  # ...but permitted deliberately, which is the recommended flow — syncing the
  # main checkout would mean committing from the integration ground.
  if bash "$DIR/sync-repo.sh" "$DOWN/.claude/worktrees/wt-fake" --allow-worktree \
       > "$SCRATCH/wtok.log" 2>&1; then
    ok "--allow-worktree permits a deliberate sync worktree"
  else
    bad "--allow-worktree still refused: $(tail -2 "$SCRATCH/wtok.log")"
  fi

  # The provenance stamp must be in the .gitignore whitelist the tool checks for,
  # or it is written and never tracked.
  printf '.claude/*\n!.claude/agents/\n!.claude/hooks/\n!.claude/commands/\n' > "$DOWN/.gitignore"
  bash "$DIR/sync-repo.sh" "$DOWN" --dry-run > "$SCRATCH/gi.log" 2>&1
  grep -q 'claude-infra-version' "$SCRATCH/gi.log" \
    && ok ".gitignore check flags the missing provenance-stamp whitelist" \
    || bad ".gitignore check ignores the provenance stamp (it would go untracked)"
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
