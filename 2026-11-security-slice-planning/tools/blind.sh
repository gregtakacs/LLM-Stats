#!/usr/bin/env bash
# Blind two plans for scoring: copy them to OUT/X and OUT/Y with their file prefixes renamed to
# "plan-", then list lines that may reveal the author, for the human to reword by hand.
#
# usage: blind.sh PLAN_X_DIR PREFIX_X PLAN_Y_DIR PREFIX_Y OUT_DIR
#   e.g. blind.sh plans/local h3w- plans/frontier h3- /tmp/blind
# Which plan you pass as X is your secret; keep that mapping away from the scorers.
set -euo pipefail
[ $# -eq 5 ] || { sed -n '2,7p' "$0"; exit 2; }
x_dir=$1 x_pre=$2 y_dir=$3 y_pre=$4 out=$5
rm -rf "$out"; mkdir -p "$out/X" "$out/Y"

copy() {  # src_dir prefix dest_dir
  local src=$1 pre=$2 dest=$3 f base
  for f in "$src"/*; do
    [ -f "$f" ] || continue
    base=$(basename "$f")
    sed "s/${pre}/plan-/g" "$f" > "$dest/${base/#$pre/plan-}"
  done
}
copy "$x_dir" "$x_pre" "$out/X"
copy "$y_dir" "$y_pre" "$out/Y"

# Words that tend to give the author away. Extend with your own model and harness names.
hints='\b(lead|slice lead|local worker|the worker|local model|frontier|orchestrator|delegate-lead|sub-agent|subagent)\b'
echo "== lines that may reveal an author (reword by hand, then re-run this grep):"
grep -rniE "$hints" "$out" || echo "(none)"
echo "== blinded plans in $out/X and $out/Y"
