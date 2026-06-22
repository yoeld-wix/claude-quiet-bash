#!/usr/bin/env bash
#
# quiet-query — smart query & aggregation over a (spilled) JSON/YAML file.
#
#   quiet-query.sh <file> <op> [args...]
#
# Lets an agent interrogate a large result that quiet-bash spilled to disk
# WITHOUT re-reading the whole thing — each op returns a small, focused answer.
# Backed by jq; YAML is converted via the shared core converter.
#
# Ops:
#   keys   [path]            keys + value-type at path (default root)
#   count  <path>            number of items at an array/object path
#   get    <path>            the value at a jq path
#   sample <path> [n=5]      first n items of an array (default 5)
#   pluck  <path> <field>    project one field from each item of an array
#   select <path> <cond>     items where a jq condition holds (e.g. '.score>0.8')
#   group  <path> <field>    count of items grouped by a field value
#   stats  <path> <field>    count/min/max/sum/avg of a numeric field
#   search <regex>           leaf paths whose key or value matches a regex
#
# <path> is a jq path expression like '.packages' or '.items'. Examples:
#   quiet-query result.json keys
#   quiet-query result.json count '.items'
#   quiet-query result.json stats '.items' '.price'
#   quiet-query result.json group '.items' '.status'
#   quiet-query result.json select '.items' '.score > 0.8'

ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$ROOT/quiet-core.sh"

file="${1:-}"; op="${2:-keys}"
[ -n "$file" ] || { echo "usage: quiet-query.sh <file> <op> [args]" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "quiet-query: jq required" >&2; exit 1; }

json=$(quiet_to_json "$file") || { echo "quiet-query: cannot parse $file" >&2; exit 1; }
a3="${3:-}"; a4="${4:-}"
jqr() { printf '%s' "$json" | jq -r "$@"; }
jqc() { printf '%s' "$json" | jq    "$@"; }

case "$op" in
  keys)
    p="${a3:-.}"
    jqr "($p) | if type==\"object\" then (to_entries[] | \"\\(.key): \\(.value|type)\")
                elif type==\"array\" then \"[array of \\(length) × \\((.[0]|type)//\"?\")]\"
                else type end" ;;
  count)  [ -n "$a3" ] || { echo "count needs <path>" >&2; exit 2; }; jqr "($a3) | length" ;;
  get)    [ -n "$a3" ] || { echo "get needs <path>" >&2; exit 2; };   jqc "($a3)" ;;
  sample) [ -n "$a3" ] || { echo "sample needs <path>" >&2; exit 2; }; jqc "[ ($a3)[0:${a4:-5}] ] | .[0:${a4:-5}]" ;;
  pluck)  { [ -n "$a3" ] && [ -n "$a4" ]; } || { echo "pluck needs <path> <field>" >&2; exit 2; }; jqc "[ ($a3)[] | ($a4) ]" ;;
  select) { [ -n "$a3" ] && [ -n "$a4" ]; } || { echo "select needs <path> <cond>" >&2; exit 2; }; jqc "[ ($a3)[] | select($a4) ]" ;;
  group)  { [ -n "$a3" ] && [ -n "$a4" ]; } || { echo "group needs <path> <field>" >&2; exit 2; };
          jqc "($a3) | group_by($a4) | map({ key: (.[0] | $a4 | tostring), value: length }) | from_entries" ;;
  stats)  { [ -n "$a3" ] && [ -n "$a4" ]; } || { echo "stats needs <path> <field>" >&2; exit 2; };
          jqc "[ ($a3)[] | ($a4) | numbers ] | { count: length, min: (min // null), max: (max // null), sum: (add // 0), avg: (if length>0 then (add/length) else null end) }" ;;
  search) [ -n "$a3" ] || { echo "search needs <regex>" >&2; exit 2; };
          jqr --arg re "$a3" 'paths(scalars) as $p | select(($p[-1]|tostring|test($re)) or (getpath($p)|tostring|test($re)))
                              | "\($p|map(if type=="number" then "[\(tostring)]" else "."+tostring end)|join("")) = \(getpath($p)|tojson)"' ;;
  *) echo "quiet-query: unknown op '$op' (keys|count|get|sample|pluck|select|group|stats|search)" >&2; exit 2 ;;
esac
