#!/usr/bin/env bash
# SessionStart hook: inject the standing protocol into session context so the
# session opens by briefly surfacing it to the operator.
cat <<'EOF'
[session-protocol] Standing ritual — open the session by surfacing this to the operator in 3-4 short lines (then proceed normally):
1. Orchestrator tier: /model fable (ambiguous, novel, multi-stream) or /model opus (well-specified, single-stream). Ask which if a real build is starting and none was chosen.
2. Unit of work: /mission <issue# or goal> provisions a fresh worktree (one mission = one issue = one worktree = one session); /mission end decommissions. The main checkout is integration ground only.
3. Build contract: /orchestrate <goal> — scout recon → architect specs → parallel implementors → finder/verifier pass → the repo's PR gate. The orchestrator never types out multi-file packages inline.
Workers are pinned (scout/finder/implementor = sonnet; architect/verifier = opus); raw Agent spawns must pass model explicitly; Fable subagents are denied by hook. Small conversational work needs none of this — plain prompting is fine.
EOF
