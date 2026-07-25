#!/usr/bin/env bash
# Has every file this branch touched actually landed on the base branch?
#
#   ./landed.sh [branch] [base]        # defaults: current branch, origin/main
#
# Exit 0 = fully landed and safe to decommission. Exit 1 = something is unlanded.
# Prints one line per file either way.
#
# This exists as a script rather than as a snippet in the mission checklist because
# the snippet was wrong three times, each in a way that reads fine:
#
#   1. Ancestry (`branch --merged`, `git log --not <base>`) false-positives on every
#      squash-merged branch, because the squash rewrites the commit.
#   2. Plain two-dot `git diff <base> <branch>` false-positives as soon as the base
#      moves, and cannot distinguish "my work never landed" from "someone else's did".
#   3. `git rev-parse "ref:path" 2>/dev/null || echo none` — rev-parse prints its
#      ARGUMENT to stdout when the path is missing, so the value becomes the ref
#      string, not "none". Two absent files on two refs compare unequal, and every
#      DELETED file reports as unlanded forever. `--verify --quiet` is the fix.
#
# The property that actually matters: for each path the branch touched, its blob on
# the branch equals its blob on the base — with "absent" as a first-class value, so a
# deletion that landed compares equal.
set -uo pipefail

BRANCH="${1:-$(git rev-parse --abbrev-ref HEAD)}"
BASE="${2:-origin/main}"

git rev-parse --verify --quiet "$BRANCH" >/dev/null || { echo "no such branch: $BRANCH" >&2; exit 2; }
git rev-parse --verify --quiet "$BASE"   >/dev/null || { echo "no such base: $BASE"    >&2; exit 2; }

base_commit=$(git merge-base "$BASE" "$BRANCH") || exit 2

blob() { # $1=ref $2=path -> blob sha, or the literal ABSENT
  git rev-parse --verify --quiet "$1:$2" || echo ABSENT
}

unlanded=0
touched=0
while IFS= read -r f; do
  [ -n "$f" ] || continue
  touched=$((touched + 1))
  if [ "$(blob "$BRANCH" "$f")" = "$(blob "$BASE" "$f")" ]; then
    echo "landed:   $f"
  else
    echo "UNLANDED: $f"
    unlanded=$((unlanded + 1))
  fi
done < <(git diff --name-only "$base_commit" "$BRANCH")

if [ "$touched" -eq 0 ]; then
  # An ancestor branch touches nothing relative to the merge base. Correct, but it
  # looks identical to a check that silently did nothing — so say which it was.
  echo "no files differ from the merge base — $BRANCH is contained in $BASE"
fi

if [ "$unlanded" -eq 0 ]; then
  echo "OK: $touched file(s) checked, all landed on $BASE"
  exit 0
fi
echo "STOP: $unlanded of $touched file(s) not on $BASE — do not decommission"
exit 1
