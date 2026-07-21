#!/usr/bin/env node
/**
 * PreToolUse guard for the Agent tool: subagents must never silently inherit
 * the session model (Dan's delegation policy — the orchestrator is Fable or
 * Opus; workers are pinned). A spawn is allowed when it either uses one of
 * the house agent types (which pin their model in .claude/agents/*.md
 * frontmatter) or passes an explicit non-Fable `model`.
 */
const PINNED_TYPES = new Set([
  "implementor", // sonnet — executes a work-package spec
  "finder",      // sonnet — review finder, one angle
  "verifier",    // opus   — adversarial verify one candidate
  "scout",       // sonnet — read-only recon
  "architect",   // opus   — work-package specs
]);

const chunks = [];
process.stdin.on("data", (c) => chunks.push(c));
process.stdin.on("end", () => {
  let input = {};
  try {
    input = JSON.parse(Buffer.concat(chunks).toString("utf8"));
  } catch {
    process.exit(0); // unparseable — don't block
  }
  if (input.tool_name !== "Agent") process.exit(0);

  const t = input.tool_input || {};
  const type = (t.subagent_type || "").trim();
  const model = (t.model || "").trim().toLowerCase();

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

  if (model === "fable") {
    deny(
      "Delegation policy: never spawn a Fable subagent — Fable is the orchestrator tier. " +
        "Use subagent_type implementor/finder/scout (sonnet) or verifier/architect (opus), " +
        "or pass model: sonnet | opus | haiku explicitly.",
    );
  }
  if (PINNED_TYPES.has(type)) process.exit(0); // model pinned by the agent definition
  if (model) process.exit(0); // explicit non-Fable model

  deny(
    `Delegation policy: this spawn (${type || "no subagent_type"}) would inherit the session model. ` +
      "Either use a house agent type — implementor/finder/scout (sonnet), verifier/architect (opus) — " +
      "or pass model: sonnet | opus | haiku explicitly on the Agent call.",
  );
});
