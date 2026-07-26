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
        if (!fm) continue; // unreadable — a later root may still resolve it
        // Claim the type at the FIRST root whose file exists, well-pinned or not.
        // findAgentDefinition stops there too, so a later root's copy is never the
        // definition that actually gets validated. Recording only well-pinned files
        // let a home-scope definition describe a type that project scope resolves,
        // so the deny message advertised a pin the guard had not checked.
        seen.set(type, fm.model && fm.effort ? `${fm.model}, ${fm.effort}` : null);
      }
    }
    if (seen.size === 0) return "No house agent definitions were found to compare against.";
    const byPin = new Map();
    // Explicit comparator: sorting [type, pin] pairs with the default comparator
    // stringifies each pair and sorts the comma-joined result, which orders by an
    // accident of formatting rather than by type name.
    for (const [type, pin] of [...seen].sort((a, b) => a[0].localeCompare(b[0]))) {
      if (!pin) continue; // claimed above, but its definition does not pin both axes
      byPin.set(pin, [...(byPin.get(pin) || []), type]);
    }
    if (byPin.size === 0) return "No fully-pinned house agent definitions were found.";
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
