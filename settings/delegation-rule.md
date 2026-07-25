<!--
  Installed by claude-infra to ~/.claude/rules/claude-infra-delegation.md.
  OWNED BY THE INSTALLER and overwritten wholesale on every ./install.sh — edit it
  here, not there. No `paths:` frontmatter: that would make it load on demand, and
  this has to load at session launch, in every project.

  Keep this short. It sits in the context of every session in every repo, including
  the ones that never run a mission. Anything mission-shaped belongs in
  commands/mission.md, which loads only when invoked.
-->

## Delegation

- **Subagents never inherit the session model or effort.** Use the pinned types in
  `~/.claude/agents/` — `scout`/`finder`/`implementor` (sonnet, medium), `architect`
  (opus, xhigh), `verifier`/`documentarian` (opus, high) — or pass `model:` explicitly
  on a raw Agent call. A PreToolUse hook enforces this by reading each agent's own
  definition, so a new agent needs both pins in its frontmatter or its spawns are
  denied. Pinning buys reproducibility and keeps workers off the orchestrator's
  rate-limit bucket; effort matters as much as model, and it is the axis no hook can
  observe at runtime, which is why the definition has to declare it.
- **The main checkout is integration ground** — pulls, triage, review, coordination.
  Feature commits happen in a worktree.
- **`/mission <issue# | pr# | description>`** for anything that warrants a branch and a
  PR; `/mission end` to decommission. Small conversational work needs none of this.
- Set the tier with `/model` before starting real work: **Fable** when you are in the
  loop clarifying unknowns as it goes, **Opus** for decomposable work meant to run
  unattended.
