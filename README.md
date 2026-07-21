# claude-infra

Dan's portable Claude Code environment: the two-tier delegation policy
(orchestrator designs, pinned cheaper workers execute), mechanically enforced,
plus the mission/worktree lifecycle. Canonical source of truth — machines and
repos install *from here*; edits happen *here first*.

Origin: the Jul 2026 sartora sprint analysis — ~1/3 of subagent turns ran on
Fable by inheritance because the Agent tool's `model` param is optional and
prose doctrine wasn't mechanically enforced. Reference repo-level
implementation: sartora PR #222.

## Install on a machine

```sh
git clone git@github.com:rdtiv/claude-infra.git && cd claude-infra
./install.sh          # idempotent; re-run after every pull
```

Then restart Claude Code sessions (agents/commands/hooks load at session
start). No git on the machine? Paste `setup-prompt.md` into a Claude Code
session and say "execute this".

## What's installed

| Path | What |
|---|---|
| `~/.claude/agents/` | Five pinned roles: `scout`/`finder`/`implementor` (sonnet), `architect`/`verifier` (opus) |
| `~/.claude/hooks/agent-model-guard.mjs` | PreToolUse guard: denies Agent spawns that would inherit the session model or that name Fable |
| `~/.claude/commands/orchestrate.md` | `/orchestrate <goal>` — session contract: spec first, delegate to pinned workers, verify adversarially |
| `~/.claude/commands/mission.md` | `/mission <issue#>` / `/mission end` — worktree lifecycle: provision fresh from origin, decommission on merge; main checkout = integration ground only |
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
folded into the agent bodies and the mission command — see sartora's versions.

## Expected behavior / non-bugs

- Built-in agent types (Explore, Plan, general-purpose) and plugin agents get
  **denied until the orchestrator passes `model:` explicitly** — intentional
  friction, one corrective round-trip.
- In repos with the repo-level hook, both hooks fire; duplicate denies are
  harmless.
- Workflow-internal `agent()` calls bypass PreToolUse — pin models inside
  workflow scripts (see sartora `.claude/workflows/code-review-mixed.js`).
- The hook fails open on unparseable input and only evaluates the Agent tool.

## Updating

Edit here → commit → on each machine: `git pull && ./install.sh`. For repos
carrying the repo-level copy, port the change over in a PR.
