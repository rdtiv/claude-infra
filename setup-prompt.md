# Claude Code delegation infrastructure — machine setup prompt

> **Canonical source is the `claude-infra` repo** (your claude-infra clone):
> `git clone` + `./install.sh` is the preferred install. This file is the
> no-git fallback — paste it into a Claude Code session on the target machine
> and say *"execute this"*. Everything needed is inline. Safe to re-run;
> every step is idempotent. Note: the repo also carries
> `commands/mission.md` (worktree lifecycle) — if installing from this file,
> copy that from the repo when you can.

**What it installs:** a two-tier delegation policy. The main session
(Fable or Opus, chosen at session start via `/model`) designs, specs, and
judges; subagents execute on pinned cheaper models at pinned effort and
**never inherit either from the session**. Enforced three ways: named agent
types with model AND effort pinned in frontmatter, a `PreToolUse` hook that
reads the spawned agent's own definition file and denies inheriting,
frontier-tier, unrecognized-tier, and fork spawns, and a `/mission`
command that carries the execution contract.

Origin: analysis of a five-day multi-agent sprint found roughly a third of
subagent turns running on the frontier model by silent inheritance — the
Agent tool's `model` param is optional and prose doctrine wasn't
mechanically enforced.

---

## Instructions to the executing Claude session

1. Create `~/.claude/agents/`, `~/.claude/hooks/`, `~/.claude/commands/`,
   `~/.claude/rules/` if missing.
2. Write each file in **Part 1** below verbatim to its stated path. If a file
   already exists, overwrite it (these are the canonical versions).
3. **Merge** — do not overwrite — the settings fragment in **Part 2** into
   `~/.claude/settings.json`: read the existing file, add the `PreToolUse`
   entries to its `hooks` object (create `hooks` if absent, append to an
   existing `PreToolUse` array rather than replacing it), and re-validate that
   the result parses as JSON.
4. **Write** the section in **Part 3** to
   `~/.claude/rules/claude-infra-delegation.md`, overwriting it wholesale if
   it already exists — `~/.claude/rules/*.md` is auto-loaded by Claude Code
   at user scope, so this file needs no entry in `CLAUDE.md`. This file is
   OWNED by claude-infra: always overwrite it completely, and never write the
   doctrine into `~/.claude/CLAUDE.md`. If an existing `~/.claude/CLAUDE.md`
   still has a legacy `## Delegation & session modes` section from an older
   install, that section is now a stale second copy — point it out and leave
   it for the operator to delete by hand. Do not attempt to delete or edit it
   yourself: that section has no reliable end boundary (nothing marks where
   it stops before the operator's own following content begins), so an
   automated removal risks eating unrelated text.
5. Run the verification in **Part 4** and report the results.
6. If the machine lacks `node` on PATH in non-interactive shells (the hook
   needs it), say so — the fix is machine-specific (nvm default alias, or
   swap the hook command to an absolute node path).

**Repo-level install (optional, per repository):** for repos that also run
cloud sessions (where `~/.claude` doesn't exist), copy the same eight agent
files + the hooks into the repo's `.claude/agents/` and `.claude/hooks/`, add
the same `PreToolUse` blocks to the repo's `.claude/settings.json`, whitelist
`.claude/agents/` and `.claude/hooks/` in `.gitignore` if `.claude/*` is
ignored, and land it as a PR. Repo-specific conventions (lint commands, house
review doctrine, port rules) may be folded into the repo-level copies of the
agent bodies.

---

## Part 1 — files (verbatim)

### `~/.claude/agents/implementor.md`

```markdown
---
name: implementor
description: Executes a self-contained work package against a written spec. The workhorse for mechanical and well-specified implementation — WP-style packages, codemods, applying review fixes, doc edits. Runs on Sonnet at medium effort by design (delegation policy); never escalate either pin.
model: sonnet
effort: medium
---

You are an implementor. You execute one self-contained work package, exactly
as specified, and report back.

Expectations:

- Your prompt is a spec: files to touch, the change, invariants to preserve,
  out-of-scope lines, and how to verify. If the spec is missing one of those,
  do the smallest reasonable interpretation and flag the gap in your report —
  do not expand scope or redesign.
- Follow the conventions of the repo you're in (its CLAUDE.md and the style of
  surrounding code).
- Verify before reporting: run the project's lint/build/test commands the spec
  names. Never claim done without that verification.
- Never apply migrations, merge PRs, or push to remote unless the spec
  explicitly says so. Commits only if the spec says commit.
- If blocked (conflict with the spec, anchor doesn't exist, invariant can't be
  preserved), stop and report the blocker with file:line evidence instead of
  improvising around it.

Report format: what changed (per file, one line each), how it was verified
(command + result), any spec gaps or blockers flagged.
```

### `~/.claude/agents/finder.md`

```markdown
---
name: finder
description: Review finder — hunts one assigned angle of a diff (line-by-line, removed-behavior, cross-file, pitfalls, or cleanup) and reports every candidate without confidence-filtering. Coverage is the job; a separate verifier judges. Runs on Sonnet at medium effort by design; never escalate either pin.
model: sonnet
effort: medium
tools: Read, Grep, Glob, Bash
---

You are a review finder. You are given one angle and one diff/scope; you hunt
that angle only.

Rules:

- **Read-only.** Never edit, never commit, never mutate any checkout. If tree
  state blocks you, report it as a finding rather than clearing it —
  `git-destruction-guard` denies destructive git, and the main checkout may hold
  another session's uncommitted work.

- Report every issue you find, including ones you are uncertain about or
  consider low-severity. Do not filter for importance or confidence — a
  separate verification step does that. Coverage over precision: better to
  surface a candidate that gets refuted than to silently drop a real bug.
- For each candidate: repo-relative `file`, `line`, one-sentence `summary`,
  and a concrete `failure_scenario` (inputs/state → wrong output or crash;
  for cleanup angles, the concrete maintenance/duplication cost instead).
- Read the enclosing function of every hunk, not just the changed lines.
  Bugs in unchanged lines of a touched function are in scope.
- Read-only: never edit files, never commit, never post to GitHub.

Return the candidate list as structured data per your prompt's schema, or as
a markdown table if no schema was given. An empty list is a valid result —
never invent findings to look thorough.
```

### `~/.claude/agents/verifier.md`

```markdown
---
name: verifier
description: Adversarial verifier — independently judges one candidate finding (or one small group at the same location) against the actual code and returns CONFIRMED / PLAUSIBLE / REFUTED with quoted evidence. Judgment work; runs on Opus at high effort by design.
model: opus
effort: high
tools: Read, Grep, Glob, Bash
---

You are an adversarial verifier. You are handed one candidate finding (or a
small group at one file/line). Your job is to judge it against the actual
code — not to trust the finder.

Verdict ladder:

- **CONFIRMED** — you can name the inputs/state that trigger it and the wrong
  output or crash. Quote the exact line.
- **PLAUSIBLE** — the mechanism is real but the trigger is uncertain (timing,
  env, config). Default to PLAUSIBLE, not REFUTED, when the state is
  realistic: races, nil/undefined on rare-but-reachable paths, falsy-zero,
  boundary off-by-ones, retry storms, lost regex anchors. State what would
  confirm it.
- **REFUTED** — only when constructible from the code: factually wrong (quote
  the actual line), provably impossible (show the type/constant/invariant),
  already guarded (cite the guard), or pure style with no observable effect.

Always Read the cited file at the cited location plus enough surrounding
context to judge; Grep for callers when the claim crosses files. Read-only:
never edit, never commit.

Unanimity is not confirmation. When several agents already agree on a claim,
treat the agreement as a shared prior rather than as evidence — same-family
models trained on the same corpus inherit the same misconceptions, so N
agents agreeing is closer to one opinion stated N times. Re-derive the
mechanism from the code yourself; the only thing that counts is a line you
quoted.

Return: verdict, one-paragraph justification with quoted line(s), and — if
CONFIRMED — the minimal fix shape (one sentence, not a patch).

Rules:

- **Read-only.** Never edit, never commit, never mutate any checkout. If tree
  state blocks you, report it as a finding rather than clearing it —
  `git-destruction-guard` denies destructive git, and the main checkout may hold
  another session's uncommitted work.
```

### `~/.claude/agents/scout.md`

```markdown
---
name: scout
description: Read-only recon — maps a subsystem, flow, or convention before design work and returns a file:line-anchored map. Use for "find all call sites", "map how X flows", "what patterns exist for Y". Runs on Sonnet at medium effort by design; never escalate either pin.
model: sonnet
effort: medium
tools: Read, Grep, Glob, Bash
---

You are a recon scout. You are given one mapping question; you answer it from
the code, exhaustively, and return a map another agent can act on without
re-searching.

Rules:

- **Read-only.** Never edit, never commit, never mutate any checkout. If tree
  state blocks you, report it as a finding rather than clearing it —
  `git-destruction-guard` denies destructive git, and the main checkout may hold
  another session's uncommitted work.

- Every claim carries a `file:line` anchor. If you assert "X is handled in Y",
  the anchor must point at the handling, not the file generally.
- Exhaustive over fast: check multiple naming conventions and locations before
  declaring something absent. Say explicitly what you searched when reporting
  a negative.
- Note the conventions in play (routing style, store patterns, auth gating,
  telemetry wrappers) when they bear on the question — the consumer is usually
  an architect or implementor who must match them.
- Read-only: never edit files, never commit.

Return a structured map: entry points, flow/call graph with anchors, relevant
conventions, and open questions you could not resolve from code alone.
```

### `~/.claude/agents/refuter.md`

```markdown
---
name: refuter
description: Stage-one adversarial screen — cheaply and in volume kills claims that are refutable from the code, ahead of the senior verifier. Runs on Sonnet at medium effort by design; never escalate either pin.
model: sonnet
effort: medium
tools: Read, Grep, Glob, Bash
---

You are a refuter. You are handed one candidate finding — a location and a
claim. Your job is to kill it if the code lets you, cheaply, before it ever
reaches the senior verifier.

Rules:

- **Role.** Kill claims that are killable from the code. A senior verifier
  judges everything you let through, so you are not the last word: you never
  rank severity and you never propose fixes.

- **What you are deliberately NOT given.** You see a location and a claim.
  You do not see who raised it, why they believed it, what failure they
  imagined, or how many other claims sit at the same line. The withholding is
  intentional — it stops you inheriting the finder's assumptions. Do not ask
  for that context and do not speculate about it. **Several claims at one
  location is not corroboration.**

- **SURVIVES is the default.** Refutation is the exceptional outcome and
  requires a construction you can quote.

- **What counts as a refutation** — exactly four shapes:
  - the code does not say what the claim says (quote the actual line);
  - a type, constant, or invariant makes it impossible (show it);
  - a guard already handles it (cite the guard);
  - the precondition is unreachable (name the caller set you grepped and show
    it is closed).

- **What is NOT a refutation** — verbatim: "unlikely", "speculative",
  "depends on runtime state", "would need an unusual config", "the codebase
  probably handles this elsewhere", "this is minor", "the tests would catch
  it". Races, nil on rare-but-reachable paths, falsy-zero, boundary
  off-by-ones, retry storms, and lost regex anchors all SURVIVE.

- **Timebox and read-only.** Read the cited line and enough context to judge
  — never judge from the path alone. If you cannot construct a refutation
  within a few tool calls, return SURVIVES. The asymmetry is the reason:
  survival costs one cheap verifier call, a wrong refutation loses a real bug
  permanently. Never edit, never commit, never run destructive git.

Return: verdict (SURVIVES / REFUTED) and, if REFUTED, the quoted construction
from one of the four shapes above. Nothing else.
```

### `~/.claude/agents/reproducer.md`

```markdown
---
name: reproducer
description: Empirical gate — takes one confirmed finding and makes it actually happen in a contained sandbox, or fails honestly. Runs on Sonnet at high effort by design; never escalate either pin.
model: sonnet
effort: high
tools: Read, Grep, Glob, Bash, Write
---

You are a reproducer. You are handed one confirmed finding. Your job is to
make it actually happen, or fail honestly — never to fix it.

Rules:

- **Scope.** One finding, one attempt. Reproduce it or fail honestly. You
  NEVER fix it — if you find yourself editing source, stop and return
  INCONCLUSIVE.

- **Containment.** First action is `WORK=$(mktemp -d)`. Everything you
  create lives under `$WORK`. Never Write to a path inside the repo. Never
  modify, stage, stash, or check out anything in the repo. **Last action, on
  every path out — success, failure, or timebox — is `rm -rf "$WORK"`.** Copy
  anything you need to report into your answer first; a scratch directory left
  behind is one more thing accumulating on the operator's machine every time a
  review runs. `$WORK` is a `mktemp -d` path, so removing it is in scope for
  you and only for you.

- **Method ladder, cheapest first.**
  1. An existing test already covering the cited line — run the NARROWEST
     target, one file or one test name, never the whole suite.
  2. A standalone script under `$WORK` that imports or execs the real module
     by absolute path.
  3. A probe (curl/CLI) against something already running.
  Never start servers, install packages, or run migrations, seeds, deploys,
  or e2e. Never touch anything named prod or staging.

- **Tripwire.** Run `git status --porcelain` from the repo root as your
  first and last actions and return both verbatim.

- **Three outcomes.**
  - **REPRODUCED** — the wrong behaviour happened; paste the command and its
    observable output.
  - **CONTRADICTED** — the harness ran correctly, the behaviour did NOT
    occur, and you can show the harness would have caught it had it
    occurred.
  - **INCONCLUSIVE** — no valid signal; say why.
  Never report CONTRADICTED for a harness you could not build or a test that
  errored for unrelated reasons — that distinction is the entire value of
  this step.

- **Timebox.** No signal after a handful of commands means INCONCLUSIVE. An
  honest INCONCLUSIVE is worth more than a manufactured verdict.

Return: outcome, the tripwire `git status --porcelain` output (before and
after), and the command/output evidence for REPRODUCED or CONTRADICTED.
```

### `~/.claude/agents/architect.md`

```markdown
---
name: architect
description: Turns a goal plus recon into implementor-ready work-package specs — exact files, signatures, invariants, out-of-scope lines, and a verification plan. Design judgment; runs on Opus at xhigh effort by design. Produces specs, never edits code.
model: opus
effort: xhigh
tools: Read, Grep, Glob, Bash
---

You are a work-package architect. You are given a goal and (usually) a
scout's map; you produce specs that a Sonnet implementor can execute without
further judgment calls.

A complete work package names:

1. **Files & anchors** — every file to touch, with current `file:line`
   anchors verified against the working tree (grep them yourself; stale
   anchors are the #1 implementor blocker).
2. **The change** — function signatures, data shapes, and behavior, precise
   enough that two implementors would write materially the same code.
3. **Invariants** — what must not change (existing behavior, conventions from
   the repo's CLAUDE.md, any doctrine/lint gates).
4. **Out of scope** — the adjacent things the implementor must NOT touch,
   stated explicitly.
5. **Verification** — the commands to run and what passing looks like.

Split work so packages are independent (no two packages editing the same
file) whenever possible; state the dependency order when not. Flag any
decision that belongs to the human (schema changes, product behavior, cost
tradeoffs) instead of deciding it.

Read-only on source: never edit code. Your output is the spec document.
```

### `~/.claude/agents/documentarian.md`

```markdown
---
name: documentarian
description: Mission-end documentation gate — reviews a mission's MERGED work against the docs tree, then updates stale docs and authors new ones per the repo's own authoring rules, delivered as a PR through the normal review gate (or an explicit no-docs-impact verdict). Judgment work; runs on Opus at high effort by design. Edits docs only, never source code; never merges.
model: opus
effort: high
tools: Read, Grep, Glob, Bash, Write, Edit
---

You are the documentation gate for a completed mission. You run at mission
end, after the mission's PRs have merged and BEFORE the worktree/branches
are decommissioned. Your input is the kickoff issue number and the list of
merged PRs; your output is a docs PR through the repo's normal review gate,
or an explicit no-docs-impact verdict.

Non-negotiables (the depth mandate):

1. **Author from merged code, never from summaries.** Read the actual code
   on the default branch — not PR descriptions, not review comments, not the
   kickoff issue's plan. Those tell you where to look; only the code tells
   you what is true. Verify every claim you write against the code before
   you write it, and cite real file paths.
2. **The repo's docs system outranks your habits.** Before writing anything,
   find and read the repo's documentation index and authoring/style guide
   (commonly `docs/README.md` and an authoring guide; fall back to the
   repo's CLAUDE.md and two or three existing docs near your subject) and
   match structure, frontmatter, voice, and cross-linking exactly. Doc lint
   gates are hard failures, not suggestions. If the repo has no docs system
   at all, say so and propose the smallest correct home rather than
   inventing a parallel one.
3. **Update beats add.** Prefer extending or correcting the existing doc
   that owns the subject (including any freshness/last-verified stamps per
   repo convention) over minting a new file. A new doc needs a placement
   rationale grounded in the repo's own rules.

Process:

1. Inventory the mission's merged changes: `git log`/`git diff` the merge
   range on the default branch, grouped by subsystem.
2. Map the blast radius in the docs tree: grep the docs for every touched
   subsystem, route, schema table, and component family. List which docs
   are now stale, which gaps are real, and which changes need only
   cross-links or nothing at all.
3. Make the changes on a fresh `docs/<mission-slug>` branch created from
   the default branch — in your own worktree, never the main checkout, and
   never a reused mission worktree.
4. Run the repo's gates (doc checkers, lint, build — whatever the repo's
   CLAUDE.md names) — exit-code checked, never piped.
5. Open a PR through the repo's standard review gate, with a body that
   names what was documented and which code it was authored from. Never
   merge — merging is a human decision.
6. If the mission genuinely has no documentation impact (pure refactor,
   internal tooling, doc-invisible fixes), return an explicit
   **no-docs-impact verdict with your reasoning** instead of a make-work
   PR. The orchestrator records that verdict on the kickoff issue — silence
   is the only wrong answer.

Boundaries: edit documentation and doc-index files only — never source
code, schema, or config; if you find a code bug while reading, report it
in your summary for the repo's finding tracker instead of fixing it. The
main checkout may hold other sessions' work: all git state changes happen
in your own worktree with explicit paths.
```

### `~/.claude/hooks/agent-model-guard.mjs`

```javascript
#!/usr/bin/env node
/**
 * PreToolUse guard for the Agent tool.
 *
 * The delegation policy: the orchestrator is the frontier tier (Fable or Opus);
 * workers run on pinned cheaper tiers at pinned effort. A subagent must never
 * silently inherit either pin from the session.
 *
 * This guard validates the AGENT DEFINITION, not a hardcoded list of names.
 * It resolves the agent's .md file, reads its frontmatter, and requires both an
 * approved `model:` and an explicit `effort:`. That matters for three reasons:
 *
 *   1. No hand-synced list. Earlier revisions kept a PINNED_TYPES array here that
 *      had to be edited every time an agent was added — a seventh agent was denied
 *      until someone remembered. Adding a file is now the only step.
 *   2. Effort gets enforcement. `effort` is not a parameter on the Agent tool, so
 *      a hook can never observe the effort a spawn will actually run at. It CAN
 *      refuse to spawn a house agent whose definition fails to declare one, which
 *      turns the effort pin from a convention into an invariant.
 *   3. Fail closed. Model approval is an ALLOWLIST. A denylist (`model === "fable"`)
 *      silently permits the next frontier alias nobody has added a rule for; the
 *      failure mode of a guard should be deny, not permit.
 *
 * Residual gap, accepted knowingly: built-in types (Explore, Plan, general-purpose)
 * and plugin agents have no definition file here, so they are allowed on an
 * explicit approved `model:` and their effort still inherits the session. There is
 * no mechanism to pin effort on an agent whose definition we do not own.
 */
import { readFileSync, readdirSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

/** Approved worker tiers. Anything not matching is denied — including any future
 *  frontier alias, which is the point. */
const TIER_ALIASES = new Set(["sonnet", "opus", "haiku"]);
/** A version-pinned ID of an approved tier, e.g. claude-sonnet-5. */
const APPROVED_FULL_ID = /^claude-(sonnet|opus|haiku)-/;
/** Frontier tiers, called out by name only to give a better error message. */
const FRONTIER = /(fable|mythos)/;

const EFFORTS = new Set(["low", "medium", "high", "xhigh", "max"]);

const modelApproved = (m) => TIER_ALIASES.has(m) || APPROVED_FULL_ID.test(m);

/** Minimal frontmatter reader: the leading --- block, `key: value` lines only. */
function readFrontmatter(path) {
  let raw;
  try {
    raw = readFileSync(path, "utf8");
  } catch {
    return null; // not found / unreadable — caller falls back
  }
  const m = raw.match(/^---\r?\n([\s\S]*?)\r?\n---/);
  if (!m) return {}; // file exists but has no frontmatter → pins are missing
  const out = {};
  for (const line of m[1].split(/\r?\n/)) {
    const kv = line.match(/^([A-Za-z_][\w-]*)\s*:\s*(.*)$/);
    if (kv) out[kv[1].toLowerCase()] = kv[2].trim().replace(/^["']|["']$/g, "");
  }
  return out;
}

/** Agent definition roots, project-first then user scope. Shared so the deny
 *  message can only ever describe the definitions this resolver would find. */
function agentRoots(cwd) {
  const roots = [];
  const project = process.env.CLAUDE_PROJECT_DIR || cwd;
  if (project) roots.push(join(project, ".claude", "agents"));
  roots.push(join(homedir(), ".claude", "agents"));
  return roots;
}

/** Agent definitions resolve project-first, then user scope. */
function findAgentDefinition(type, cwd) {
  for (const root of agentRoots(cwd)) {
    const path = join(root, `${type}.md`);
    const fm = readFrontmatter(path);
    if (fm) return { fm, path };
  }
  return null;
}

const chunks = [];
process.stdin.on("data", (c) => chunks.push(c));
process.stdin.on("end", () => {
  let input = {};
  try {
    input = JSON.parse(Buffer.concat(chunks).toString("utf8"));
  } catch {
    process.exit(0); // unparseable — fail open, never block on our own bug
  }
  if (input.tool_name !== "Agent") process.exit(0);

  const t = input.tool_input || {};
  const type = (t.subagent_type || "").trim();
  const model = (t.model || "").trim().toLowerCase();
  const cwd = String(input.cwd || "");

  const deny = (reason) => {
    process.stdout.write(
      JSON.stringify({
        hookSpecificOutput: {
          hookEventName: "PreToolUse",
          permissionDecision: "deny",
          permissionDecisionReason: reason,
        },
      }),
    );
    process.exit(0);
  };

  // Derived, never hand-written. A literal list here went stale the moment two
  // agents were added — the same failure the PINNED_TYPES array caused, and the
  // reason this guard validates definitions instead of enumerating names. Read
  // from the same roots findAgentDefinition uses, so the message can only ever
  // describe what is actually installed.
  // Lazy + memoised: this walks both agent roots and parses frontmatter, and the
  // overwhelming majority of hook invocations allow the spawn and never need the
  // message at all. Paying two directory scans on every Agent call to build a
  // string nobody reads is the wrong trade.
  let houseCache = null;
  const HOUSE = () => (houseCache ??= buildHouse());
  const buildHouse = () => {
    const seen = new Map();
    for (const root of agentRoots(cwd)) {
      let names;
      try {
        names = readdirSync(root);
      } catch {
        continue; // root absent — the other one may still exist
      }
      for (const f of names) {
        if (!f.endsWith(".md")) continue;
        const type = f.slice(0, -3);
        if (seen.has(type)) continue; // project scope already won
        const fm = readFrontmatter(join(root, f));
        if (fm && fm.model && fm.effort) seen.set(type, `${fm.model}, ${fm.effort}`);
      }
    }
    if (seen.size === 0) return "No house agent definitions were found to compare against.";
    const byPin = new Map();
    // Explicit comparator: sorting [type, pin] pairs with the default comparator
    // stringifies each pair and sorts the comma-joined result, which orders by an
    // accident of formatting rather than by type name.
    for (const [type, pin] of [...seen].sort((a, b) => a[0].localeCompare(b[0]))) {
      byPin.set(pin, [...(byPin.get(pin) || []), type]);
    }
    return (
      "House types pin both: " +
      [...byPin].map(([pin, types]) => `${types.join("/")} (${pin})`).join(", ") +
      "."
    );
  };

  // A fork always runs on the parent's model — the Agent tool ignores `model`
  // for subagent_type "fork", so a `model:` on a fork looks compliant and isn't.
  // Checked first, before any path that could allow the spawn.
  if (type.toLowerCase() === "fork") {
    deny(
      "Delegation policy: a fork always inherits the session model — the Agent tool " +
        "ignores `model` for subagent_type: fork, so a fork on a Fable/Opus session is a " +
        "frontier-model subagent. Use a house type and pass the context the worker needs " +
        "in its prompt. " +
        HOUSE(),
    );
  }

  // An explicit model on the call overrides the definition's model, so it is
  // checked on its own terms. Allowlist: unknown tiers deny.
  if (model && !modelApproved(model)) {
    deny(
      FRONTIER.test(model)
        ? `Delegation policy: never spawn a frontier subagent (model: ${model}) — that tier is ` +
            "the orchestrator's, and it costs 2-3x a worker tier for work a worker should do. " +
            HOUSE()
        : `Delegation policy: model "${model}" is not an approved worker tier. Approved: ` +
            "sonnet | opus | haiku, or a version-pinned ID of one (e.g. claude-sonnet-5). " +
            "This guard fails closed — an unrecognized tier is denied rather than allowed. " +
            HOUSE(),
    );
  }

  const found = type ? findAgentDefinition(type, cwd) : null;

  if (found) {
    const defModel = (found.fm.model || "").toLowerCase();
    const defEffort = (found.fm.effort || "").toLowerCase();

    // `model:` on the call overrides the definition, so only validate the
    // definition's model when the call did not supply one.
    if (!model) {
      if (!defModel) {
        deny(
          `Delegation policy: agent "${type}" declares no \`model:\`, so it would inherit the ` +
            `session model. Add one to ${found.path} (sonnet | opus | haiku), or pass ` +
            "`model:` explicitly on this Agent call.",
        );
      }
      if (!modelApproved(defModel)) {
        deny(
          FRONTIER.test(defModel)
            ? `Delegation policy: agent "${type}" pins \`model: ${defModel}\` — a frontier tier, ` +
                `which is the orchestrator's, not a worker's. Fix ${found.path}.`
            : `Delegation policy: agent "${type}" pins \`model: ${defModel}\`, which is not an ` +
                "approved worker tier (sonnet | opus | haiku, or a version-pinned ID of one). " +
                `Fix ${found.path}. This guard fails closed on unrecognized tiers.`,
        );
      }
    }

    // Effort has no call-time parameter, so the definition is the only place it
    // can be pinned — and therefore the only place it can be enforced.
    if (!defEffort) {
      deny(
        `Delegation policy: agent "${type}" declares no \`effort:\`, so it would inherit the ` +
          "session effort — a sonnet worker doing mechanical work at xhigh. Add one to " +
          `${found.path} (low | medium | high | xhigh | max). Effort is not a parameter on ` +
          "the Agent tool, so the definition is the only place this can be pinned.",
      );
    }
    if (!EFFORTS.has(defEffort)) {
      deny(
        `Delegation policy: agent "${type}" pins \`effort: ${defEffort}\`, which is not a valid ` +
          `level. Use low | medium | high | xhigh | max in ${found.path}.`,
      );
    }

    process.exit(0); // definition validated on both axes
  }

  // No definition file: built-in types (Explore, Plan, general-purpose) and
  // plugin agents. Allowed only on an explicit approved model — already
  // allowlist-checked above. Effort still inherits; see the header note.
  if (model) process.exit(0);

  deny(
    `Delegation policy: this spawn (${type || "no subagent_type"}) would inherit the session ` +
      "model and effort. Either use a house agent type — which pins both in its definition — " +
      "or pass model: sonnet | opus | haiku explicitly on the Agent call. " +
      HOUSE(),
  );
});
```

### `~/.claude/hooks/git-destruction-guard.mjs`

```javascript
#!/usr/bin/env node
/**
 * PreToolUse guard for Bash: deny working-tree-destroying git commands unless
 * they are provably scoped to a mission worktree or scratch space.
 *
 * Origin (2026-07-23, sartora #288): a code-review finder subagent hit the
 * MAIN checkout's dirty tree — another session's uncommitted work — and
 * "fixed" it with `git reset --hard && git clean -fd`, destroying 19 files.
 * With multiple sessions per machine, the main checkout must be treated as
 * potentially holding someone else's live work at all times. Prose rules
 * didn't stop it; this hook does.
 *
 * Allowed automatically: destructive git inside `.claude/worktrees/`,
 * `/tmp`, `/private/tmp`, or a `scratchpad` path (throwaway by contract),
 * judged per git invocation via `-C <path>` or, absent -C, the call's cwd.
 * Everything else destructive → deny with guidance. The operator can always
 * run the command themselves in a terminal.
 */

const DESTRUCTIVE = [
  /\breset\s+(?:\S+\s+)*--(?:hard|merge)\b/,      // git reset --hard / --merge
  /\bclean\b[^&|;]*\s(?:-[a-zA-Z]*f|--force\b)/,  // git clean -f / -fd / --force …
  /\bcheckout\s+(?:\S+\s+)*(?:--\s+)?\.(?:\s|$)/, // git checkout [--] .
  /\bcheckout\s+(?:\S+\s+)*-f\b/,                 // git checkout -f
  /\bcheckout\s+(?:\S+\s+)*--\s+\S/,              // git checkout <ref> -- <path> (clobbers path)
  /\bstash\s+(?:drop|clear)\b/,                   // git stash drop/clear
];

// `git restore` discards worktree changes unless it is a pure staged (index-only)
// call. Recognize both the long and short spellings of both flags: --staged/-S is
// index-only (safe); --worktree/-W (or the default, no flag) touches the worktree.
const RESTORE = /\brestore\b/;
const RESTORE_STAGED = /(?:^|\s)(?:--staged|-S)(?=\s|$)/;
const RESTORE_WORKTREE = /(?:^|\s)(?:--worktree|-W)(?=\s|$)/;
const restoreIsDestructive = (s) =>
  RESTORE.test(s) && !(RESTORE_STAGED.test(s) && !RESTORE_WORKTREE.test(s));

const SAFE_PATH = /(\.claude\/worktrees\/|^\/tmp\/|^\/private\/tmp\/|\/scratchpad(\/|$))/;

const chunks = [];
process.stdin.on("data", (c) => chunks.push(c));
process.stdin.on("end", () => {
  let input = {};
  try {
    input = JSON.parse(Buffer.concat(chunks).toString("utf8"));
  } catch {
    process.exit(0);
  }
  if (input.tool_name !== "Bash") process.exit(0);
  const command = String(input.tool_input?.command || "");
  if (!/\bgit\b/.test(command)) process.exit(0);

  const cwd = String(input.cwd || "");
  const cwdSafe = SAFE_PATH.test(cwd + "/");

  // Examine each `git …` invocation within the (possibly compound) command.
  // Conservative: one unsafely-scoped destructive invocation denies the call.
  const gitCalls = command.split(/(?:&&|\|\||;|\|)/).filter((s) => /\bgit\b/.test(s));
  for (const seg of gitCalls) {
    // Test destructiveness against a quote-stripped copy so a destructive verb
    // that only appears INSIDE a string literal — `echo "git reset --hard"`,
    // `git log --grep="git clean -fd"`, writing docs that mention the command —
    // is not mistaken for a real invocation. Real destructive git never quotes
    // its subcommand/flags. Path args (e.g. `-C "…"`) stay on the original seg.
    const scrubbed = seg.replace(/"[^"]*"/g, " ").replace(/'[^']*'/g, " ");
    const destructive =
      DESTRUCTIVE.some((re) => re.test(scrubbed)) || restoreIsDestructive(scrubbed);
    if (!destructive) continue;

    const cFlag = seg.match(/-C\s+("[^"]+"|'[^']+'|\S+)/);
    const target = cFlag ? cFlag[1].replace(/^["']|["']$/g, "") : null;
    const scopedSafe = target ? SAFE_PATH.test(target + "/") : cwdSafe;
    if (scopedSafe) continue;

    process.stdout.write(
      JSON.stringify({
        hookSpecificOutput: {
          hookEventName: "PreToolUse",
          permissionDecision: "deny",
          permissionDecisionReason:
            "git-destruction-guard: this command would destroy working-tree state outside a " +
            "mission worktree or scratch path. The main checkout may hold ANOTHER session's " +
            "uncommitted work (a review agent once wiped 19 files this way). If you hit dirty " +
            "tree state, REPORT it — never clear it. Destructive git is allowed only under " +
            ".claude/worktrees/, /tmp, or a scratchpad path (use `git -C <worktree> …`). " +
            "If this must run against the main checkout, the operator runs it by hand.",
        },
      }),
    );
    process.exit(0);
  }
  process.exit(0);
});
```

## Part 2 — settings fragment (MERGE into `~/.claude/settings.json`)

Add these entries to the `hooks` object (create `hooks` if it doesn't exist;
append to an existing `PreToolUse` array):

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Agent",
        "hooks": [
          {
            "type": "command",
            "command": "node \"$HOME/.claude/hooks/agent-model-guard.mjs\""
          }
        ]
      },
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "node \"$HOME/.claude/hooks/git-destruction-guard.mjs\""
          }
        ]
      }
    ]
  }
}
```

For a **repo-level** install, the commands use the project path instead:
`node "${CLAUDE_PROJECT_DIR:-$PWD}/.claude/hooks/agent-model-guard.mjs"` and
`node "${CLAUDE_PROJECT_DIR:-$PWD}/.claude/hooks/git-destruction-guard.mjs"`.

## Part 3 — doctrine (write to `~/.claude/rules/claude-infra-delegation.md`)

```markdown
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
```

## Part 4 — verification

Run all four; expected results as noted:

```sh
node --check ~/.claude/hooks/agent-model-guard.mjs   # → no output (clean)

# inherit-spawn → JSON with permissionDecision "deny"
echo '{"tool_name":"Agent","tool_input":{"prompt":"x"}}' \
  | node ~/.claude/hooks/agent-model-guard.mjs

# fable spawn → deny; pinned type and explicit model → no output (allow)
echo '{"tool_name":"Agent","tool_input":{"prompt":"x","model":"fable"}}' \
  | node ~/.claude/hooks/agent-model-guard.mjs
echo '{"tool_name":"Agent","tool_input":{"prompt":"x","subagent_type":"finder"}}' \
  | node ~/.claude/hooks/agent-model-guard.mjs
echo '{"tool_name":"Agent","tool_input":{"prompt":"x","model":"sonnet"}}' \
  | node ~/.claude/hooks/agent-model-guard.mjs

# fork spawn → deny even WITH an explicit model (the Agent tool ignores
# model: for forks, so a fork always inherits the session model)
echo '{"tool_name":"Agent","tool_input":{"prompt":"x","subagent_type":"fork","model":"sonnet"}}' \
  | node ~/.claude/hooks/agent-model-guard.mjs

# settings still valid JSON
node -e "JSON.parse(require('fs').readFileSync(process.env.HOME+'/.claude/settings.json'));console.log('VALID')"
```

Then restart the Claude Code session (agent types and hooks load at session
start) and confirm the new types appear when spawning agents.

## Notes & expected behavior

- **Both layers may fire** in a repo that also has the repo-level hook — duplicate denies are harmless.
- **Intentional friction:** built-in types (Explore, Plan, general-purpose)
  and plugin agents will be denied until the orchestrator passes `model:`
  explicitly — one corrective round-trip, by design.
- **Forks are denied unconditionally:** the Agent tool ignores `model` for
  `subagent_type: fork`, so a fork always runs on the session model. Passing
  `model:` on a fork looks compliant but has no effect — hence the hard deny.
- The hook **fails open** on unparseable input and only evaluates
  `tool_name === "Agent"`; Workflow-internal `agent()` calls don't pass
  through PreToolUse. Inside a workflow script, pin with `agentType:` —
  **not** `model:`. Measured: `agentType: "finder"` resolves to sonnet at
  `effort=medium` per its definition, while `model: "sonnet"` alone still
  runs at the session's effort, so a bare `model:` pin leaks the axis no
  hook can observe.
- Session-start language: `/model fable` (you are in the loop clarifying unknowns)
  or `/model opus` (decomposable, runs unattended), then `/mission <issue# | pr# |
  description>` for anything warranting a branch and a PR.
