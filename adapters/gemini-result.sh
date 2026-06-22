#!/usr/bin/env bash
#
# Gemini CLI adapter — shrink a large tool RESULT.  (AfterTool hook)
# Docs: https://geminicli.com/docs/hooks/reference/
#
# Gemini's AfterTool hook receives the result at `.tool_response.llmContent`.
# Gemini has NO success-preserving result-replace field; the only documented way
# to substitute text for a large result is `decision:"deny"` + `reason` — per the
# docs, deny "hides the real tool output" and `reason` "replaces the tool result
# sent back to the model". CAVEAT: this marks the call as denied/blocked, not
# "succeeded with edited output" — the model may treat it as a failed tool call.
# Configure with matcher "mcp_.*" (Gemini MCP tools are mcp_<server>_<tool>).
#
# NOTE: written to the documented AfterTool schema; not yet run against a live CLI.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$ROOT/core/quiet-core.sh"
command -v jq >/dev/null 2>&1 || exit 0

quiet_prune

input=$(cat)
text=$(printf '%s' "$input" | jq -r '
  .tool_response.llmContent
  | if type=="string" then . elif .==null then "" else tojson end' 2>/dev/null)
[ -z "$text" ] && exit 0

tool=$(printf '%s' "$input" | jq -r '.tool_name // "tool"')

if summary=$(quiet_result_summarize "$text" "$tool"); then
  jq -n --arg r "$summary" '{decision: "deny", reason: $r}'
fi
exit 0
