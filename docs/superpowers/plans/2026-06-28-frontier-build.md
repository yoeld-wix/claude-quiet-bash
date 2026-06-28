# Frontier Build Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Ship `quiet-applies` + `quiet-patch` (output-side diff apply/check) and `bench/dfirst-audit.py` (the meta auditor, v1: two reliable detectors).

**Architecture:** Two zero-dependency `core/` verbs (git-backed, mirroring `core/quiet-verify.sh`) + a python3 transcript auditor extending `bench/session-savings.py`. Stacks on branch `deterministic-first-frontier` (off merged main).

**Tech Stack:** bash + git; python3 (auditor, like the existing bench). Tests append to `tests/run.sh`; auditor uses fixtures under `tests/fixtures/transcripts/`.

## Global Constraints

- **Zero new dependencies** — bash + git + python3 (stdlib).
- **No regression / lossless** — verbs read-only except `quiet-patch`'s apply, which is **check-first + `git apply` atomic** (never partial, never `.rej`, never `--whitespace=fix`); a bad diff fails loud and leaves the tree untouched. Auditor is read-only.
- **Match existing style** — `core/` scripts mirror `core/quiet-verify.sh` (shebang, doc header, arg guards usage→stderr+exit 2, `[quiet-…]` provenance, `git rev-parse` guard like quiet-hist). Auditor mirrors `bench/session-savings.py` (glob discovery, per-line JSON parse, tolerate malformed lines).
- Spec: `docs/superpowers/specs/2026-06-28-frontier-build-design.md`.

---

### Task 1: `quiet-applies` verb

**Files:** Create `core/quiet-applies.sh`; Test: append to `tests/run.sh`.

**Interface:** `core/quiet-applies.sh [-R] [-f FILE]` (diff from `-f` or stdin) → `[quiet-applies] APPLIES — <n> file(s), +<a> −<d>` exit 0; `[quiet-applies] CONFLICT — <reason>` exit 1; non-git/empty/usage → exit 2. Read-only.

- [ ] **Step 1: Write the failing test**

Append to `tests/run.sh` before the final summary/exit block:

```bash
echo "== quiet-applies =="
QA2="$ROOT/core/quiet-applies.sh"
AR=$(mktemp -d); AP=$(mktemp)
( cd "$AR" && git init -q && git config user.email t@t && git config user.name t \
  && printf 'a\nb\nc\n' > f.txt && git add f.txt && git commit -qm init \
  && printf 'a\nB\nc\n' > f.txt && git diff > "$AP" && git checkout -q f.txt )
( cd "$AR" && "$QA2" -f "$AP" ) | grep -q 'APPLIES' && pass "quiet-applies clean → APPLIES" || bad "quiet-applies clean"
( cd "$AR" && "$QA2" -f "$AP" >/dev/null 2>&1; [ $? -eq 0 ] ) && pass "quiet-applies clean exit 0" || bad "quiet-applies exit0"
# corrupt the target so the patch no longer applies → CONFLICT exit 1
( cd "$AR" && printf 'totally\ndifferent\n' > f.txt && "$QA2" -f "$AP" >/dev/null 2>&1; [ $? -eq 1 ] ) && pass "quiet-applies conflict → exit 1" || bad "quiet-applies conflict"
( cd "$AR" && "$QA2" </dev/null >/dev/null 2>&1; [ $? -eq 2 ] ) && pass "quiet-applies empty → exit 2" || bad "quiet-applies empty"
NG=$(mktemp -d); ( cd "$NG" && printf 'x' | "$QA2" >/dev/null 2>&1; [ $? -eq 2 ] ) && pass "quiet-applies non-git → exit 2" || bad "quiet-applies non-git"
rm -rf "$AR" "$NG" "$AP"
```

- [ ] **Step 2: Run to verify it fails** — `bash tests/run.sh` → `quiet-applies` lines FAIL.

- [ ] **Step 3: Implement**

Create `core/quiet-applies.sh`:

```bash
#!/usr/bin/env bash
#
# quiet-applies — does this unified diff apply cleanly? (read-only git apply --check)
# Use instead of reasoning over two file versions to decide if a patch fits.
#
#   quiet-applies.sh [-R] [-f patch.diff] < diff

rev=""; file=""
while [ $# -gt 0 ]; do
  case "$1" in
    -R) rev="-R"; shift ;;
    -f) file="${2:-}"; shift 2 || { echo "quiet-applies: -f needs a file" >&2; exit 2; } ;;
    *)  echo "usage: quiet-applies.sh [-R] [-f patch.diff] < diff" >&2; exit 2 ;;
  esac
done
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "quiet-applies: not a git repo" >&2; exit 2; }

tmp=$(mktemp)
if [ -n "$file" ]; then
  [ -r "$file" ] || { echo "quiet-applies: cannot read $file" >&2; rm -f "$tmp"; exit 2; }
  cat "$file" > "$tmp"
else
  cat > "$tmp"
fi
[ -s "$tmp" ] || { echo "usage: quiet-applies.sh [-R] [-f patch.diff] < diff (empty input)" >&2; rm -f "$tmp"; exit 2; }

if err=$(git apply --check $rev "$tmp" 2>&1); then
  stat=$(git apply --numstat $rev "$tmp" 2>/dev/null | awk '{a+=$1; d+=$2; n++} END{printf "%d file(s), +%d -%d", n, a, d}')
  echo "[quiet-applies] APPLIES — $stat"
  rm -f "$tmp"; exit 0
else
  echo "[quiet-applies] CONFLICT — $(printf '%s' "$err" | head -1)"
  rm -f "$tmp"; exit 1
fi
```

Then `chmod +x core/quiet-applies.sh`.

- [ ] **Step 4: Run to verify pass** — `bash tests/run.sh` → all `quiet-applies` lines `ok`, suite exit 0.

- [ ] **Step 5: Commit**

```bash
git add core/quiet-applies.sh tests/run.sh
git commit -m "feat: quiet-applies — read-only git-apply --check (does this diff fit?)"
```

---

### Task 2: `quiet-patch` verb

**Files:** Create `core/quiet-patch.sh`; Test: append to `tests/run.sh`.

**Interface:** `core/quiet-patch.sh [-R] [-f FILE]` → check-first, then `git apply`; `[quiet-patch] OK — applied <n> file(s), +<a> −<d>` exit 0; on no-apply `[quiet-patch] FAIL — does not apply cleanly; no changes written: <reason>` exit 1 (tree untouched); non-git/empty/usage → exit 2.

- [ ] **Step 1: Write the failing test**

Append to `tests/run.sh` before the final summary/exit block:

```bash
echo "== quiet-patch =="
QP="$ROOT/core/quiet-patch.sh"
PR=$(mktemp -d); PP=$(mktemp)
( cd "$PR" && git init -q && git config user.email t@t && git config user.name t \
  && printf 'a\nb\nc\n' > f.txt && git add f.txt && git commit -qm init \
  && printf 'a\nB\nc\n' > f.txt && git diff > "$PP" && git checkout -q f.txt )
( cd "$PR" && "$QP" -f "$PP" >/dev/null && grep -q '^B$' f.txt ) && pass "quiet-patch applies + changes file" || bad "quiet-patch applies"
# re-apply same patch (already applied) → FAIL exit 1, tree untouched
before=$(cd "$PR" && cat f.txt)
( cd "$PR" && "$QP" -f "$PP" >/dev/null 2>&1; [ $? -eq 1 ] ) && pass "quiet-patch re-apply → FAIL exit 1" || bad "quiet-patch reapply"
after=$(cd "$PR" && cat f.txt); [ "$before" = "$after" ] && pass "quiet-patch FAIL leaves tree untouched" || bad "quiet-patch tree untouched"
( cd "$PR" && "$QP" </dev/null >/dev/null 2>&1; [ $? -eq 2 ] ) && pass "quiet-patch empty → exit 2" || bad "quiet-patch empty"
NGP=$(mktemp -d); ( cd "$NGP" && printf 'x' | "$QP" >/dev/null 2>&1; [ $? -eq 2 ] ) && pass "quiet-patch non-git → exit 2" || bad "quiet-patch non-git"
rm -rf "$PR" "$NGP" "$PP"
```

- [ ] **Step 2: Run to verify it fails** — `bash tests/run.sh` → `quiet-patch` lines FAIL.

- [ ] **Step 3: Implement**

Create `core/quiet-patch.sh`:

```bash
#!/usr/bin/env bash
#
# quiet-patch — apply a unified diff atomically (check first; never partial).
# For an existing diff blob or an atomic multi-file patch. For a single small
# edit, prefer the agent's native Edit tool — this does not replace it.
#
#   quiet-patch.sh [-R] [-f patch.diff] < diff
#
# Safety: dry-run (git apply --check) first; only apply if the WHOLE patch fits;
# never --reject / --whitespace=fix. A bad diff fails loud, tree untouched.

rev=""; file=""
while [ $# -gt 0 ]; do
  case "$1" in
    -R) rev="-R"; shift ;;
    -f) file="${2:-}"; shift 2 || { echo "quiet-patch: -f needs a file" >&2; exit 2; } ;;
    *)  echo "usage: quiet-patch.sh [-R] [-f patch.diff] < diff" >&2; exit 2 ;;
  esac
done
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "quiet-patch: not a git repo" >&2; exit 2; }

tmp=$(mktemp)
if [ -n "$file" ]; then
  [ -r "$file" ] || { echo "quiet-patch: cannot read $file" >&2; rm -f "$tmp"; exit 2; }
  cat "$file" > "$tmp"
else
  cat > "$tmp"
fi
[ -s "$tmp" ] || { echo "usage: quiet-patch.sh [-R] [-f patch.diff] < diff (empty input)" >&2; rm -f "$tmp"; exit 2; }

if ! err=$(git apply --check $rev "$tmp" 2>&1); then
  echo "[quiet-patch] FAIL — does not apply cleanly; no changes written: $(printf '%s' "$err" | head -1)"
  rm -f "$tmp"; exit 1
fi
stat=$(git apply --numstat $rev "$tmp" 2>/dev/null | awk '{a+=$1; d+=$2; n++} END{printf "%d file(s), +%d -%d", n, a, d}')
git apply $rev "$tmp"
echo "[quiet-patch] OK — applied $stat"
rm -f "$tmp"; exit 0
```

Then `chmod +x core/quiet-patch.sh`.

- [ ] **Step 4: Run to verify pass** — `bash tests/run.sh` → all `quiet-patch` lines `ok`, suite exit 0.

- [ ] **Step 5: Commit**

```bash
git add core/quiet-patch.sh tests/run.sh
git commit -m "feat: quiet-patch — apply a unified diff atomically (check-first, never partial)"
```

---

### Task 3: `bench/dfirst-audit.py` — the meta auditor

**Files:** Create `bench/dfirst-audit.py`, `tests/fixtures/transcripts/{probe,reread,clean}.jsonl`; Test: append to `tests/run.sh`. **READ `bench/session-savings.py` first and mirror its discovery/parse/robustness.**

**Interface:** `bench/dfirst-audit.py [GLOB] [--top N]` → markdown report with a per-pattern table (P4 toolchain probing → quiet-env; P2 unchanged re-read → quiet-dedup) + top offending sessions. Tolerates malformed lines.

- [ ] **Step 1: Write the failing test + fixtures**

Create `tests/fixtures/transcripts/probe.jsonl`:

```
{"message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"node --version"}}]}}
{"message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"which docker"}}]}}
```

Create `tests/fixtures/transcripts/reread.jsonl`:

```
{"message":{"content":[{"type":"tool_use","name":"Read","input":{"file_path":"/a/b.txt"}}]}}
{"message":{"content":[{"type":"tool_use","name":"Read","input":{"file_path":"/a/b.txt"}}]}}
```

Create `tests/fixtures/transcripts/clean.jsonl`:

```
{"message":{"content":[{"type":"tool_use","name":"Read","input":{"file_path":"/a/b.txt"}}]}}
{"message":{"content":[{"type":"text","text":"done"}]}}
```

Append to `tests/run.sh` before the final summary/exit block:

```bash
echo "== bench: dfirst-audit =="
DA="$ROOT/bench/dfirst-audit.py"
FX="$ROOT/tests/fixtures/transcripts"
python3 "$DA" "$FX/probe.jsonl" | grep -q 'quiet-env | 1 | 2' && pass "audit P4 detects probes" || bad "audit P4"
python3 "$DA" "$FX/reread.jsonl" | grep -q 'quiet-dedup | 1 | 1' && pass "audit P2 detects re-read" || bad "audit P2"
cl=$(python3 "$DA" "$FX/clean.jsonl")
{ printf '%s' "$cl" | grep -q 'quiet-env | 0 | 0' && printf '%s' "$cl" | grep -q 'quiet-dedup | 0 | 0'; } && pass "audit clean → no hits" || bad "audit clean"
BADJ=$(mktemp); printf 'not json\n{"message":{"content":[]}}\n' > "$BADJ"
python3 "$DA" "$BADJ" >/dev/null 2>&1 && pass "audit tolerates malformed lines" || bad "audit malformed"
rm -f "$BADJ"
```

- [ ] **Step 2: Run to verify it fails** — `bash tests/run.sh` → `dfirst-audit` lines FAIL (script missing).

- [ ] **Step 3: Implement**

Create `bench/dfirst-audit.py`:

```python
#!/usr/bin/env python3
"""
dfirst-audit — mine agent transcripts for deterministic-first opportunities.

Extends bench/session-savings.py's transcript scan with a sequence model over
tool calls, flagging where the model did tool-shaped work a quiet-bash lever
would do. v1 detectors (high-confidence, structural):
  P4 toolchain probing -> quiet-env   (>=2 version/availability probes in a session)
  P2 unchanged re-read  -> quiet-dedup (Read of a path already Read, no edit since)

Output is candidate DISCOVERY (which lever a real workload needs), NOT a token
number — exact billing stays in bench/run.sh + session-savings.py.

Usage:
  bench/dfirst-audit.py [GLOB] [--top N]      # default GLOB: ~/.claude/projects/*/*.jsonl
"""
import json, glob, os, sys, re

PROBE_RE = re.compile(
    r'(^|\s)(node|python3?|go|rustc|java|ruby|deno|bun|npm|pnpm|yarn|cargo|docker|kubectl)\s+(--version|-v|-version|version)\b'
    r'|(^|\s)(which|type)\s+\S'
    r'|command\s+-v\s+\S'
)

def events(fp):
    """Yield (name, input_dict) for each tool_use in file order; tolerate junk."""
    for ln in open(fp, errors="ignore"):
        ln = ln.strip()
        if not ln:
            continue
        try:
            o = json.loads(ln)
        except Exception:
            continue
        msg = o.get("message") or {}
        content = msg.get("content") if isinstance(msg, dict) else None
        parts = content if isinstance(content, list) else ([content] if content else [])
        for c in parts:
            if isinstance(c, dict) and c.get("type") == "tool_use":
                yield (c.get("name") or "", c.get("input") or {})

def audit(fp):
    probes = 0
    seen, dirty, rereads = set(), set(), 0
    for name, inp in events(fp):
        if not isinstance(inp, dict):
            continue
        if name == "Bash":
            cmd = inp.get("command")
            if isinstance(cmd, str) and PROBE_RE.search(cmd):
                probes += 1
        elif name == "Read":
            p = inp.get("file_path")
            if p:
                if p in seen and p not in dirty:
                    rereads += 1
                seen.add(p); dirty.discard(p)
        elif name in ("Edit", "Write", "MultiEdit"):
            p = inp.get("file_path")
            if p:
                dirty.add(p)
    return probes, rereads

def main():
    top = 20
    pat = None
    a = sys.argv[1:]
    i = 0
    while i < len(a):
        if a[i] == "--top":
            top = int(a[i + 1]); i += 2
        else:
            pat = a[i]; i += 1
    if pat is None:
        pat = os.path.expanduser("~/.claude/projects/*/*.jsonl")

    files = glob.glob(pat)
    tot_probe = tot_reread = sess_probe = sess_reread = 0
    rows = []
    for fp in files:
        pr, rr = audit(fp)
        tot_probe += pr; tot_reread += rr
        if pr >= 2:
            sess_probe += 1
        if rr >= 1:
            sess_reread += 1
        if pr or rr:
            rows.append((os.path.basename(fp), pr, rr))

    print("# deterministic-first audit")
    print(f"scanned {len(files)} transcript(s)")
    print()
    print("| pattern | lever | sessions hit | total occurrences |")
    print("|---|---|--:|--:|")
    print(f"| P4 toolchain probing (>=2/session) | quiet-env | {sess_probe} | {tot_probe} |")
    print(f"| P2 unchanged re-read | quiet-dedup | {sess_reread} | {tot_reread} |")
    print()
    print("Directional candidate-discovery signal (not a token total). A pattern with")
    print("many hits and no shipped lever is the next thing to build.")
    if rows:
        rows.sort(key=lambda r: -(r[1] + r[2]))
        print("\n## top sessions")
        for name, pr, rr in rows[:top]:
            print(f"- {name}: probes={pr} rereads={rr}")

if __name__ == "__main__":
    main()
```

(`bench/dfirst-audit.py` is run via `python3`; `chmod +x` optional but harmless.)

- [ ] **Step 4: Run to verify pass** — `bash tests/run.sh` → all `dfirst-audit` lines `ok`, suite exit 0.

- [ ] **Step 5: Commit**

```bash
git add bench/dfirst-audit.py tests/fixtures/transcripts tests/run.sh
git commit -m "feat(bench): dfirst-audit — mine transcripts for deterministic-first candidates"
```

---

### Task 4: Skill + README surface

**Files:** Modify `skills/deterministic-first/SKILL.md`, `README.md`; Test: structural assertion in `tests/run.sh`.

- [ ] **Step 1: Write the failing test**

Append to `tests/run.sh` before the final summary/exit block:

```bash
echo "== frontier skill rows =="
SKF="$ROOT/skills/deterministic-first/SKILL.md"
for tok in 'quiet-patch' 'quiet-applies'; do
  grep -qF "$tok" "$SKF" 2>/dev/null && pass "skill mentions $tok" || bad "skill missing $tok"
done
```

- [ ] **Step 2: Run to verify it fails** — those lines FAIL.

- [ ] **Step 3: Add skill row**

In `skills/deterministic-first/SKILL.md`, in the pattern table under `## The decision rule`, add after the **Orient** row:

```markdown
| **Apply a diff** — existing patch / multi-file / no Edit tool | re-emit whole files; reason if a patch fits | `quiet-applies FILE` (does it fit?) then `quiet-patch FILE`; single small edits → use Edit |
```

- [ ] **Step 4: Add the README row**

In `README.md`, find the row beginning `| **Orientation**` (added last round). Directly beneath it, add:

```markdown
| **Diff apply & audit** — apply a patch, find more savings | re-emit whole files; brainstorm what to optimize | `quiet-applies`/`quiet-patch` (atomic git apply) · `bench/dfirst-audit.py` (mine transcripts for candidates) |
```

- [ ] **Step 5: Run to verify pass** — `bash tests/run.sh` → `frontier skill rows` `ok`; existing structural test still green; suite exit 0.

- [ ] **Step 6: Commit**

```bash
git add skills/deterministic-first/SKILL.md README.md tests/run.sh
git commit -m "docs: surface quiet-patch/applies + dfirst-audit in skill + README"
```

---

## Notes for the implementer
- **Order 1→4.** Append each test section after existing ones; never disturb the final `[ "$fail" -eq 0 ]` accounting.
- **Tasks 1–2** create throwaway temp git repos in tests (never mutate the real working tree). The `$rev`/`$file` vars are intentionally unquoted in the `git apply $rev` calls so an empty `$rev` expands to nothing — keep them as written.
- **Task 3** mirrors `bench/session-savings.py` — read it first; tolerate malformed lines (the test asserts this). The report table strings must match the test greps exactly (`quiet-env | 1 | 2`, `quiet-dedup | 1 | 1`, `… | 0 | 0`).
- **Do not** add `--reject`/`--whitespace=fix` to `quiet-patch` (would break the no-corrupt guarantee), and do not weaken the exit-2 guards.
