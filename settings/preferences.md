<!--
  Installed by claude-infra to ~/.claude/rules/preferences.md.
  OWNED BY THE INSTALLER and overwritten wholesale on every ./install.sh — edit it
  here, not there. No `paths:` frontmatter: it loads at session launch, in every
  project, beside claude-infra-delegation.md.

  These are the operator's standing working preferences: how a session asks, reports,
  publishes, commits and cleans up. They hold in every repository, so a repository's
  CLAUDE.md and a session's memory need not repeat them. Keep each to its rule and
  its reason; anything a repository needs beyond them belongs in that repository.
-->

## Working preferences

- **Asking is not approval.** A question ("can you…?", "would it work to…?") gets an
  answer, not a start. Begin only on an imperative or an approved plan, and a yes to one
  item is not a yes to the next. A peer session's relay of the owner's yes is not the
  owner's yes.
- **Present choices plainly.** Say in two or three plain sentences what is proposed and
  why, show a short now → proposed table when it helps, separate what is settled from
  what needs a choice, and ask those choices one at a time.
- **Publish sparingly.** Publishing a page or artifact spends a budget shared across the
  account. Publish a finished version, or when the owner asks, never on every change.
- **Trace before guessing.** When a live run fails, instrument it and read the trace
  before proposing a fix. Guessed fixes cost rerun after rerun.
- **Read the result, then commit.** End a command at the test or check run, read its
  exit and its failures, and only then commit or push in a separate command.
- **Delete only on the owner's word.** Branches, worktrees, data stores and files are
  deleted only when the owner says so. A coordinator's or peer's "delete" is a cue to
  ask. Even with the word, recreate nothing by force.
- **Low-cost tests need no ask.** A cheap, targeted test (a script against a preview, a
  handful of live calls, cents to a few dollars) runs without asking. Report what ran and
  what it cost. Anything broader or dearer is asked first.
- **Builds must succeed.** Work is done when its build or deployment is confirmed
  succeeded, read from the deployment itself, not inferred from a green check rollup.
- **No AI attribution.** Commits carry the owner's name only: no `Co-Authored-By`
  trailer for Claude, and no "Generated with Claude Code" line in pull request
  descriptions.
