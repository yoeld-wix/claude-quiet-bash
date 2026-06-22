#!/usr/bin/env bash
#
# quiet-json — summarize a large JSON/YAML file instead of dumping it.
#
#   quiet-json.sh <file.json|file.yaml|file.yml>
#
# Emits a collapsed preview: objects/arrays with many entries show a few samples
# plus a "N more of M, same shape" note (so keys aren't repeated hundreds of
# times), long strings are truncated, and a footer prints the exact query
# commands. The file stays untouched on disk.
#
# JSON needs jq. YAML is converted to JSON with whichever of yq / ruby / python3
# is present (ruby & json+yaml ship in Ruby's stdlib, so this works out of the
# box on macOS and most CI). If none can convert, YAML passes through unchanged.
# YAML comments are lost in conversion — acceptable for a summary.

QJDIR="$(cd -P "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$QJDIR/quiet-core.sh"

f="${1:?usage: quiet-json.sh <file>}"

[ -f "$f" ] || exec cat "$f"
command -v jq >/dev/null 2>&1 || exec cat "$f"

: "${QUIET_JSON_MAX_KEYS:=6}"
: "${QUIET_JSON_MAX_ITEMS:=3}"
: "${QUIET_JSON_MAX_STR:=80}"

# Get JSON out of the file (yaml via the shared core converter).
case "$f" in
  *.yaml | *.yml)
    fmt="YAML"; query="yq"
    if ! json=$(quiet_to_json "$f"); then
      exec cat "$f"   # no converter / unparseable → leave YAML alone
    fi ;;
  *)
    fmt="JSON"; query="jq"
    json=$(cat "$f") ;;
esac

program='
def summ:
  if type=="object" then
    (to_entries) as $e | ($e|length) as $n
    | ([ $e[0:'"$QUIET_JSON_MAX_KEYS"'][] | {key:.key, value:(.value|summ)} ]|from_entries)
      + (if $n>'"$QUIET_JSON_MAX_KEYS"' then {"…": "\($n-'"$QUIET_JSON_MAX_KEYS"') more of \($n) keys, same shape"} else {} end)
  elif type=="array" then
    length as $n
    | ([ .['"0:$QUIET_JSON_MAX_ITEMS"'][] | summ ])
      + (if $n>'"$QUIET_JSON_MAX_ITEMS"' then ["… \($n-'"$QUIET_JSON_MAX_ITEMS"') more of \($n), same shape"] else [] end)
  elif type=="string" then
    (if (length)>'"$QUIET_JSON_MAX_STR"' then (.[0:'"$QUIET_JSON_MAX_STR"'] + "…(len=\(length))") else . end)
  else . end;
summ
'

if ! summary=$(printf '%s' "$json" | jq "$program" 2>/dev/null); then
  echo "[quiet-bash] $f is not valid $fmt — showing raw:"
  exec cat "$f"
fi

bytes=$(wc -c <"$f" | tr -d ' ')
lines=$(wc -l <"$f" | tr -d ' ')
echo "[quiet-bash] $f — ${bytes} bytes, ${lines} lines, ${fmt}. Collapsed preview (full file unchanged on disk):"
printf '%s\n' "$summary"
qq="$QJDIR/quiet-query.sh"
cat <<EOF
[quiet-bash] Query/aggregate the full file instead of re-reading it:
    $qq "$f" keys                 # keys + types
    $qq "$f" count '.<path>'      # how many items
    $qq "$f" sample '.<path>' 5   # first 5 items
    $qq "$f" select '.<path>' '.score > 0.8'   # filter
    $qq "$f" group '.<path>' '.status'         # count by field (aggregate)
    $qq "$f" stats '.<path>' '.price'          # min/max/sum/avg
    $qq "$f" search '<regex>'     # find matching paths
  (or raw: ${query} '.<path>' "$f")
EOF
