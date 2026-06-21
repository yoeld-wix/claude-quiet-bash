#!/usr/bin/env bash
#
# Gemini CLI adapter for quiet-bash.  (BeforeTool hook, matcher: run_shell_command)
# Docs: https://geminicli.com/docs/hooks/reference/
#
# Gemini's BeforeTool hook can rewrite a tool call by emitting
# `hookSpecificOutput.tool_input` — an object that merges with and overrides the
# model's arguments. For the shell tool that argument is `command`.
#
# NOTE: written to the documented format; verify against your Gemini CLI version.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$ROOT/core/quiet-core.sh"

quiet_prune

input=$(cat)
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // .toolInput.command // .args.command // empty')

if rewritten=$(quiet_rewrite "$cmd"); then
  jq -n --arg c "$rewritten" \
    '{hookSpecificOutput: {tool_input: {command: $c}}}'
fi
exit 0
