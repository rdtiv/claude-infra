<!--
  Retirement manifest — the single source of truth for artifacts this repo used to
  install and no longer does. Read by install.sh (user scope) and sync-repo.sh
  (repo scope); both delete exactly these paths and nothing else.

  WHY A LIST AND NOT "anything I don't recognise":
  An earlier revision retired any downstream file with no counterpart in this repo.
  That deletes repo-OWNED artifacts — a repo's own hook, its own slash commands —
  which is the opposite of the ownership split the sync tool exists to respect, and
  unrecoverable where .claude/ is gitignored. Absence is not evidence of retirement.

  WHEN YOU DELETE A FILE FROM hooks/ OR commands/, ADD IT HERE.
  verify.sh compares this list against the files your branch deletes and fails if
  one is missing, so the omission cannot ship silently.

  Format: one repo-relative path per line. Blank lines and <!-- --> comments ignored.
-->

hooks/session-protocol.sh
commands/orchestrate.md
