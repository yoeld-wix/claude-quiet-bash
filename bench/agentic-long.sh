#!/usr/bin/env bash
#
# Long-session agentic benchmark for quiet-bash — the FAIR test of the compounding
# claim. A short task barely exercises quiet-bash (fixed overhead dominates); the
# win is supposed to show up over many turns, because a stateless agent re-sends
# the whole transcript — including every prior command's output — on every turn.
#
# So this runs ONE long task: ~10 sequential verbose commands, each producing
# output that then rides along in context for all later turns. In baseline that
# output accumulates and is re-billed every turn; quiet-bash collapses each one.
# We measure CUMULATIVE input tokens (summed across turns) and total cost.
#
# Usage: QB_TARGET=/path/to/repo QB_MODEL=claude-haiku-4-5 QB_REPEATS=2 bench/agentic-long.sh
set -uo pipefail
ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
TARGET="${QB_TARGET:?set QB_TARGET}"
MODEL="${QB_MODEL:-claude-haiku-4-5}"
REPEATS="${QB_REPEATS:-2}"
OUT="${QB_OUT:-$ROOT/bench/agentic-long-runs.jsonl}"
: > "$OUT"

BASE_SET="$(mktemp)"; printf '{}\n' > "$BASE_SET"
QUIET_SET="$(mktemp)"
cat > "$QUIET_SET" <<JSON
{ "hooks": {
  "PreToolUse":  [ { "matcher": "Bash", "hooks": [ { "type": "command", "command": "$ROOT/adapters/claude-code.sh", "timeout": 15 } ] } ],
  "PostToolUse": [ { "matcher": "Read|mcp__.*|WebFetch|WebSearch", "hooks": [ { "type": "command", "command": "$ROOT/adapters/claude-code-result.sh", "timeout": 15 } ] } ]
} }
JSON

read -r -d '' TASK <<'TXT'
Work through these steps IN ORDER. Use the Bash tool to run each command EXACTLY as
written (do not combine, pipe, head, or optimise them), and after each command write
one short sentence about what you saw. Then do the next step. Steps:
1. git log -p -20
2. git log --stat -100
3. git diff HEAD~6 HEAD
4. git show HEAD~1
5. git log --oneline -400
6. cat packages/astra-migrations-mcp-server/src/services/pr-review.ts
7. cat packages/astra-migrations-mcp-server/src/services/local-runner.ts
8. git log -p -15
9. cat package-lock.json
10. git log --stat -60
After all 10 steps, give a 3-bullet summary of the repo's recent activity.
TXT

run_one() { # arm settings rep
  local arm="$1" set="$2" rep="$3" j
  j=$(cd "$TARGET" && timeout 900 claude -p "$TASK" \
        --model "$MODEL" --output-format json --settings "$set" \
        --allowedTools "Bash" "Read" "Grep" "Glob" --max-turns 25 2>/dev/null)
  [ -z "$j" ] && { echo "  ! ${arm} rep${rep}: no output" >&2; return; }
  printf '%s\n' "$j" | python3 -c "
import sys,json
o=json.load(sys.stdin)
u=o.get('usage',{}) or {}
its=u.get('iterations') or []
# CUMULATIVE input across all turns (this is where re-send compounding shows)
cum=sum((i.get('input_tokens',0) or 0)+(i.get('cache_read_input_tokens',0) or 0)+(i.get('cache_creation_input_tokens',0) or 0) for i in its) if its else (u.get('input_tokens',0) or 0)+(u.get('cache_read_input_tokens',0) or 0)+(u.get('cache_creation_input_tokens',0) or 0)
rec={'arm':'$arm','rep':$rep,'cum_input':cum,'cost':o.get('total_cost_usd',0) or 0,
     'ms':o.get('duration_ms',0) or 0,'turns':o.get('num_turns',0)}
print(json.dumps(rec))
" >> "$OUT"
  echo "  ✓ ${arm} rep${rep}" >&2
}

echo "model=$MODEL repeats=$REPEATS (long task)" >&2
for rep in $(seq 1 "$REPEATS"); do
  run_one baseline   "$BASE_SET"  "$rep"
  run_one quiet-bash "$QUIET_SET" "$rep"
done

echo >&2
python3 - "$OUT" <<'PY'
import sys,json,collections,statistics
rows=[json.loads(l) for l in open(sys.argv[1]) if l.strip()]
by=collections.defaultdict(lambda:collections.defaultdict(list))
for r in rows:
    for k in ('cum_input','cost','ms','turns'): by[r['arm']][k].append(r[k])
def mean(x): return statistics.mean(x) if x else 0
print("# quiet-bash LONG-session benchmark — mean per run")
print("| arm | cumulative input tok | cost $ | turns | time s | runs |")
print("|---|--:|--:|--:|--:|--:|")
for a in ('baseline','quiet-bash'):
    if not by[a]['cum_input']: continue
    print(f"| {a} | {mean(by[a]['cum_input']):,.0f} | {mean(by[a]['cost']):.4f} | {mean(by[a]['turns']):.0f} | {mean(by[a]['ms'])/1000:.0f} | {len(by[a]['cum_input'])} |")
if by['baseline']['cum_input'] and by['quiet-bash']['cum_input']:
    b,q=mean(by['baseline']['cum_input']),mean(by['quiet-bash']['cum_input'])
    bc,qc=mean(by['baseline']['cost']),mean(by['quiet-bash']['cost'])
    print(f"\n**quiet-bash vs baseline: cumulative input {100*(b-q)/b:+.1f}%, cost {100*(bc-qc)/bc:+.1f}%** (negative = quiet-bash lower).")
PY
