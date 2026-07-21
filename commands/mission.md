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
2. The kickoff issue is closed or updated with the punch list; review
   findings dispositioned wherever the repo tracks them.
3. Verify nothing unmerged: worktree `git status --short` is clean AND
   `git diff <default> <branch>` for source files is empty (squash merges
   break ancestry — always tree-diff, never trust `branch --merged`).
4. Remove the worktree, delete the local branch, and delete the remote
   branch only after the whole stack is in.
5. Report the decommission in your final summary: worktree removed, branches
   deleted, state externalized where.

## Standing rules (both directions)

- **The main checkout is the integration ground**: pulls, triage, reviews,
  coordination. Feature commits never happen there.
- One mission per worktree; never reuse a mission worktree for a different
  mission — decommission and provision fresh.
- Never rename a branch that has an open PR (GitHub auto-closes it,
  unrecoverably).

Mission: $ARGUMENTS
