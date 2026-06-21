#!/usr/bin/env bash
#
# quiet-bash PATH shim (name-aware).
#
# Installed as symlinks named after each verbose tool (yarn, pytest, cargo, …)
# in a directory that is prepended to PATH. Unlike the rc-sourced wrapper, this
# intercepts under ANY shell — interactive or not, login or not — because it
# works through PATH rather than shell startup files. That makes it the robust
# option for agents (Cursor, Aider, …) that run commands in non-interactive
# shells which never source your rc.
#
# Run adapters/install-shims.sh to create the symlinks.

# Resolve a path through symlinks and normalise its directory physically, so
# comparisons work across the /var -> /private/var indirection on macOS.
_qb_resolve() {
  local p="$1" d
  while [ -h "$p" ]; do
    d="$(cd -P "$(dirname "$p")" 2>/dev/null && pwd)" || break
    p="$(readlink "$p")"
    case "$p" in /*) ;; *) p="$d/$p" ;; esac
  done
  d="$(cd -P "$(dirname "$p")" 2>/dev/null && pwd)" || { printf '%s' "$p"; return; }
  printf '%s/%s' "$d" "$(basename "$p")"
}

invoked="${BASH_SOURCE[0]:-$0}"
tool="$(basename "$invoked")"
self_real="$(_qb_resolve "$invoked")"       # …/adapters/quiet-shim.sh (resolved)
root="$(cd -P "$(dirname "$self_real")/.." && pwd)"
. "$root/core/quiet-core.sh"

# Locate the REAL tool: first PATH match that is NOT one of our own shims
# (i.e. does not resolve back to this script).
real=""
_oifs=$IFS; IFS=:
for dd in $PATH; do
  cand="$dd/$tool"
  [ -x "$cand" ] || continue
  [ "$(_qb_resolve "$cand")" = "$self_real" ] && continue
  real="$cand"; break
done
IFS=$_oifs
if [ -z "$real" ]; then
  echo "quiet-bash: real '$tool' not found on PATH (only quiet-bash shims)" >&2
  exit 127
fi

# Never wrap version/help probes.
case " $* " in
  *" --version "* | *" -V "* | *" --help "* | *" -h "*) exec "$real" "$@" ;;
esac

# Package managers: only wrap known-verbose subcommands.
case "$tool" in
  yarn | npm | pnpm | bun)
    case "${1:-}" in
      test | build | lint | install | add | ci | run | dev | start | typecheck | watch)
        quiet_run "$real" "$@"; exit $? ;;
      *) exec "$real" "$@" ;;
    esac ;;
esac

# Everything else (always-verbose tools): wrap.
quiet_run "$real" "$@"
exit $?
