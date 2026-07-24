---
description: Start or finish a mission — one worktree, one branch family, one kickoff issue. Provision at start, decommission at end; the main checkout never does feature work.
---

You are running the **mission lifecycle**. A mission is one unit of work:
one kickoff issue ↔ one worktree ↔ one branch family ↔ one session.
`$ARGUMENTS` is either a kickoff (issue number and/or goal) or the word `end`.

## If starting (`/mission <issue# or goal>`)

1. **Provision:**
   - Fetch and read the kickoff issue if one was given; if none exists and
     the work is multi-package, draft one first (self-contained start-prompt
     style) and get the operator's OK.
   - Create the worktree fresh from the default remote branch:
     `git worktree add .claude/worktrees/wt-<issue>-<slug> -b <type>/<slug> origin/<default>`.
   - Install dependencies and environment per the repo's CLAUDE.md. In a
     fresh worktree, install *real* dependencies (`npm ci` / `pnpm i` /
     `bun install` / etc.) — do NOT symlink `node_modules` from the main
     checkout. Some bundlers (notably Turbopack) reject a `node_modules`
     symlink that points outside the worktree's filesystem root and the
     build fails ("Symlink node_modules is invalid, it points out of the
     filesystem root").
   - If the repo runs a dev server, claim the port deterministically:
     `3000 + (issue# % 1000)`; state it in your first status line.
2. **Execute** under the orchestration contract (`/orchestrate`): scout recon
   → architect specs → pinned implementors → finder/verifier pass → the
   repo's PR gate. All commits happen in this worktree — never in the main
   checkout.
3. **Externalize state** at every phase end (issue comments, plan docs,
   tracker if the repo has one) so a fresh session can resume from artifacts
   alone.

## If finishing (`/mission end`)

Decommission checklist — a mission is not done until all of these:

1. All mission PRs merged (by the operator) or explicitly parked with an issue comment
   saying what remains and why.
2. **Documentation gate**: launch the pinned `documentarian` agent over the
   mission's merged work (give it the kickoff issue number and the merged PR
   list). The mission is not documented until its docs PR has landed through
   the repo's review gate, or the agent's explicit no-docs-impact verdict is
   recorded on the kickoff issue. Do not decommission ahead of this gate.
3. The kickoff issue is closed or updated with the punch list; review
   findings dispositioned wherever the repo tracks them.
4. Verify nothing unmerged: worktree `git status --short` is clean AND
   `git diff <default> <branch>` for source files is empty (squash merges
   break ancestry — always tree-diff, never trust `branch --merged`).
5. Remove the worktree, delete the local branch, and delete the remote
   branch only after the whole stack is in.
6. Report the decommission in your final summary: worktree removed, branches
   deleted, state externalized where.

## Standing rules (both directions)

- **The main checkout is the integration ground**: pulls, triage, reviews,
  coordination. Feature commits never happen there.
- **The main checkout may hold ANOTHER session's uncommitted work at any
  time** (multi-session machines are the norm). Dirt there is never yours to
  clean: a dirty tree, a failing build, a surprise branch — report it and
  route around it; never `reset`/`clean`/`checkout .` it away. (A review
  finder once "fixed" a blocked diff with `git reset --hard && git clean -fd`
  in the main checkout and destroyed 19 files of a parallel session's work.)
  The `git-destruction-guard` hook now denies destructive git outside
  `.claude/worktrees/` and scratch paths — mechanically, for every session
  and subagent.
- **Read-only agents need the rule IN THE PROMPT.** Scout/finder/verifier
  and any ad-hoc review or recon prompt must carry an explicit no-mutation
  clause; read-only intent is not inherited, and a Bash-equipped agent will
  eventually "fix" whatever blocks it. The pinned agent definitions carry it;
  raw Agent prompts must add it.
- One mission per worktree; never reuse a mission worktree for a different
  mission — decommission and provision fresh.
- Never rename a branch that has an open PR (GitHub auto-closes it,
  unrecoverably).
- **Stacked PRs with kept branches: retarget before every merge.** `gh pr
  merge` merges head→base *literally*; GitHub only retargets dependents to
  main when the base branch is DELETED. With kept branches (the safe
  default), merging a stacked PR lands its content into the branch below,
  not main — silently, with the PR showing MERGED. Procedure: after the PR
  below lands, `gh pr edit <next#> --base main` FIRST, then merge; then
  **tree-diff the landing** (`git diff origin/main <branch> --stat`) —
  never trust the MERGED state alone. (Learned on a mission where three
  PRs sat "merged" in a branch chain while main held only the first.)
- **Verify commands by exit code, never through a pipe.** `build | tail`
  reports tail's exit, not the build's — a failing build shipped that way
  once. Pattern: `cmd > log 2>&1; echo "exit: $?"`. Same family: never
  filter push output.
- **Shell cwd resets between tool calls**: a bare `git checkout` / `git
  push` / `npm run dev` can silently execute in the main checkout. Always
  `git -C <worktree>` or `cd <worktree> && ...` in the same command line,
  and verify a dev server's cwd (`lsof -p <pid> -d cwd`) before trusting
  what it serves.
- **Restart the dev server after switching worktree branches** before
  trusting behavior probes — hot reload across branch switches serves
  stale module state (two model-behavior probes were invalidated this
  way).
- **Parallel missions can collide on main** (file moves, shared docs).
  At kickoff, note territories the mission will touch; before integration
  merges, re-fetch and check whether main moved under you — resolve with
  content-from-your-branch, structure-from-main (rename detection usually
  helps), and re-verify with the doc/lint gates of CURRENT main.

Mission: $ARGUMENTS
