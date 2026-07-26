<!--
  Retirement manifest — the single source of truth for artifacts this repo used to
  install and no longer does. Read by install.sh (user scope) and sync-repo.sh
  (repo scope); both delete exactly these paths and nothing else.

  WHY A LIST AND NOT "anything I don't recognise":
  An earlier revision retired any downstream file with no counterpart in this repo.
  That deletes repo-OWNED artifacts — a repo's own hook, its own slash commands —
  which is the opposite of the ownership split the sync tool exists to respect, and
  unrecoverable where .claude/ is gitignored. Absence is not evidence of retirement.

  WHEN YOU DELETE A FILE FROM hooks/, commands/, scripts/ OR workflows/, ADD IT HERE.
  verify.sh compares this list against the files your branch deletes and fails if
  one is missing, so the omission cannot ship silently.

  ONLY paths this repo actually installs belong here. A file some downstream repo
  authored for itself is not ours to retire, even when it sits at a path we would
  otherwise write — listing it would turn this manifest into the very "delete what
  I don't recognise" behaviour the paragraph above exists to prevent.

  Format: one repo-relative path per line. Blank lines and <!-- --> comments ignored.
-->

hooks/session-protocol.sh
commands/orchestrate.md
