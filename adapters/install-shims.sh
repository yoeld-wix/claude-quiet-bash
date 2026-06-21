#!/usr/bin/env bash
#
# Generate quiet-bash PATH shims.
#
# Creates one symlink per verbose tool (all pointing at quiet-shim.sh) in a shim
# directory, then tells you to prepend that directory to PATH. Because it works
# through PATH, the interception applies to every shell an agent spawns —
# interactive or not — so it covers agents (Cursor, Aider, …) that don't source
# your rc and don't offer a command-rewriting hook.
#
# Usage:
#   adapters/install-shims.sh [SHIM_DIR]      (default: ~/.quiet-bash/shims)

set -eu

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHIM_DIR="${1:-${QUIET_SHIM_DIR:-$HOME/.quiet-bash/shims}}"

TOOLS="jest vitest mocha cypress playwright pytest tox nox cargo gradle mvn sbt \
bazel buildozer turbo webpack vite rollup esbuild tsc eslint prettier rspec rake \
ninja gulp grunt yarn npm pnpm bun make cmake"

mkdir -p "$SHIM_DIR"
for t in $TOOLS; do
  ln -sf "$ROOT/adapters/quiet-shim.sh" "$SHIM_DIR/$t"
done

echo "✓ Installed quiet-bash shims in: $SHIM_DIR"
echo
echo "Add this to your shell rc — and to your agent's environment/PATH setting"
echo "(e.g. Cursor's terminal env, or wherever Aider inherits PATH):"
echo
echo "    export PATH=\"$SHIM_DIR:\$PATH\""
echo
echo "Note: explicit paths like ./gradlew or /usr/bin/make bypass PATH shims by"
echo "design; those are caught by the hook adapters instead."
