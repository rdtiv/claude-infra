---
description: Run a mission — provision, execute under the delegation contract, decommission. One kickoff, one branch family, one session; the main checkout never does feature work.
---

You are running a **mission**: one kickoff ↔ one branch family ↔ one session.
`$ARGUMENTS` is the kickoff — an issue number, a PR number, or a description — or
the word `end`.

**Name the tier you are on in your first status line.** The operator sets it with
`/model` before invoking this; you observe it, you do not choose it. It changes the
delegation guidance in step 3, so a wrong tier is worth catching before you provision.

- **Fable** — the operator is in the loop, clarifying unknowns as the work proceeds.
  Hard or ambiguous problems where the bottleneck is articulating what nobody knows yet.
- **Opus** — decomposable work meant to run unattended. Strongest when handed the
  complete specification up front and left alone.

A mission may hold **more than one worktree**. What stays singular is the kickoff, the
branch family, and the session — not the checkout count.

- **Ephemeral agent worktrees** — the default for concurrent writers. `isolation:
  "worktree"` on the Agent call gives that agent its own checkout, auto-removed if it
  changes nothing. No branch, nothing to decommission.
- **Long-lived stream worktrees** — one per genuinely independent stream that will land
  as its own PR: `.claude/worktrees/wt-<ref>-<stream>` on `<type>/<slug>-<stream>`,
  where `<ref>` is fixed in step 1 below.

Prefer agent isolation. If two streams would touch the same files, they are one stream.

## If starting (`/mission <issue# | pr# | description>`)

1. **Provision:**
   - Read the kickoff — fetch the issue or PR if one was given. **Fix a `<ref>` now
     and use it everywhere below**: the issue number, the PR number, or for a
     description kickoff a short slug you pick. Everything downstream keys off it.
   - **A description kickoff needs a home before it needs a worktree.** The
     decommission checklist records worktrees, dispositions findings, and closes out
     against a durable artifact; with nothing to write to, a second concurrent
     mission has no way to know which worktrees are yours. If the work is
     multi-package, draft the issue first and get the operator's OK. If it is small
     enough not to warrant one, say so explicitly in your first status line and use
     the PR description as the artifact instead — but do not proceed silently.
   - Create the worktree fresh from the default remote branch:
     `git worktree add .claude/worktrees/wt-<ref>-<slug> -b <type>/<slug> origin/<default>`.
     If the mission has independent streams that will land as separate PRs, add
     one per stream — `wt-<ref>-<stream>` on `<type>/<slug>-<stream>`, each
     branched from `origin/<default>`, never from a sibling stream. Record the
     full worktree list on the kickoff artifact; `/mission end` has to decommission
     every one of them, and an unrecorded worktree is one that gets stranded.
   - Install dependencies and environment per the repo's CLAUDE.md. In a
     fresh worktree, install *real* dependencies (`npm ci` / `pnpm i` /
     `bun install` / etc.) — do NOT symlink `node_modules` from the main
     checkout. Some bundlers (notably Turbopack) reject a `node_modules`
     symlink that points outside the worktree's filesystem root and the
     build fails ("Symlink node_modules is invalid, it points out of the
     filesystem root").
   - If the repo runs a dev server, claim the port deterministically from `<ref>`:
     `3000 + (issue-or-PR-number % 1000)`, or for a non-numeric ref
     `3000 + (cksum of the slug % 1000)` — the property that matters is that two
     concurrent missions never derive the same port, so the input must be the ref
     and not something incidental. State it in your first status line.
2. **Open the task list** — one task per work package. Always; if the work were small
   enough not to need it, it would not be a mission.

   It is not the same artifact as step 4 and does not substitute for it. The task list
   is *in-session working state* — what is in flight, in what order, visible to the
   operator while you work — and it dies with the session. Externalized state is
   *durable and operator-facing* and outlives it. A thorough issue with an untouched
   task list satisfies step 4 while losing everything this step is for, which is the
   easy mistake because the issue feels like tracking.

3. **Execute.** Your job is design, specification, judgment, and coordination.

   Scout recon (parallel, one mapping question each) → `architect` specs, or write them
   yourself: files with verified anchors, the change, invariants, out-of-scope,
   verification commands → `implementor` agents run the packages → `finder` fleets for
   coverage and `verifier` agents for judgment, or the repo's own review workflow →
   the repo's PR gate. Work the findings, not the score. You review implementor reports;
   you do not rewrite their work unless a package fails twice.

   **Local review gate runs to clean BEFORE the remote one — never concurrently.**
   `/review-pinned` costs no CI minutes and has no round-trip; a remote or CI reviewer
   costs both on every push. Anything the local pass would have caught is a remote run
   spent to learn what you could already have known. Running them in parallel is worse
   than wasteful: two reviewers working the same diff land duplicate and conflicting
   fixes on one branch, and you end up rebasing your own work onto a reviewer's
   equivalent commit. Invite the remote gate once local is clean.

   All commits happen in a mission worktree — never the main checkout. Keep the task
   list current: a package flips to in-progress when its implementor spawns, and to
   completed when its work is *verified*, not when it is written.

   **Delegation, on Opus** — cap it. Each subagent re-establishes context, re-explores,
   reports back, and then you re-read the report. Don't delegate what you would finish
   in a handful of tool calls. Don't fan several agents at one modest job. Keep spawn
   counts low. Commit to a delegation rather than re-deriving its findings.

   **Delegation, on Fable** — use it freely. Dispatch independent subtasks and keep
   working while they run rather than blocking on each return. Prefer long-lived
   subagents that hold context across subtasks, which saves time and cost through cache
   reads and avoids bottlenecking on the slowest one. Intervene when a subagent goes off
   track or is missing context, not on a schedule.

   Inline work is the exception either way: trivial edits, spec-writing, judgment calls,
   and integration decisions.
4. **Externalize state** at every phase end (issue comments, plan docs, tracker if the
   repo has one) so a fresh session can resume from artifacts alone. The task list is
   *not* externalized state — it is not durable and a fresh session cannot read it.

## If finishing (`/mission end`)

Decommission checklist — a mission is not done until all of these:

1. All mission PRs merged (by the operator) or explicitly parked with an issue comment
   saying what remains and why.
2. **Documentation gate**: launch the pinned `documentarian` agent over the
   mission's merged work (give it the kickoff artifact and the merged PR
   list). The gate closes when one of these is true: the docs PR has landed
   through the repo's review gate; the docs PR is open, gated, and explicitly
   parked on the kickoff artifact as the remaining item (merging stays a human
   decision — never block decommission on the operator's merge timing); or the
   agent's explicit no-docs-impact verdict is recorded on the kickoff artifact.
3. The kickoff artifact is closed or updated with the punch list; review
   findings dispositioned wherever the repo tracks them. **Reconcile the task
   list into it first** — anything still open or discovered late lives only in
   the task list, which is about to vanish with the session. Then clear it.
4. Verify nothing unmerged — **for every mission worktree, not just the one you
   are standing in**. Enumerate them first (`git worktree list`, cross-checked
   against the list recorded on the kickoff artifact), then for each: `git status
   --short` is clean, AND every file the branch touched has landed. A mission
   with three worktrees and one checked is a mission with two unverified
   checkouts.

   **Two checks that look right and are not:**

   - *Ancestry* — `branch --merged`, or `git log <branch> --not <default>`. A
     squash merge rewrites the commit, so the branch tip is not an ancestor of
     the default branch and these report unmerged work that landed perfectly
     well. False positive, every time, on every squash-merged branch.
   - *Plain two-dot tree-diff* — `git diff <default> <branch>`. This is only
     empty while the default branch has not moved. The moment anything else
     merges, it reports that difference too, and you cannot tell "my work never
     landed" from "someone else's did." False positive that grows with time.

   **What actually works** is per-file content: for each path the branch touched,
   its blob on the branch must equal its blob on the base, treating *absent* as a
   value so a deletion that landed compares equal. **Use the script — do not
   hand-roll it:**

   ```sh
   # repo-level install (cloud sessions included), else user scope:
   .claude/scripts/landed.sh <branch> origin/<default>    # exit 0 = safe to remove
   ~/.claude/scripts/landed.sh <branch> origin/<default>
   ```

   It is a script rather than a snippet here because the snippet was wrong three
   separate times — ancestry, diff direction, and `rev-parse` printing its argument
   on a missing path so every *deleted* file reported as unlanded. `verify.sh`
   exercises it, including that deletion case.

   **Make the check gate the removal.** Never chain `git worktree remove` after a
   command that only *prints* a verdict — `check | wc -l` succeeds whether the count
   is 0 or 50, so `&&` runs the removal either way and the verification becomes
   decoration. Branch on the exit code:

   ```sh
   if <path>/landed.sh <branch> origin/<default> && [ -z "$(git -C <wt> status --short)" ]; then
     git worktree remove <wt>
   fi
   ```
5. Remove **every** mission worktree and delete the whole branch family; delete
   remote branches only after the whole stack is in. Re-run `git worktree list`
   afterwards and confirm none of the mission's entries survive — a stranded
   worktree silently blocks the next mission from reusing the branch name, and
   the pruning is what the singular phrasing here used to miss.
6. Report the decommission in your final summary: which worktrees were removed,
   which branches deleted, state externalized where.

## Standing rules (both directions)

- **Migrations ship before the code that needs them.** If the repo
  auto-deploys its default branch (Vercel-style), merge-to-default IS the
  production rollout — there is no later "rollout step." Apply additive
  migrations (new nullable columns/tables) to the production database, and
  run the repo's migration drift check if it has one, BEFORE merging the
  first PR that references the new schema: old code tolerates an extra
  column; new code cannot tolerate its absence. Destructive or renaming
  changes go expand → migrate → contract across separate merges. Use the
  repo's ledger-tracked migrate command, never a schema push, against
  production. (Learned when a deferred ADD COLUMN took production down for
  ~30 minutes: the code deployed on merge, the column didn't exist, and
  every request failed at its first write.)

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
- One mission per **worktree set**; never reuse a mission worktree for a
  different mission — decommission and provision fresh. Multiple worktrees
  within one mission are fine and expected for independent streams (see the
  two tiers above); what is never fine is a worktree outliving its mission.
- **Long commit messages and PR bodies go in a file**, not inline: `git commit
  -F <file>` / `gh pr --body-file <file>`. The git-destruction-guard inspects
  the Bash command text, so a message that *describes* destructive git — which
  is exactly what an incident write-up does — gets denied from a non-scratch
  cwd. Same applies to any test fixture containing those commands.
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
