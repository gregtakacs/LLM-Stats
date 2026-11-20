#!/bin/bash
# Effort bench: replay past slices on model-medium and model-xhigh, REPS each, SLOTS at a time.
# Each run: same spec, same base commit, a verify pinned to that commit, no verify re-run.
# Results: one JSON line per run in results.jsonl (status, verify rc, wall, tokens).
set -u
B=$(cd "$(dirname "$0")" && pwd)
. "$B/verifies.sh"
REPS=${REPS:-2}; SLOTS=${SLOTS:-4}
declare -A REPO=(
  [{orb-project}-integration-4-lead-i4-6-b3-fix]=$HOME/docker/Projects/{orb-project}
  [{project}-a2x-design]=$HOME/docker/Projects/{project}
  [{project}-a2p-design]=$HOME/docker/Projects/{project}
)
declare -A SHORT=(
  [{orb-project}-integration-4-lead-i4-6-b3-fix]=b3 [{project}-a2x-design]=dx [{project}-a2p-design]=dp
)
declare -A REPS_OF=( [b3]=3 [dx]=2 [dp]=2 )
one() { # SLICE MODEL REP
  local s=$1 m=$2 r=$3 base name v img="" t0 t1 id
  base=$(awk -v s="$s" '$1==s{print $2}' "$B/bases.txt")
  name="bench2-${SHORT[$s]}-${m#model-}-$r"
  v=$(verify_for "$s" "$base")
  [ "${SHORT[$s]}" = b3 ] && img=delegate-worker:{orb-image}
  t0=$(date +%s)
  DELEGATE_IMAGE=${img:-${DELEGATE_IMAGE:-}} delegate run "$B/specs/$s.md" --repo "${REPO[$s]}" \
    --base "$base" --name "$name" --model "$m" --verify "$v" --verify-retries 0 --timeout 5400 \
    > "$B/logs/$name.log" 2>&1
  t1=$(date +%s)
  id="$(basename "${REPO[$s]}")-$name"
  python3 - "$id" "$s" "$m" "$r" "$((t1 - t0))" >> "$B/results.jsonl" <<'PY'
import json, os, sys, glob
tid, s, m, r, wall = sys.argv[1:]
d = os.path.expanduser(f"~/.local/state/delegate/{tid}/rounds/1")
rep = {}
try: rep = json.load(open(os.path.join(d, "report.json")))
except Exception as e: rep = {"error": str(e)}
keep = {k: rep.get(k) for k in ("status", "worker_status", "verify_rc", "exit", "duration_s",
        "input_tokens", "output_tokens", "reasoning_tokens", "tool_calls", "tool_errors", "tokens", "usage", "error") if k in rep}
print(json.dumps({"task": tid, "slice": s, "model": m, "rep": int(r), "wall_s": int(wall), **keep}))
PY
}
mkdir -p "$B/logs"
jobs_list=()
for r in 1 2 3; do
  for s in "${!SHORT[@]}"; do
    [ "$r" -le "${REPS_OF[${SHORT[$s]}]}" ] || continue
    for m in model-medium model-xhigh; do jobs_list+=("$s $m $r"); done
  done
done
for j in "${jobs_list[@]}"; do
  while [ "$(jobs -rp | wc -l)" -ge "$SLOTS" ]; do wait -n; done
  one $j &
  sleep 20   # stagger starts
done
wait
echo "bench done: $(wc -l < "$B/results.jsonl") runs"
