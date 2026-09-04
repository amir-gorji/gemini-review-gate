#!/usr/bin/env bash
# Capture one calibration case from a defect planted in the working tree.
#
#   scripts/capture-case.sh reject-tenant-filter-dropped src/route.ts src/route.test.ts
#
# Runs `git diff -M -U10` on the named files (the same flags the action uses,
# so the case replays in the live shape), writes calibration/<name>.diff, and
# checks the files out again so the plant never reaches a commit. The name
# must start with `reject-` or `approve-`: that prefix is the expected verdict.
set -euo pipefail

name="${1:?usage: capture-case.sh <reject-name|approve-name> <file>...}"
shift
[ "$#" -gt 0 ] || { echo "name at least one changed file" >&2; exit 2; }
case "$name" in
  reject-*|approve-*) ;;
  *) echo "the name must start with reject- or approve-: $name" >&2; exit 2 ;;
esac

dir="${CALIBRATION_DIR:-calibration}"
mkdir -p "$dir"
out="$dir/$name.diff"

git diff -M -U10 -- "$@" > "$out"
if [ ! -s "$out" ]; then
  rm -f "$out"
  echo "no diff in the named files; plant the defect first" >&2
  exit 1
fi
git checkout -- "$@"
echo "$out ($(wc -c < "$out" | tr -d ' ') bytes); working tree restored"
