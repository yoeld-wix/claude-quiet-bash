#!/usr/bin/env bash
#
# Real multi-arm agentic benchmark for quiet-bash (input side).
#
# Runs a headless Claude Code session on real read-only tasks across three arms,
# isolating quiet-bash's two levers, and measures the real input tokens / cost /
# time each consumes:
#   A baseline  — no hooks
#   B cmd-only  — command-output quieting only (PreToolUse Bash)
#   C full      — command-output + Read/MCP result quieting (Pre + PostToolUse)
# quiet-bash reduces the context that gets re-sent, so B and C should spend fewer
# input tokens (and less $) than A for the same answers.
#
# Tasks are read-only and dependency-free (git log, large file reads) so they
# trigger quiet-bash's quieting without mutating the target repo or needing a build.
#
# Usage:
#   QB_TARGET=/path/to/git/repo QB_MODEL=claude-haiku-4-5 QB_REPEATS=2 bench/agentic.sh
#
set -uo pipefail
ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
TARGET="${QB_TARGET:?set QB_TARGET to a git repo to run the tasks in}"
MODEL="${QB_MODEL:-claude-haiku-4-5}"
REPEATS="${QB_REPEATS:-2}"
OUT="${QB_OUT:-$ROOT/bench/agentic-runs.jsonl}"
: > "$OUT"

# Three arms, isolating quiet-bash's two levers:
#   A baseline  = no hooks
#   B cmd-only  = command-output quieting only (PreToolUse Bash)
#   C full      = command-output + Read/MCP result quieting (Pre + PostToolUse)
PRE_HOOK='"PreToolUse":  [ { "matcher": "Bash", "hooks": [ { "type": "command", "command": "'"$ROOT"'/adapters/claude-code.sh", "timeout": 15 } ] } ]'
POST_HOOK='"PostToolUse": [ { "matcher": "Read|mcp__.*|WebFetch|WebSearch", "hooks": [ { "type": "command", "command": "'"$ROOT"'/adapters/claude-code-result.sh", "timeout": 15 } ] } ]'

BASE_SET="$(mktemp)";    printf '{}\n' > "$BASE_SET"
CMDONLY_SET="$(mktemp)"; printf '{ "hooks": { %s } }\n'      "$PRE_HOOK"             > "$CMDONLY_SET"
FULL_SET="$(mktemp)";    printf '{ "hooks": { %s, %s } }\n'  "$PRE_HOOK" "$POST_HOOK" > "$FULL_SET"

TASKS=(
  "Run: git log -p -30   then summarise the three most significant changes in two sentences."
  "Read packages/astra-migrations-mcp-server/src/services/pr-review.ts and list its exported function names."
  "Run: cat package-lock.json   then tell me roughly how many dependency entries it has."
  "Run: git log --stat -120   then name the three files that changed most often."
)

run_one() { # arm settings task_idx repeat
  local arm="$1" set="$2" ti="$3" rep="$4" task="${TASKS[$3]}"
  local j
  j=$(cd "$TARGET" && timeout 300 claude -p "$task" \
        --model "$MODEL" --output-format json --settings "$set" \
        --allowedTools "Bash" "Read" "Grep" "Glob" 2>/dev/null)
  [ -z "$j" ] && { echo "  ! ${arm} task${ti} rep${rep}: no output" >&2; return; }
  printf '%s\n' "$j" | python3 -c "
import sys,json
o=json.load(sys.stdin)
u=o.get('usage',{}) or {}
inp=(u.get('input_tokens',0) or 0)+(u.get('cache_read_input_tokens',0) or 0)+(u.get('cache_creation_input_tokens',0) or 0)
rec={'arm':'$arm','task':$ti,'rep':$rep,'input':inp,'output':u.get('output_tokens',0) or 0,
     'cost':o.get('total_cost_usd',0) or 0,'ms':o.get('duration_ms',0) or 0,'turns':o.get('num_turns',0)}
print(json.dumps(rec))
" >> "$OUT"
  echo "  ✓ ${arm} task${ti} rep${rep}" >&2
}

echo "model=$MODEL repeats=$REPEATS target=$TARGET" >&2
for ti in "${!TASKS[@]}"; do
  for rep in $(seq 1 "$REPEATS"); do
    run_one baseline "$BASE_SET"    "$ti" "$rep"
    run_one cmd-only "$CMDONLY_SET" "$ti" "$rep"
    run_one full     "$FULL_SET"    "$ti" "$rep"
  done
done

echo >&2
python3 - "$OUT" <<'PY'
import sys,json,collections,statistics
rows=[json.loads(l) for l in open(sys.argv[1]) if l.strip()]
by=collections.defaultdict(lambda:collections.defaultdict(list))
for r in rows:
    for k in ('input','output','cost','ms'): by[r['arm']][k].append(r[k])
def mean(x): return statistics.mean(x) if x else 0
arms=['baseline','cmd-only','full']
labels={'baseline':'A baseline (no hooks)','cmd-only':'B cmd-only (Bash)','full':'C full (Bash + Read/MCP)'}
print("# quiet-bash agentic benchmark — mean per run (3-arm)")
print(f"| arm | input tok | output tok | cost $ | time s | runs |")
print(f"|---|--:|--:|--:|--:|--:|")
for a in arms:
    if not by[a]['input']: continue
    print(f"| {labels[a]} | {mean(by[a]['input']):,.0f} | {mean(by[a]['output']):,.0f} | {mean(by[a]['cost']):.4f} | {mean(by[a]['ms'])/1000:.1f} | {len(by[a]['input'])} |")
if by['baseline']['input']:
    b,bc=mean(by['baseline']['input']),mean(by['baseline']['cost'])
    print("\n_vs baseline (negative = cheaper):_")
    for a in ('cmd-only','full'):
        if not by[a]['input']: continue
        q,qc=mean(by[a]['input']),mean(by[a]['cost'])
        print(f"- **{labels[a]}**: input {100*(b-q)/b:+.1f}%, cost {100*(bc-qc)/bc:+.1f}%")
PY
