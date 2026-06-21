#!/usr/bin/env bash
#
# quiet-bash test suite. Runs in CI and locally:  bash tests/run.sh
# Exits non-zero if any assertion fails.

set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fail=0
pass() { printf '  \033[32mok\033[0m   %s\n' "$1"; }
bad()  { printf '  \033[31mFAIL\033[0m %s\n' "$1"; fail=1; }

echo "== core: should WRAP =="
. "$ROOT/core/quiet-core.sh"
for c in "yarn test" "pnpm run build" "bun test" "pytest -q" "cargo build --release" \
         "go test ./..." "mvn package" "./gradlew test" "docker compose up" "make" \
         "cmake --build ." "ninja" "jest" "eslint . --fix" "tsc -p ." "uv sync" \
         "git diff" "git log" "git show HEAD"; do
  if quiet_rewrite "$c" >/dev/null; then pass "wrap: $c"; else bad "should wrap: $c"; fi
done

echo "== core: should PASS THROUGH =="
for c in "ls -la" "cat f.txt" "grep -r x ." "git status" "gh pr list" "echo hi" "pwd" \
         "cd /tmp" "which node" "git diff --stat" "git log --oneline" "yarn info x"; do
  if quiet_rewrite "$c" >/dev/null; then bad "should pass: $c"; else pass "pass: $c"; fi
done

echo "== adapters: output shape for 'yarn test' + passthrough for 'ls -la' =="
EV='{"tool_input":{"command":"yarn test"}}'
PE='{"tool_input":{"command":"ls -la"}}'

shape() { # adapter  jqpath  name
  local got
  got=$(printf '%s' "$EV" | "$ROOT/adapters/$1" | jq -r "$2" 2>/dev/null)
  [ -n "$got" ] && [ "$got" != "null" ] && pass "$3 wraps" || bad "$3 wrap shape ($2)"
  got=$(printf '%s' "$PE" | "$ROOT/adapters/$1")
  [ -z "$got" ] && pass "$3 passes through" || bad "$3 should pass through"
}
shape claude-code.sh '.hookSpecificOutput.updatedInput.command'        "claude-code"
shape codex.sh       '.hookSpecificOutput.updatedInput.command'        "codex"
shape gemini.sh      '.hookSpecificOutput.tool_input.command'          "gemini"
shape copilot.sh     '.modifiedArgs.command'                           "copilot"
# codex + copilot must say permissionDecision: allow
[ "$(printf '%s' "$EV" | "$ROOT/adapters/codex.sh"   | jq -r '.hookSpecificOutput.permissionDecision')" = "allow" ] && pass "codex allow"   || bad "codex allow"
[ "$(printf '%s' "$EV" | "$ROOT/adapters/copilot.sh" | jq -r '.permissionDecision')" = "allow" ] && pass "copilot allow" || bad "copilot allow"

echo "== shims: wrap / passthrough via PATH =="
TMP=$(mktemp -d)
mkdir -p "$TMP/realbin" "$TMP/shims"
printf '#!/usr/bin/env bash\necho l1; echo l2; echo l3\n' > "$TMP/realbin/pytest"
printf '#!/usr/bin/env bash\necho "yarn $*"\n' > "$TMP/realbin/yarn"
chmod +x "$TMP/realbin/pytest" "$TMP/realbin/yarn"
"$ROOT/adapters/install-shims.sh" "$TMP/shims" >/dev/null
export PATH="$TMP/shims:$TMP/realbin:$PATH"
out=$(timeout 10 pytest </dev/null);              echo "$out" | grep -q '^\[ok' && pass "shim pytest wraps"       || bad "shim pytest wrap"
out=$(timeout 10 pytest --version </dev/null);    { ! echo "$out" | grep -q '^\[ok'; } && echo "$out" | grep -q 'l1' && pass "shim --version passes" || bad "shim --version pass"
out=$(timeout 10 yarn install </dev/null);        echo "$out" | grep -q '^\[ok' && pass "shim yarn install wraps" || bad "shim yarn install wrap"
out=$(timeout 10 yarn info x </dev/null);          echo "$out" | grep -q '^yarn info x' && pass "shim yarn info passes" || bad "shim yarn info pass"
rm -rf "$TMP"

echo
[ "$fail" -eq 0 ] && { echo "ALL TESTS PASSED"; exit 0; } || { echo "TESTS FAILED"; exit 1; }
