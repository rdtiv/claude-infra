---
description: Local adversarial code review on the pinned house fleet — sonnet finders, a cheap refutation screen, opus verifiers, and an optional reproduction gate. Runs before the remote reviewer, never instead of it.
---

You are running the **pinned local review** over the working diff.

Parse `$ARGUMENTS` as `<level> [target]`:

- **level** — `low` | `medium` | `high` | `xhigh` | `max`. Default `high` when the
  first token is not one of these.
- **target** — everything after the level. Optional. A PR number, a branch, a ref
  range, a path, or a free-form narrowing instruction ("only src/auth", "focus on
  the migration"). Passed through verbatim as scope guidance.
- Add the token `no-exec` anywhere in the target to disable the reproduction gate,
  which executes narrow tests and throwaway scripts.

Then invoke the workflow **by name, exactly once**:

```
Workflow({ name: "code-review-pinned", args: "<level> <target>" })
```

Do not substitute a different workflow, and do not run the review inline instead.
Naming the workflow here is the entire point of this command: the built-in
`/code-review` chooses its workflow by model judgement, which measurably picks the
wrong one, so this command removes the choice.

If the user gave scope instructions elsewhere in the conversation — files to focus
on, things to skip — append them to the args string so the workflow honours them.

The workflow runs in the background and returns verified findings as a task
notification. When they arrive:

- Present findings **most-severe first**, or say plainly that nothing survived
  verification. Do not pad a short list.
- A finding marked `empirical: reproduced` was actually made to happen — say so,
  and give it precedence. One marked `did not reproduce` was demoted rather than
  dropped; report it as unconfirmed rather than as a bug.
- Surface any `WARNING:` prefix on the summary verbatim. A tree-dirty warning or a
  control-sample disagreement means the run itself is suspect, and that matters
  more than any individual finding.
- Work the findings, not the count.

## When to run this

**Before the remote reviewer, not alongside it.** This gate is local, costs no CI
minutes, and has no round-trip. Push to a remote or CI reviewer only once this one
is clean — a finding it would have caught is a wasted remote run, and the two
reviewers working the same diff concurrently produces duplicate and conflicting
fixes on the same branch.

`/code-review` still reaches the vendor's own reviewer and is deliberately left
alone. Use it when you want a second, differently-built opinion — not as a
substitute for this one.

**One thing only this command can do.** The built-in `/code-review` is registered
`disableModelInvocation: true`, so it is user-invocable *only* — an agent that
tries to call it gets `Skill code-review cannot be used with Skill tool due to
disable-model-invocation`. This command carries no such flag, which is what makes
the "local gate before the remote gate" rule executable by an unattended mission
rather than something a human has to remember to type.

Review: $ARGUMENTS
