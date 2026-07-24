#!/usr/bin/env bash
# SessionStart hook: inject the standing protocol into session context so the
# session opens by briefly surfacing it to the operator.
cat <<'EOF'
[session-protocol] Standing ritual — open the session by surfacing this to the operator in 3-4 short lines (then proceed normally):
1. Orchestrator tier: /model fable (ambiguous, novel, multi-stream) or /model opus (well-specified, single-stream). Ask which if a real build is starting and none was chosen.
2. Unit of work: /mission <issue# or goal> provisions a fresh worktree (one mission = one issue = one branch family = one session; more than one worktree is fine for independent streams); /mission end decommissions every one of them. The main checkout is integration ground only.
3. Build contract: /orchestrate <goal> — scout recon → architect specs → parallel implementors → finder/verifier pass → the repo's PR gate. The orchestrator never types out multi-file packages inline, and equally never delegates what it would finish in a handful of tool calls.
Workers pin model AND effort (scout/finder/implementor = sonnet+medium; architect = opus+xhigh; verifier/documentarian = opus+high); raw Agent spawns must pass model explicitly; the hook reads each agent's own definition and denies anything missing either pin, plus any frontier or unrecognized tier. Small conversational work needs none of this — plain prompting is fine.
EOF
