<!--
  Installed by claude-infra to ~/.claude/rules/claude-infra-delegation.md.
  This file is OWNED BY THE INSTALLER and overwritten wholesale on every
  ./install.sh — do not hand-edit the installed copy; edit it here and re-run.

  Deliberately carries NO `paths:` frontmatter. A rule with `paths:` loads
  on-demand for matching files; this one must load at session launch, for every
  project, which is what a bare rules file does.
-->

## Delegation & session modes

- I pick the orchestrator tier at session start via `/model`: **Fable** for ambiguous, novel, or multi-stream programs; **Opus** for well-specified single-stream work. Either way the main session designs, specs, judges, and coordinates — it does not type out large mechanical work packages inline.
- Subagents **never inherit the session model or the session effort**. Delegate through the pinned agent types in `~/.claude/agents/` — `scout`/`finder`/`implementor` (sonnet, medium), `architect` (opus, xhigh), `verifier`/`documentarian` (opus, high) — or pass `model:` explicitly on raw Agent calls (`sonnet` mechanical, `opus` judgment, `haiku` trivial). Never spawn a frontier subagent. A PreToolUse hook enforces this by reading each agent's own definition, so a new agent needs both pins in its frontmatter or its spawns are denied.
- **Why both pins, and why mechanically.** Not mainly cost — the spread is ~1.7x (opus→sonnet) to ~3.3x (fable→sonnet), real but not an order of magnitude. The durable reasons are *predictability*, since a run whose tiers are pinned is reproducible and comparable across sessions, and *rate-limit separation*, since the frontier and worker tiers draw from different buckets and pinned workers therefore don't contend with the orchestrator's own turns. Effort matters at least as much as model: near the top of the ladder it can move more tokens than a tier change does, and it is the one axis no hook can observe at spawn time — which is why the definition has to declare it.
- `/orchestrate <goal>` invokes the full contract: scout recon → architect specs → parallel implementors → finder/verifier pass → the repo's PR gate. Use it for any multi-package build. It carries a floor as well as a ceiling: don't delegate what you'd finish in a handful of tool calls, and keep spawn counts low.
- `/mission <issue#>` / `/mission end` runs the worktree lifecycle: one mission = one kickoff issue = one branch family = one session. A mission may hold more than one worktree when its streams are genuinely independent; a worktree is never reused across missions. The main checkout is the integration ground — feature commits never happen there.
