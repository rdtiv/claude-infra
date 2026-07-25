# claude-infra

A portable Claude Code setup that makes multi-agent work **predictable, cheap, and
safe to run unattended** — by pinning which model each kind of subagent uses, and
enforcing it in a hook rather than hoping a prompt is followed.

Install it once per machine. It adds a set of named agent roles, two guardrails, and
one command that runs a piece of work end to end.

---

## Why

Claude Code lets a session spawn subagents. Left alone, three things go wrong.

**Subagents silently inherit the session's model and reasoning effort.** The `model`
parameter is optional, so a subagent doing mechanical work — reading files, applying a
written spec — quietly runs on the frontier model at whatever depth the session was
set to. It works, and it costs several times what it should. Effort is worse than
model here: it's not a parameter the harness exposes at all, so nothing can observe it
at spawn time.

**Runs aren't reproducible.** If the tier a subagent used depends on whatever the
session happened to be set to that day, two runs of the same work aren't comparable,
and neither is their cost.

**Agents will clear things that block them.** A review agent that finds a dirty
working tree will, given a shell, "fix" it. On a machine running several sessions at
once, that tree may hold someone else's uncommitted work.

The fix for all three is the same shape: decide once, encode it in a file, and let a
hook enforce it. Prose in a prompt is a suggestion; a `PreToolUse` hook is not.

**On cost, honestly.** The spread is roughly 1.7× (opus→sonnet) to 3.3×
(fable→sonnet) — real, but not an order of magnitude. The more durable reasons to pin
are reproducibility, and the fact that frontier and worker tiers draw on separate
rate-limit buckets, so pinned workers never contend with the orchestrator's own turns.

This mirrors what others have measured independently: a frontier model planning with
cheaper models executing beats frontier-everywhere on both quality and cost, because
only a few moments in a task — the decomposition, the design calls — actually need
frontier reasoning. Once those collapse into an explicit spec, a cheaper model just
follows it.

---

## What you get

**Six named agent roles**, each pinning both its model and its reasoning effort:

| Role | Model | Effort | For |
|---|---|---|---|
| `scout` | sonnet | medium | Read-only recon — map a subsystem, find call sites |
| `finder` | sonnet | medium | Hunt one angle of a diff, report every candidate |
| `implementor` | sonnet | medium | Execute one written work package |
| `architect` | opus | xhigh | Turn a goal into implementor-ready specs |
| `verifier` | opus | high | Adversarially judge one finding against the code |
| `documentarian` | opus | high | Mission-end documentation gate |

**Two guardrails.** One refuses to spawn a subagent whose definition doesn't pin both
axes, or that names an unapproved model. The other refuses working-tree-destroying git
outside a worktree or scratch path.

**One command.** `/mission` provisions a worktree, runs the work through recon → spec
→ implement → review → PR, and decommissions cleanly.

---

## Install

```sh
git clone https://github.com/rdtiv/claude-infra.git && cd claude-infra
./install.sh
```

Then **restart your Claude Code sessions** — agents, commands, and hooks load at
session start.

No git on the machine? Paste `setup-prompt.md` into a Claude Code session and say
"execute this". It contains everything inline.

### Updating from a previous version

```sh
cd claude-infra && git pull && ./install.sh
```

Three things worth knowing:

**Always use `./install.sh` — never copy files by hand.** The guard requires every
agent to pin both model and effort, so hooks and agent files have to move together.
Copying one without the other denies every agent role until the other lands. The
installer copies both.

**The installer retires things, not just adds them.** Artifacts removed upstream are
deleted from `~/.claude` and unwired from your `settings.json` on the next run. If an
earlier version installed a `session-protocol.sh` hook or an `orchestrate.md` command,
those go away automatically — you don't need to hunt for them.

**One thing the installer deliberately won't touch.** Early versions appended a
`## Delegation & session modes` section to `~/.claude/CLAUDE.md`. Doctrine now ships as
its own file, so that section is a stale second copy. The installer prints a warning
but will not remove it, because on a real machine it's followed immediately by your own
preferences with no heading between them, and any automatic boundary-guessing would
take those with it. **Delete that section by hand once**, and the warning stops.

Re-running the installer is always safe; it's idempotent.

---

## Using it

**1. Pick the tier** with `/model`:

- **Fable** when you're in the loop, clarifying unknowns as the work proceeds. Hard or
  ambiguous problems where the bottleneck is articulating what nobody knows yet.
- **Opus** for decomposable work meant to run unattended — strongest when handed the
  full specification up front and left alone.

**2. Start the work** with `/mission <issue# | pr# | description>`.

That's the whole interface. `/mission` provisions a worktree from the default branch,
opens a task list, runs recon → specs → implementation → adversarial review → your
repo's PR gate, and keeps commits out of your main checkout. `/mission end`
decommissions: verifies nothing is unmerged, removes every worktree it created, and
reconciles loose ends onto the kickoff issue.

Small conversational work needs none of this — plain prompting is fine.

There's no separate "build contract" to invoke. `/mission` carries it, and emits
delegation guidance matched to the tier you chose: Opus is told to cap delegation,
Fable to use subagents freely and asynchronously. Those are opposite instructions,
which is exactly why they're never both in context.

---

## Behaviors that look like bugs

- **An agent missing `model:` or `effort:` is denied.** That's the enforcement working.
  Effort isn't a parameter the harness exposes, so a hook can never see the effort a
  spawn *runs at* — but it can refuse to spawn one that never *declared* one. Add both
  pins to the frontmatter.
- **Unknown model names are denied**, not just known-bad ones. Approval is an allowlist
  (`sonnet`, `opus`, `haiku`, or a version-pinned ID of one). A denylist would silently
  permit the next model alias nobody had written a rule for.
- **Built-in agent types** (Explore, Plan, general-purpose) and plugin agents are denied
  until you pass `model:` explicitly — one corrective round-trip, by design. Their
  effort still inherits the session; there's no way to pin a definition we don't own.
- **`subagent_type: fork` is always denied.** A fork ignores `model:`, so it always runs
  on the session model — passing one looks compliant and isn't.
- **A commit message describing destructive git gets denied** from a non-scratch
  directory. The guard inspects the command text, and an incident write-up contains
  exactly those words. Use `git commit -F <file>` and `gh pr --body-file <file>`.
- Workflow-internal `agent()` calls bypass hooks entirely — pin models inside the
  workflow script.
- The guard fails open on unparseable input, and only ever evaluates the Agent tool.

---

## Reference: what lands where

| Path | What |
|---|---|
| `~/.claude/agents/` | The six roles above, each pinning model and effort in frontmatter |
| `~/.claude/hooks/agent-model-guard.mjs` | Reads the spawned agent's own definition and denies unless it pins an approved `model:` and an explicit `effort:`. Also denies inheriting spawns and `subagent_type: fork` |
| `~/.claude/hooks/git-destruction-guard.mjs` | Denies `reset --hard`, `clean -f`, `checkout .`, `checkout <ref> -- <path>`, non-staged `restore`, `stash drop` outside `.claude/worktrees/` and scratch paths. Matches quote-stripped text, so merely *mentioning* those commands in a string is fine |
| `~/.claude/commands/mission.md` | `/mission` and `/mission end` — the full lifecycle |
| `~/.claude/rules/claude-infra-delegation.md` | The short always-loaded doctrine. Installer-owned and overwritten every run; auto-loaded at user scope, so it needs no entry in `CLAUDE.md` |
| `~/.claude/settings.json` | Hook wiring, merged into whatever is already there |

---

## Repo-level install

Cloud sessions don't see `~/.claude`, so a repo that runs them needs its own copy under
`.claude/`. Use the sync tool rather than copying by hand:

```sh
./sync-repo.sh --scan ~/dev              # which repos have it, and at what version
./sync-repo.sh ~/dev/myrepo --dry-run    # see what would change

# Sync into a worktree, so the commit doesn't land on your integration ground:
git -C ~/dev/myrepo worktree add .claude/worktrees/wt-infra-sync -b chore/sync origin/main
./sync-repo.sh ~/dev/myrepo/.claude/worktrees/wt-infra-sync --allow-worktree
# commit + PR from that worktree, then remove it
```

It splits the tree by who owns what. **Hooks** are pure mechanism and get overwritten.
**Agent frontmatter** is owned here and patched in place. **Agent bodies belong to the
repo** — its own lint commands, house review conventions — and are never written, only
reported as drift. `settings.json` is merged, so unrelated hooks survive. Files removed
upstream are retired downstream. `.gitignore` is reported on but never edited: if
`.claude/*` is ignored, it needs `!.claude/agents/`, `!.claude/hooks/`,
`!.claude/commands/`, and `!.claude/.claude-infra-version`.

The tool never commits. It leaves a dirty tree so the change lands through that repo's
own review gate.

---

## Verifying

```sh
./verify.sh          # also run automatically by ./install.sh
```

103 checks: both guard behavior matrices, every agent pinning both axes, install and
doctrine propagation including idempotency and the migration from older layouts,
`setup-prompt.md` matching a fresh generation, and `sync-repo.sh` against a downstream
whose agent bodies are customized. Everything runs against scratch copies — it never
writes to `$HOME`, to this repo, or to any downstream.

---

## Contributing changes

Edit here, commit, then on each machine `git pull && ./install.sh`. For repos carrying
a repo-level copy, `./sync-repo.sh <path>` and land it as a PR there.

`setup-prompt.md` is **generated** — edit `settings/setup-prompt.template.md` and run
`node build-setup-prompt.mjs`. `./verify.sh` fails if the committed copy doesn't match
a fresh generation.
