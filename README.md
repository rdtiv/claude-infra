# claude-infra

A portable Claude Code environment: the two-tier delegation policy
(orchestrator designs, pinned cheaper workers execute), mechanically enforced,
plus the mission/worktree lifecycle. Canonical source of truth — machines and
repos install *from here*; edits happen *here first*.

Origin: analysis of a five-day multi-agent sprint found roughly a third of
subagent turns running on the frontier model by silent inheritance — the
Agent tool's `model` param is optional and prose doctrine wasn't
mechanically enforced.

## Install on a machine

```sh
git clone https://github.com/rdtiv/claude-infra.git && cd claude-infra
./install.sh          # idempotent; re-run after every pull
```

Then restart Claude Code sessions (agents/commands/hooks load at session
start). No git on the machine? Paste `setup-prompt.md` into a Claude Code
session and say "execute this".

## What's installed

| Path | What |
|---|---|
| `~/.claude/agents/` | Six pinned roles: `scout`/`finder`/`implementor` (sonnet), `architect`/`verifier`/`documentarian` (opus) |
| `~/.claude/hooks/agent-model-guard.mjs` | PreToolUse guard: denies Agent spawns that would inherit the session model or that name Fable |
| `~/.claude/hooks/git-destruction-guard.mjs` | PreToolUse guard: denies working-tree-destroying git (`reset --hard`, `clean -f`, `checkout .`, `restore`, `stash drop`) outside `.claude/worktrees/` and scratch paths — the main checkout may hold another session's uncommitted work |
| `~/.claude/hooks/session-protocol.sh` | SessionStart hook: injects the standing ritual so every session opens by surfacing the protocol (model tier → /mission → /orchestrate) |
| `~/.claude/commands/orchestrate.md` | `/orchestrate <goal>` — session contract: spec first, delegate to pinned workers, verify adversarially |
| `~/.claude/commands/mission.md` | `/mission <issue#>` / `/mission end` — worktree lifecycle: provision fresh from origin; at end, a `documentarian` docs gate precedes decommission; migrations ship to prod before the code that needs them; main checkout = integration ground only |
| `~/.claude/settings.json` | Hook wiring (merged, never clobbered) |
| `~/.claude/CLAUDE.md` | "Delegation & session modes" doctrine (appended once) |

## Session-start language

1. `/model fable` (ambiguous / novel / multi-stream) or `/model opus`
   (well-specified / single-stream) — the orchestrator tier.
2. `/mission <issue#>` for a new unit of work; `/orchestrate <goal>` for the
   build contract inside it. Plain prompting for conversational/small work.

## Repo-level install (for repos with cloud sessions)

Cloud sessions don't see `~/.claude`, so repos that run them need their own
copy: `.claude/agents/` + `.claude/hooks/` + the PreToolUse block in the
repo's `.claude/settings.json` (command:
`node "${CLAUDE_PROJECT_DIR:-$PWD}/.claude/hooks/agent-model-guard.mjs"`),
whitelisted in `.gitignore` if `.claude/*` is ignored, landed as a PR.
Repo-specific conventions (lint commands, review doctrine, port rules) may be
folded into the repo-level copies of the agent bodies and the mission command.

## Expected behavior / non-bugs

- Built-in agent types (Explore, Plan, general-purpose) and plugin agents get
  **denied until the orchestrator passes `model:` explicitly** — intentional
  friction, one corrective round-trip.
- `subagent_type: fork` is **denied unconditionally**: the Agent tool ignores
  `model` for forks, so a fork always runs on the session model. Passing
  `model:` on a fork looks compliant and isn't — hence the hard deny.
- In repos with the repo-level hook, both hooks fire; duplicate denies are
  harmless.
- Workflow-internal `agent()` calls bypass PreToolUse — pin models inside
  workflow scripts in the workflow script itself.
- The hook fails open on unparseable input and only evaluates the Agent tool.

## Updating

Edit here → commit → on each machine: `git pull && ./install.sh`. For repos
carrying the repo-level copy, port the change over in a PR.
