#!/usr/bin/env bash
#
# GitHub Copilot CLI adapter — shrink a large tool RESULT.  (postToolUse hook)
# Docs: https://docs.github.com/en/copilot/reference/hooks-reference
#
# Copilot's postToolUse hook receives the result at `.toolResult.textResultForLlm`
# (snake_case alias `.tool_result.text_result_for_llm`). It has a clean replace
# field: return `modifiedResult.textResultForLlm` with `resultType:"success"`.
# Configure the matcher to target the tools you want (e.g. MCP tools); confirm
# the literal toolName prefix in your environment.
#
# NOTE: written to the documented schema; not yet run against a live CLI.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$ROOT/core/quiet-core.sh"
command -v jq >/dev/null 2>&1 || exit 0

quiet_prune

input=$(cat)
text=$(printf '%s' "$input" | jq -r '
  (.toolResult.textResultForLlm // .tool_result.text_result_for_llm)
  | if type=="string" then . elif .==null then "" else tojson end' 2>/dev/null)
[ -z "$text" ] && exit 0

tool=$(printf '%s' "$input" | jq -r '.toolName // .tool_name // "tool"')

if summary=$(quiet_result_summarize "$text" "$tool"); then
  jq -n --arg r "$summary" '{modifiedResult: {resultType: "success", textResultForLlm: $r}}'
fi
exit 0
