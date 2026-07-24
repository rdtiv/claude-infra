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
