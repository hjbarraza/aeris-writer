#!/bin/sh
# Progress + validation for the development plan (docs/PLAN.md).
# Usage: scripts/status.sh          -> progress table + run the always-green gates
#        scripts/status.sh --no-build -> progress table only
set -e
cd "$(dirname "$0")/.."

printf '%-10s %5s %5s  %s\n' MILESTONE DONE TOTAL NEXT
for n in 1 1.5 2 3 4.5 4 5 6; do f=docs/TICKETS-M$n.md
  name=$(basename "$f" .md | sed 's/TICKETS-//')
  done_n=$(grep -c '^- \[x\]' "$f" || true)
  total=$(grep -c '^- \[[ x]\]' "$f" || true)
  next=$(grep -m1 '^- \[ \]' "$f" | sed -E 's/^- \[ \] \*\*([^—]*) —.*/\1/' | sed 's/ *$//')
  printf '%-10s %5s %5s  %s\n' "$name" "$done_n" "$total" "${next:-complete}"
done

[ "$1" = "--no-build" ] && exit 0
echo
echo "== gates =="
swift build 2>&1 | grep -E 'error|Compiling|Build complete' | tail -1
swift run mdcheck 2>&1 | tail -1
