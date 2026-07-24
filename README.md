# claude-infra

A portable Claude Code environment: the two-tier delegation policy
(orchestrator designs, pinned cheaper workers execute), mechanically enforced,
plus the mission/worktree lifecycle. Canonical source of truth — machines and
repos install *from here*; edits happen *here first*.

Origin: analysis of a five-day multi-agent sprint found roughly a third of
subagent turns running on the frontier model by silent inheritance — the
Agent tool's `model` param is optional and prose doctrine wasn't
mechanically enforced.

**Why pin, honestly.** Not mainly cost: the spread is ~1.7x (opus→sonnet) to
~3.3x (fable→sonnet). Real, but not the order of magnitude the origin story
implies. The durable reasons are **predictability** — a run whose tiers are
pinned is reproducible and comparable across sessions — and **rate-limit
separation**, since frontier and worker tiers draw from different buckets, so
pinned workers never contend with the orchestrator's own turns. **Effort is
pinned for the same reasons and matters at least as much**: near the top of the
ladder it moves more tokens than a tier change does, and it is the one axis no
hook can observe at spawn time, which is why every agent definition has to
declare it.

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
| `~/.claude/agents/` | Six pinned roles, each pinning **model and effort**: `scout`/`finder`/`implementor` (sonnet, medium), `architect` (opus, xhigh), `verifier`/`documentarian` (opus, high) |
| `~/.claude/hooks/agent-model-guard.mjs` | PreToolUse guard: reads the spawned agent's **own definition** and denies unless it pins an approved `model:` *and* an explicit `effort:`. Model approval is an allowlist (`sonnet`/`opus`/`haiku`, or a version-pinned ID of one), so unknown and frontier tiers fail closed. Also denies spawns that would inherit the session model, and `subagent_type: fork` unconditionally (a fork ignores `model:`) |
| `~/.claude/hooks/git-destruction-guard.mjs` | PreToolUse guard: denies working-tree-destroying git (`reset --hard`, `clean -f`/`--force`, `checkout .` or `checkout <ref> -- <path>`, `restore` unless staged-only, `stash drop`) outside `.claude/worktrees/` and scratch paths — the main checkout may hold another session's uncommitted work. Matches on quote-stripped command text, so commands that merely mention destructive git in a string are not blocked |
| `~/.claude/hooks/session-protocol.sh` | SessionStart hook: injects the standing ritual so every session opens by surfacing the protocol (model tier → /mission → /orchestrate) |
| `~/.claude/commands/orchestrate.md` | `/orchestrate <goal>` — session contract: spec first, delegate to pinned workers, verify adversarially |
| `~/.claude/commands/mission.md` | `/mission <issue#>` / `/mission end` — worktree lifecycle: provision fresh from origin, one worktree per independent stream (agent-level `isolation: "worktree"` for merely-concurrent writers); at end, a `documentarian` docs gate precedes decommission and *every* mission worktree is verified and removed; migrations ship to prod before the code that needs them; main checkout = integration ground only |
| `~/.claude/settings.json` | Hook wiring (merged, never clobbered) |
| `~/.claude/rules/claude-infra-delegation.md` | The delegation doctrine. Installer-**owned** and overwritten wholesale every run — `~/.claude/rules/*.md` is auto-loaded at user scope, so this needs no entry in `CLAUDE.md` and the installer never writes to that file |

## Session-start language

1. `/model fable` (ambiguous / novel / multi-stream) or `/model opus`
   (well-specified / single-stream) — the orchestrator tier.
2. `/mission <issue#>` for a new unit of work; `/orchestrate <goal>` for the
   build contract inside it. Plain prompting for conversational/small work.

## Repo-level install (for repos with cloud sessions)

Cloud sessions don't see `~/.claude`, so repos that run them need their own
copy under `.claude/`. Use the sync tool rather than copying by hand:

```sh
./sync-repo.sh --scan ~/dev        # which repos have an install, and what version
./sync-repo.sh ~/dev/myrepo --dry-run
./sync-repo.sh ~/dev/myrepo
```

It splits the tree by who owns what. **Hooks** are pure mechanism and get
overwritten verbatim. **Agent frontmatter** (`model:`/`effort:`) is owned here
and is patched in place. **Agent bodies are owned by the repo** — repo-specific
lint commands, house review doctrine — and are never written, only reported as
drift. `settings.json` is merged, so an unrelated pre-existing hook survives.
`.gitignore` is reported on, never edited: if `.claude/*` is ignored it needs
`!.claude/agents/`, `!.claude/hooks/`, `!.claude/commands/`.

`--dry-run` writes nothing. A `.claude/.claude-infra-version` stamp records the
source commit. The tool never commits — it leaves a dirty tree so the change
lands through the target repo's own review gate.

## Verifying

```sh
./verify.sh          # also run automatically by ./install.sh
```

79 checks: both hook behavior matrices, every agent pinning both axes, doctrine
propagation and idempotency, `setup-prompt.md` matching a fresh generation, and
`sync-repo.sh` against a downstream whose agent bodies are customized. Everything
runs against scratch copies — it never writes to `$HOME`, this repo, or any
downstream.

## Expected behavior / non-bugs

- **An agent whose definition is missing `model:` or `effort:` is denied.** That
  is the enforcement mechanism, not a bug: effort is not a parameter on the Agent
  tool, so a hook can never see the effort a spawn runs at — but it can refuse to
  spawn an agent that never declared one. Add both pins to the frontmatter.
- **Unknown model aliases are denied.** Approval is an allowlist (`sonnet`,
  `opus`, `haiku`, or a version-pinned ID of one). A denylist would silently
  permit the next frontier alias nobody had written a rule for; a guard's failure
  mode should be deny.
- Built-in agent types (Explore, Plan, general-purpose) and plugin agents get
  **denied until the orchestrator passes `model:` explicitly** — intentional
  friction, one corrective round-trip. Their effort still inherits the session;
  there is no way to pin a definition this repo doesn't own.
- `subagent_type: fork` is **denied unconditionally**: the Agent tool ignores
  `model` for forks, so a fork always runs on the session model. Passing
  `model:` on a fork looks compliant and isn't — hence the hard deny.
- In repos with the repo-level hook, both hooks fire; duplicate denies are
  harmless.
- Workflow-internal `agent()` calls bypass PreToolUse — pin models inside
  workflow scripts in the workflow script itself.
- The hook fails open on unparseable input and only evaluates the Agent tool.
- **A commit message that describes destructive git gets denied** from a
  non-scratch cwd — `git-destruction-guard` inspects the Bash command text, and
  an incident write-up contains exactly those words. Use `git commit -F <file>`
  and `gh pr --body-file <file>`.

## Updating

Edit here → commit → on each machine: `git pull && ./install.sh`. For repos
carrying the repo-level copy: `./sync-repo.sh <path>`, then land it as a PR there.

**Hooks and agents must move together.** The guard requires every house agent to
pin both axes, so pulling the hook without the agent files denies every house
type until they land. `./install.sh` copies both, which is why it is the update
path rather than a manual copy.
