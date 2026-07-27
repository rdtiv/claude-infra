# Claude Code delegation infrastructure — machine setup prompt

> **Canonical source is the `claude-infra` repo** (your claude-infra clone):
> `git clone` + `./install.sh` is the preferred install. This file is the
> no-git fallback — paste it into a Claude Code session on the target machine
> and say *"execute this"*. Everything needed is inline. Safe to re-run;
> every step is idempotent. Note: the repo also carries
> `commands/mission.md` (worktree lifecycle), `commands/review-pinned.md` and
> `workflows/code-review-pinned.js` (the local review gate) — if installing
> from this file, copy those from the repo when you can. Without them the
> `refuter` and `reproducer` agents below install correctly but nothing
> invokes them: they exist only to serve that workflow.

**What it installs:** a two-tier delegation policy. The main session
(Fable or Opus, chosen at session start via `/model`) designs, specs, and
judges; subagents execute on pinned cheaper models at pinned effort and
**never inherit either from the session**. Enforced three ways: named agent
types with model AND effort pinned in frontmatter, a `PreToolUse` hook that
reads the spawned agent's own definition file and denies inheriting,
frontier-tier, unrecognized-tier, and fork spawns, and a `/mission`
command that carries the execution contract.

Origin: analysis of a five-day multi-agent sprint found roughly a third of
subagent turns running on the frontier model by silent inheritance — the
Agent tool's `model` param is optional and prose doctrine wasn't
mechanically enforced.

---

## Instructions to the executing Claude session

1. Create `~/.claude/agents/`, `~/.claude/hooks/`, `~/.claude/commands/`,
   `~/.claude/rules/` if missing.
2. Write each file in **Part 1** below verbatim to its stated path. If a file
   already exists, overwrite it (these are the canonical versions).
3. **Merge** — do not overwrite — the settings fragment in **Part 2** into
   `~/.claude/settings.json`: read the existing file, add the `PreToolUse`
   entries to its `hooks` object (create `hooks` if absent, append to an
   existing `PreToolUse` array rather than replacing it), and re-validate that
   the result parses as JSON.
4. **Write** the section in **Part 3** to
   `~/.claude/rules/claude-infra-delegation.md`, overwriting it wholesale if
   it already exists — `~/.claude/rules/*.md` is auto-loaded by Claude Code
   at user scope, so this file needs no entry in `CLAUDE.md`. This file is
   OWNED by claude-infra: always overwrite it completely, and never write the
   doctrine into `~/.claude/CLAUDE.md`. If an existing `~/.claude/CLAUDE.md`
   still has a legacy `## Delegation & session modes` section from an older
   install, that section is now a stale second copy — point it out and leave
   it for the operator to delete by hand. Do not attempt to delete or edit it
   yourself: that section has no reliable end boundary (nothing marks where
   it stops before the operator's own following content begins), so an
   automated removal risks eating unrelated text.
5. Run the verification in **Part 4** and report the results.
6. If the machine lacks `node` on PATH in non-interactive shells (the hook
   needs it), say so — the fix is machine-specific (nvm default alias, or
   swap the hook command to an absolute node path).

**Repo-level install (optional, per repository):** for repos that also run
cloud sessions (where `~/.claude` doesn't exist), copy the same eight agent
files + the hooks into the repo's `.claude/agents/` and `.claude/hooks/`, add
the same `PreToolUse` blocks to the repo's `.claude/settings.json`, whitelist
`.claude/agents/` and `.claude/hooks/` in `.gitignore` if `.claude/*` is
ignored, and land it as a PR. Repo-specific conventions (lint commands, house
review doctrine, port rules) may be folded into the repo-level copies of the
agent bodies.

---

## Part 1 — files (verbatim)

### `~/.claude/agents/implementor.md`

```markdown
<!-- include:agents/implementor.md -->
```

### `~/.claude/agents/finder.md`

```markdown
<!-- include:agents/finder.md -->
```

### `~/.claude/agents/verifier.md`

```markdown
<!-- include:agents/verifier.md -->
```

### `~/.claude/agents/scout.md`

```markdown
<!-- include:agents/scout.md -->
```

### `~/.claude/agents/refuter.md`

```markdown
<!-- include:agents/refuter.md -->
```

### `~/.claude/agents/reproducer.md`

```markdown
<!-- include:agents/reproducer.md -->
```

### `~/.claude/agents/architect.md`

```markdown
<!-- include:agents/architect.md -->
```

### `~/.claude/agents/documentarian.md`

```markdown
<!-- include:agents/documentarian.md -->
```

### `~/.claude/hooks/agent-model-guard.mjs`

```javascript
<!-- include:hooks/agent-model-guard.mjs -->
```

### `~/.claude/hooks/git-destruction-guard.mjs`

```javascript
<!-- include:hooks/git-destruction-guard.mjs -->
```

## Part 2 — settings fragment (MERGE into `~/.claude/settings.json`)

Add these entries to the `hooks` object (create `hooks` if it doesn't exist;
append to an existing `PreToolUse` array):

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Agent",
        "hooks": [
          {
            "type": "command",
            "command": "node \"$HOME/.claude/hooks/agent-model-guard.mjs\""
          }
        ]
      },
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "node \"$HOME/.claude/hooks/git-destruction-guard.mjs\""
          }
        ]
      }
    ]
  }
}
```

For a **repo-level** install, the commands use the project path instead:
`node "${CLAUDE_PROJECT_DIR:-$PWD}/.claude/hooks/agent-model-guard.mjs"` and
`node "${CLAUDE_PROJECT_DIR:-$PWD}/.claude/hooks/git-destruction-guard.mjs"`.

## Part 3 — doctrine (write to `~/.claude/rules/claude-infra-delegation.md`)

```markdown
<!-- include:settings/delegation-rule.md -->
```

## Part 4 — verification

Run all four; expected results as noted:

```sh
node --check ~/.claude/hooks/agent-model-guard.mjs   # → no output (clean)

# inherit-spawn → JSON with permissionDecision "deny"
echo '{"tool_name":"Agent","tool_input":{"prompt":"x"}}' \
  | node ~/.claude/hooks/agent-model-guard.mjs

# fable spawn → deny; pinned type and explicit model → no output (allow)
echo '{"tool_name":"Agent","tool_input":{"prompt":"x","model":"fable"}}' \
  | node ~/.claude/hooks/agent-model-guard.mjs
echo '{"tool_name":"Agent","tool_input":{"prompt":"x","subagent_type":"finder"}}' \
  | node ~/.claude/hooks/agent-model-guard.mjs
echo '{"tool_name":"Agent","tool_input":{"prompt":"x","model":"sonnet"}}' \
  | node ~/.claude/hooks/agent-model-guard.mjs

# fork spawn → deny even WITH an explicit model (the Agent tool ignores
# model: for forks, so a fork always inherits the session model)
echo '{"tool_name":"Agent","tool_input":{"prompt":"x","subagent_type":"fork","model":"sonnet"}}' \
  | node ~/.claude/hooks/agent-model-guard.mjs

# settings still valid JSON
node -e "JSON.parse(require('fs').readFileSync(process.env.HOME+'/.claude/settings.json'));console.log('VALID')"
```

Then restart the Claude Code session (agent types and hooks load at session
start) and confirm the new types appear when spawning agents.

## Notes & expected behavior

- **Both layers may fire** in a repo that also has the repo-level hook — duplicate denies are harmless.
- **Intentional friction:** built-in types (Explore, Plan, general-purpose)
  and plugin agents will be denied until the orchestrator passes `model:`
  explicitly — one corrective round-trip, by design.
- **Forks are denied unconditionally:** the Agent tool ignores `model` for
  `subagent_type: fork`, so a fork always runs on the session model. Passing
  `model:` on a fork looks compliant but has no effect — hence the hard deny.
- The hook **fails open** on unparseable input and only evaluates
  `tool_name === "Agent"`; Workflow-internal `agent()` calls don't pass
  through PreToolUse. Inside a workflow script, pin with `agentType:` —
  **not** `model:`. Measured: `agentType: "finder"` resolves to sonnet at
  `effort=medium` per its definition, while `model: "sonnet"` alone still
  runs at the session's effort, so a bare `model:` pin leaks the axis no
  hook can observe.
- Session-start language: `/model fable` (you are in the loop clarifying unknowns)
  or `/model opus` (decomposable, runs unattended), then `/mission <issue# | pr# |
  description>` for anything warranting a branch and a PR.
