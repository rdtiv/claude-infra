

## Delegation & session modes

- I pick the orchestrator tier at session start via `/model`: **Fable** for ambiguous, novel, or multi-stream programs; **Opus** for well-specified single-stream work. Either way the main session designs, specs, judges, and coordinates — it does not type out large mechanical work packages inline.
- Subagents **never inherit the session model**. Delegate through the pinned agent types in `~/.claude/agents/` — `scout`/`finder`/`implementor` (sonnet), `architect`/`verifier` (opus) — or pass `model:` explicitly on raw Agent calls (`sonnet` mechanical, `opus` judgment, `haiku` trivial). Never spawn a Fable subagent. A PreToolUse hook enforces this.
- `/orchestrate <goal>` invokes the full contract: scout recon → architect specs → parallel implementors → finder/verifier pass → the repo's PR gate. Use it for any multi-package build.
- `/mission <issue#>` / `/mission end` runs the worktree lifecycle: one mission = one kickoff issue = one worktree = one branch family = one session. The main checkout is the integration ground — feature commits never happen there.
