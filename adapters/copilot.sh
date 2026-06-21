#!/usr/bin/env bash
#
# GitHub Copilot CLI adapter for quiet-bash.  (preToolUse hook)
# Docs: https://docs.github.com/en/copilot/reference/hooks-configuration
#
# Copilot's preToolUse hook can substitute tool arguments via `modifiedArgs`
# alongside `permissionDecision`. For a verbose command we allow it and swap in
# the rewritten command; otherwise we emit nothing and let Copilot's normal
# flow proceed.
#
# IMPORTANT: Copilot hooks are FAIL-CLOSED — a crash or timeout DENIES the call.
# This adapter therefore never errors out (always exits 0) and only emits a
# decision when it actually rewrites.
#
# NOTE: written to the documented format; verify against your Copilot CLI version.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$ROOT/core/quiet-core.sh"

quiet_prune

input=$(cat)
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // .arguments.command // .args.command // empty')

if rewritten=$(quiet_rewrite "$cmd"); then
  jq -n --arg c "$rewritten" \
    '{permissionDecision: "allow", modifiedArgs: {command: $c}}'
fi
exit 0
