# Source-File Outlining Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace large source-file reads with a zero-dependency signature skeleton (imports + class/function/method signatures, bodies elided) plus exact line ranges to expand any body, cutting per-turn token cost without losing information.

**Architecture:** A new `core/quiet-outline.sh` mirrors `core/quiet-json.sh`: it takes a file path and prints an outline + drill-in footer. Symbol start-lines come from `grep -nE` (reliable ERE per language); body ranges and rendering are computed in a single `awk` pass (no dynamic awk regex, bash-3.2 safe). It is wired into both read paths — the Bash `cat` path via `quiet_rewrite`, and the native `Read` path via the PostToolUse adapter — and falls back to existing behavior whenever it can't produce a useful outline. The source file on disk is the byte-exact backup, so no spill file is created.

**Tech Stack:** POSIX shell (bash 3.2+ / zsh), `grep -E`, `awk`, `sed`, `wc` (coreutils). No tree-sitter, no ctags, no other dependencies.

## Global Constraints

- Zero hard dependencies beyond coreutils/awk/grep/sed; must work with nothing else installed (matches the YAML-ladder ethos).
- TypeScript/strict-equivalent rigor for shell: every script must pass `shellcheck -S error` and the existing `tests/run.sh` must stay green.
- Lossless: never modify the source file; the file is the backup; every elided body lists its exact line range.
- Cache-safe: only tail rewrites (Bash command rewritten pre-exec; Read result rewritten in PostToolUse). Deterministic rendering — no timestamps, stable ordering.
- Default thresholds copied verbatim from the spec: `QUIET_OUTLINE_MIN_BYTES=30000`, `QUIET_OUTLINE_MIN_SYMBOLS=3`.
- Source-extension allowlist (verbatim): `py js mjs cjs jsx ts tsx go rs java kt kts scala rb c h cc cpp cxx hpp php swift`.
- Drill-in examples must reference the exact path passed to the outliner (`$f`), not the basename, so expansion works from any working directory. The human-readable header label uses the basename.
- Regression guards (all three required): size threshold, extension allowlist, and a symbol-count floor (`< QUIET_OUTLINE_MIN_SYMBOLS` → fall back to `cat`).
- Follow existing patterns: source `core/quiet-core.sh`; reuse `QUIET_CORE_DIR`; honor the existing double-wrap guards.

---

### Task 1: Outliner core engine + Python support

**Files:**
- Create: `core/quiet-outline.sh`
- Modify: `core/quiet-core.sh` (add two config defaults near the other `: "${QUIET_*}"` lines, ~line 23)
- Test: `tests/run.sh` (append a new `== source-file outlining ==` block)

**Interfaces:**
- Consumes: `core/quiet-core.sh` (sourced — provides `QUIET_CORE_DIR`, config defaults).
- Produces: executable `core/quiet-outline.sh <file>` that prints to stdout. On a parseable large source file it prints a first line starting with the literal `[quiet-bash]`; when it cannot produce a useful outline (non-source extension, missing file, or fewer than `QUIET_OUTLINE_MIN_SYMBOLS` symbols) it `exec cat "$file"` so the caller's normal handling applies. New config vars `QUIET_OUTLINE_MIN_BYTES` (default `30000`) and `QUIET_OUTLINE_MIN_SYMBOLS` (default `3`).

- [ ] **Step 1: Add config defaults to `core/quiet-core.sh`**

Add these two lines immediately after the existing `: "${QUIET_JSON_MIN_BYTES:=25000}"` line:

```bash
: "${QUIET_OUTLINE_MIN_BYTES:=30000}"    # outline source files larger than this
: "${QUIET_OUTLINE_MIN_SYMBOLS:=3}"      # below this many symbols, skip outlining
```

- [ ] **Step 2: Write the failing test (Python outline + fallback + range correctness)**

Append to `tests/run.sh`, before the final `echo` / summary block:

```bash
echo "== source-file outlining =="
QO="$ROOT/core/quiet-outline.sh"
OT=$(mktemp -d)
# A large (>30KB) Python file with many symbols.
{
  echo "import os"
  echo "import sys"
  echo "from typing import List"
  for i in $(seq 1 400); do
    echo ""
    echo "def func_${i}(a, b):"
    echo "    # padding to grow the file well past the byte threshold xxxxxxxxxxxxxxxxxxxx"
    echo "    return a + b + ${i}"
  done
  echo ""
  echo "class Widget:"
  echo "    def render(self):"
  echo "        return 'MARKER_RENDER_BODY'"
} > "$OT/big.py"
po=$(QUIET_OUTLINE_MIN_BYTES=30000 "$QO" "$OT/big.py")
printf '%s' "$po" | grep -q '^\[quiet-bash\].*Python.*outline' && pass "python file outlined" || bad "python outline header"
printf '%s' "$po" | grep -q 'def func_1(a, b)' && pass "python signature shown" || bad "python signature"
printf '%s' "$po" | grep -qE 'body [0-9]+-[0-9]+' && pass "python body ranges shown" || bad "python body range"
# Range correctness: the Widget.render body range must contain the marker.
rng=$(printf '%s\n' "$po" | sed -n 's/.*render.*body \([0-9]*\)-\([0-9]*\)$/\1 \2/p' | head -1)
set -- $rng
[ -n "${1:-}" ] && sed -n "${1},${2}p" "$OT/big.py" | grep -q 'MARKER_RENDER_BODY' \
  && pass "python range expands to the real body" || bad "python range correctness"
# Symbol floor: a source-extension file with <3 symbols falls back to raw cat.
{ echo "x = 1"; for i in $(seq 1 4000); do echo "# comment line $i padding padding padding"; done; } > "$OT/data.py"
pf=$(QUIET_OUTLINE_MIN_BYTES=30000 "$QO" "$OT/data.py")
printf '%s' "$pf" | grep -q '^\[quiet-bash\]' && bad "symbol-floor should NOT outline" || pass "symbol-floor falls back to raw"
# Non-source extension → raw passthrough.
{ for i in $(seq 1 4000); do echo "plain text line $i"; done; } > "$OT/notes.txt"
pn=$("$QO" "$OT/notes.txt")
printf '%s' "$pn" | grep -q '^\[quiet-bash\]' && bad ".txt should not be outlined" || pass "non-source extension passthrough"
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `bash tests/run.sh 2>&1 | grep -A20 'source-file outlining'`
Expected: FAIL lines (e.g. "python outline header") because `core/quiet-outline.sh` does not exist yet.

- [ ] **Step 4: Create `core/quiet-outline.sh` (engine + Python)**

```bash
#!/usr/bin/env bash
#
# quiet-outline — signature skeleton for a large source file (zero-dep).
#
#   quiet-outline.sh <file>
#
# Prints imports + class/function/method signatures with bodies elided, each
# with the exact line range to expand it (Read <file> offset=S limit=N). The
# file is never modified and IS the byte-exact backup. If fewer than
# QUIET_OUTLINE_MIN_SYMBOLS symbols are found, or the extension is not a known
# source type, it `exec cat`s the file so the caller's normal handling applies.
#
# Symbol start-lines come from `grep -nE` (reliable ERE); body ranges + render
# are an awk pass over the file (no dynamic awk regex; bash-3.2 safe).

QODIR="$(cd -P "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$QODIR/quiet-core.sh"

f="${1:?usage: quiet-outline.sh <file>}"
[ -f "$f" ] || exec cat "$f"

base="${f##*/}"; ext="${base##*.}"
lang=""; sig=""
case "$ext" in
  py) lang="Python"
      sig='^[[:space:]]*(async[[:space:]]+def|def|class)[[:space:]]' ;;
  *) exec cat "$f" ;;   # not a known source extension → leave it
esac

import_re='^[[:space:]]*(import|from|#include|use|require|using|package)([[:space:]]|\()'

sym_lines=$(grep -nE "$sig" "$f" 2>/dev/null | cut -d: -f1 | tr '\n' ' ')
imp_lines=$(grep -nE "$import_re" "$f" 2>/dev/null | cut -d: -f1 | tr '\n' ' ')
n=$(printf '%s' "$sym_lines" | wc -w | tr -d ' ')
[ "$n" -lt "${QUIET_OUTLINE_MIN_SYMBOLS}" ] && exec cat "$f"

out=$(awk -v syms="$sym_lines" -v imps="$imp_lines" -v minsym="${QUIET_OUTLINE_MIN_SYMBOLS}" '
BEGIN{
  ns=split(syms, SA, " "); cnt=0
  for(i=1;i<=ns;i++) if(SA[i]!=""){ cnt++; order[cnt]=SA[i]+0 }
  ni=split(imps, IA, " ")
  for(i=1;i<=ni;i++) if(IA[i]!=""){ if(!ifirst) ifirst=IA[i]+0; ilast=IA[i]+0 }
}
{ L[NR]=$0 }
END{
  total=NR
  if(cnt<minsym){ print "@@FALLBACK@@"; exit }
  if(ifirst) printf "%6d  imports ... (lines %d-%d)\n", ifirst, ifirst, ilast
  for(k=1;k<=cnt;k++){
    s=order[k]; e=(k<cnt ? order[k+1]-1 : total)
    t=L[s]; sub(/[[:space:]]+$/,"",t)
    if(length(t)>200) t=substr(t,1,200) "..."
    printf "%6d  %s   body %d-%d\n", s, t, s, e
  }
  printf "@@META@@ %d %d\n", cnt, total
}' "$f")

case "$out" in *"@@FALLBACK@@"*) exec cat "$f" ;; esac

meta=$(printf '%s\n' "$out" | sed -n 's/^@@META@@ //p')
n=${meta%% *}; total=${meta##* }
body=$(printf '%s\n' "$out" | grep -v '^@@META@@')
bytes=$(wc -c <"$f" | tr -d ' ')

first=$(printf '%s\n' "$body" | sed -n 's/.*body \([0-9]*\)-\([0-9]*\)$/\1 \2/p' | head -1)
# shellcheck disable=SC2086
set -- $first
es="${1:-1}"; ee="${2:-1}"; en=$((ee-es+1))

printf '[quiet-bash] %s - %d lines / %d bytes of %s - outline (bodies elided; expand: Read %s offset=<start> limit=<n>)\n' \
  "$base" "$total" "$bytes" "$lang" "$f"
printf '%s\n' "$body"
printf '  [%d symbols - full body: Read %s offset=%d limit=%d - raw: sed -n %d,%dp %s]\n' \
  "$n" "$f" "$es" "$en" "$es" "$ee" "$f"
```

- [ ] **Step 5: Make it executable**

Run: `chmod +x core/quiet-outline.sh`

- [ ] **Step 6: Run the test to verify it passes**

Run: `bash tests/run.sh 2>&1 | grep -A8 'source-file outlining'`
Expected: all `ok` for the python/fallback/passthrough/range assertions.

- [ ] **Step 7: shellcheck the new script**

Run: `shellcheck -S error core/quiet-outline.sh && echo clean`
Expected: `clean`

- [ ] **Step 8: Commit**

```bash
git add core/quiet-outline.sh core/quiet-core.sh tests/run.sh
git commit -m "feat(outline): zero-dep source outliner engine + Python support"
```

---

### Task 2: Remaining language support

**Files:**
- Modify: `core/quiet-outline.sh` (extend the `case "$ext"` block)
- Test: `tests/run.sh` (extend the outlining block)

**Interfaces:**
- Consumes: the engine from Task 1 (grep `sig` → awk render). Each new language only adds a `case` arm setting `lang` and `sig`.
- Produces: outlining for `js mjs cjs jsx ts tsx go rs java kt kts scala rb c h cc cpp cxx hpp php swift` (the rest of the allowlist).

- [ ] **Step 1: Write the failing tests (one per language family)**

Append inside the `== source-file outlining ==` block in `tests/run.sh`:

```bash
# TypeScript
{ echo "import x from 'y'"; for i in $(seq 1 300); do echo "export function fn${i}(a: number): number { return a + ${i} }"; done; echo "export class Svc { run(): void { return } }"; } > "$OT/big.ts"
pt=$(QUIET_OUTLINE_MIN_BYTES=30000 "$QO" "$OT/big.ts"); printf '%s' "$pt" | grep -q 'export function fn1' && pass "ts outlined" || bad "ts outline"
# Go
{ echo "package main"; echo "import \"fmt\""; for i in $(seq 1 400); do echo "func Fn${i}() int { return ${i} }"; done; echo "type T struct { x int }"; } > "$OT/big.go"
pg=$(QUIET_OUTLINE_MIN_BYTES=30000 "$QO" "$OT/big.go"); printf '%s' "$pg" | grep -q 'func Fn1' && pass "go outlined" || bad "go outline"
# Rust
{ echo "use std::io;"; for i in $(seq 1 400); do echo "pub fn fn${i}() -> i32 { ${i} }"; done; echo "struct S { x: i32 }"; } > "$OT/big.rs"
pr=$(QUIET_OUTLINE_MIN_BYTES=30000 "$QO" "$OT/big.rs"); printf '%s' "$pr" | grep -q 'fn fn1' && pass "rust outlined" || bad "rust outline"
# Java
{ echo "package a;"; echo "public class C {"; for i in $(seq 1 400); do echo "  public int m${i}() { return ${i}; }"; done; echo "}"; } > "$OT/big.java"
pj=$(QUIET_OUTLINE_MIN_BYTES=30000 "$QO" "$OT/big.java"); printf '%s' "$pj" | grep -q 'class C' && pass "java outlined" || bad "java outline"
# Ruby
{ echo "require 'set'"; echo "class C"; for i in $(seq 1 400); do echo "  def m${i}; ${i}; end"; done; echo "end"; } > "$OT/big.rb"
pb=$(QUIET_OUTLINE_MIN_BYTES=30000 "$QO" "$OT/big.rb"); printf '%s' "$pb" | grep -q 'def m1' && pass "ruby outlined" || bad "ruby outline"
# C
{ echo "#include <stdio.h>"; for i in $(seq 1 400); do echo "int fn${i}(int a) { return a + ${i}; }"; done; echo "struct S { int x; };"; } > "$OT/big.c"
pc=$(QUIET_OUTLINE_MIN_BYTES=30000 "$QO" "$OT/big.c"); printf '%s' "$pc" | grep -q 'fn1' && pass "c outlined" || bad "c outline"
rm -rf "$OT"
```

- [ ] **Step 2: Run to verify the new language tests fail**

Run: `bash tests/run.sh 2>&1 | grep -E 'ts outline|go outline|rust outline|java outline|ruby outline|c outline'`
Expected: FAIL for ts/go/rust/java/ruby/c (their extensions currently hit `exec cat`).

- [ ] **Step 3: Extend the `case "$ext"` block in `core/quiet-outline.sh`**

Replace the Python-only `case "$ext" in … *) exec cat "$f" ;; esac` with:

```bash
case "$ext" in
  py) lang="Python"
      sig='^[[:space:]]*(async[[:space:]]+def|def|class)[[:space:]]' ;;
  js|mjs|cjs|jsx|ts|tsx) lang="JS/TS"
      sig='^[[:space:]]*((export([[:space:]]+default)?[[:space:]]+)?(async[[:space:]]+)?(function\*?|class|interface|type|enum)[[:space:]]|(export[[:space:]]+)?(const|let|var)[[:space:]]+[A-Za-z0-9_$]+[[:space:]]*=[[:space:]]*(async[[:space:]]+)?(\(|function|[A-Za-z0-9_$]+[[:space:]]*=>))' ;;
  go) lang="Go"
      sig='^(func|type)[[:space:]]' ;;
  rs) lang="Rust"
      sig='^[[:space:]]*(pub[[:space:]]+)?(async[[:space:]]+)?(fn|struct|enum|trait|impl|mod)[[:space:]]' ;;
  java) lang="Java"
      sig='^[[:space:]]*(public|private|protected|static|final|abstract|class|interface|enum)[[:space:]]' ;;
  kt|kts) lang="Kotlin"
      sig='^[[:space:]]*(fun|class|interface|object|enum|val|var)[[:space:]]' ;;
  scala) lang="Scala"
      sig='^[[:space:]]*(def|class|object|trait|case[[:space:]]+class)[[:space:]]' ;;
  rb) lang="Ruby"
      sig='^[[:space:]]*(def|class|module)[[:space:]]' ;;
  c|h|cc|cpp|cxx|hpp) lang="C/C++"
      sig='^[[:space:]]*(struct|class|enum|typedef)[[:space:]]|^[A-Za-z_][A-Za-z0-9_<>:,*& ]*[[:space:]]+[A-Za-z_][A-Za-z0-9_]*[[:space:]]*\(' ;;
  php) lang="PHP"
      sig='^[[:space:]]*((public|private|protected|static|abstract|final)[[:space:]]+)*(function|class|interface|trait)[[:space:]]' ;;
  swift) lang="Swift"
      sig='^[[:space:]]*((public|private|internal|fileprivate|open|final|static|override)[[:space:]]+)*(func|class|struct|enum|protocol|extension)[[:space:]]' ;;
  *) exec cat "$f" ;;   # not a known source extension → leave it
esac
```

- [ ] **Step 4: Run the test to verify all languages pass**

Run: `bash tests/run.sh 2>&1 | grep -A24 'source-file outlining'`
Expected: every language assertion shows `ok`.

- [ ] **Step 5: shellcheck**

Run: `shellcheck -S error core/quiet-outline.sh && echo clean`
Expected: `clean`

- [ ] **Step 6: Commit**

```bash
git add core/quiet-outline.sh tests/run.sh
git commit -m "feat(outline): add JS/TS, Go, Rust, JVM, Ruby, C/C++, PHP, Swift"
```

---

### Task 3: Wire into the Bash read path (`quiet_rewrite`)

**Files:**
- Modify: `core/quiet-core.sh` (the `quiet_rewrite` function — double-wrap guard ~line 149, and a new branch after the JSON/YAML branch ~line 178)
- Test: `tests/run.sh` (extend the outlining block)

**Interfaces:**
- Consumes: `core/quiet-outline.sh` (Task 1/2), `QUIET_OUTLINE_MIN_BYTES`, `QUIET_CORE_DIR`.
- Produces: `quiet_rewrite "cat big.py"` prints `<QUIET_CORE_DIR>/quiet-outline.sh big.py` and returns 0; piped/redirected/small-file/non-source reads still return 1 (pass through).

- [ ] **Step 1: Write the failing tests**

Append inside the `== source-file outlining ==` block (before `rm -rf "$OT"`):

```bash
# quiet_rewrite routes a large source read to the outliner
qr=$(quiet_rewrite "cat $OT/big.py") && printf '%s' "$qr" | grep -q 'quiet-outline.sh' && pass "rewrite routes big.py to outliner" || bad "rewrite big.py"
# piped read is left alone
quiet_rewrite "cat $OT/big.py | grep def" >/dev/null && bad "piped read should pass through" || pass "piped source read passes through"
# small source file is left alone
echo "def tiny(): pass" > "$OT/tiny.py"
quiet_rewrite "cat $OT/tiny.py" >/dev/null && bad "small file should pass through" || pass "small source read passes through"
```

(Note: this test references `$OT/big.py`, created earlier in Task 1's block; keep the `rm -rf "$OT"` as the last line of the whole outlining block.)

- [ ] **Step 2: Run to verify failure**

Run: `bash tests/run.sh 2>&1 | grep -E 'rewrite big.py|piped source|small source'`
Expected: "rewrite big.py" FAILs (no branch yet).

- [ ] **Step 3: Add `quiet-outline.sh` to the double-wrap guard**

In `core/quiet-core.sh`, change the guard case (currently):

```bash
    *__log=* | *"${QUIET_LOG_PREFIX}"* | *quiet-json.sh*) return 1 ;;
```

to:

```bash
    *__log=* | *"${QUIET_LOG_PREFIX}"* | *quiet-json.sh* | *quiet-outline.sh*) return 1 ;;
```

- [ ] **Step 4: Add the source-outline branch to `quiet_rewrite`**

In `core/quiet-core.sh`, immediately AFTER the closing `esac` of the JSON/YAML branch (the block that ends the `case "$cmd" in *'|'* … esac` at ~line 178) and BEFORE the `# ── git path` comment, insert:

```bash
  # ── Source-file outline: large code file read → signature skeleton ──
  case "$cmd" in
    *'|'* | *'>'*) : ;;   # piped/redirected → skip
    *)
      local sfile
      sfile=$(printf '%s' "$cmd" | grep -oE '[^[:space:]]+\.(py|js|mjs|cjs|jsx|ts|tsx|go|rs|java|kt|kts|scala|rb|c|h|cc|cpp|cxx|hpp|php|swift)' | head -1)
      if [ -n "$sfile" ] && [ -f "$sfile" ] \
         && [ "$(wc -c <"$sfile" 2>/dev/null || echo 0)" -gt "${QUIET_OUTLINE_MIN_BYTES}" ] \
         && printf '%s' "$cmd" | grep -qE '(^|[[:space:];&|(])(cat|bat|less|more|head|tail)[[:space:]]'; then
        printf '%q %q' "${QUIET_CORE_DIR}/quiet-outline.sh" "$sfile"
        return 0
      fi
      ;;
  esac
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `bash tests/run.sh 2>&1 | grep -E 'rewrite big.py|piped source|small source'`
Expected: all three `ok`.

- [ ] **Step 6: Confirm no regression in existing pass-through tests**

Run: `bash tests/run.sh 2>&1 | tail -3`
Expected: `ALL TESTS PASSED`

- [ ] **Step 7: shellcheck**

Run: `shellcheck -S error core/quiet-core.sh && echo clean`
Expected: `clean`

- [ ] **Step 8: Commit**

```bash
git add core/quiet-core.sh tests/run.sh
git commit -m "feat(outline): route large source reads through quiet_rewrite (Bash path)"
```

---

### Task 4: Wire into the native Read path (PostToolUse adapter)

**Files:**
- Modify: `adapters/claude-code-result.sh` (add a source-outline branch before the `quiet_result_summarize` call)
- Test: `tests/run.sh` (extend the outlining block)

**Interfaces:**
- Consumes: `core/quiet-outline.sh`, `QUIET_OUTLINE_MIN_BYTES`, and `$ROOT` (already defined at the top of the adapter).
- Produces: a PostToolUse payload whose `tool_input.path` (or `.file_path`) points at a large source file yields an `updatedToolOutput` containing the outline; everything else is unchanged.

- [ ] **Step 1: Write the failing test**

Append inside the outlining block (before `rm -rf "$OT"`):

```bash
# Native Read path: tool_input.path to a large source file → outline in updatedToolOutput
CR="$ROOT/adapters/claude-code-result.sh"
content=$(cat "$OT/big.py")
payload=$(jq -n --arg p "$OT/big.py" --arg c "$content" '{tool_name:"Read", tool_input:{path:$p}, tool_response:$c}')
ro=$(printf '%s' "$payload" | QUIET_OUTLINE_MIN_BYTES=30000 "$CR")
printf '%s' "$ro" | jq -r '.hookSpecificOutput.updatedToolOutput' 2>/dev/null | grep -q 'outline' \
  && pass "native Read of big.py is outlined" || bad "native Read outline"
```

- [ ] **Step 2: Run to verify failure**

Run: `bash tests/run.sh 2>&1 | grep 'native Read'`
Expected: FAIL (adapter doesn't outline yet — it would head/tail instead).

- [ ] **Step 3: Add the source-outline branch to the adapter**

In `adapters/claude-code-result.sh`, find the line that computes the summary (it reads `summary=$(quiet_result_summarize "$text" "$tool") || exit 0`). Immediately BEFORE that line, insert:

```bash
# Source-file outline: if this was a read of a large source file, outline the real file.
summary=""
path=$(printf '%s' "$input" | jq -r '.tool_input.path // .tool_input.file_path // empty' 2>/dev/null)
if [ -n "$path" ] && [ -f "$path" ]; then
  case "${path##*.}" in
    py|js|mjs|cjs|jsx|ts|tsx|go|rs|java|kt|kts|scala|rb|c|h|cc|cpp|cxx|hpp|php|swift)
      if [ "$(wc -c <"$path" 2>/dev/null || echo 0)" -gt "${QUIET_OUTLINE_MIN_BYTES}" ]; then
        osum=$("$ROOT/core/quiet-outline.sh" "$path")
        case "$osum" in '[quiet-bash]'*) summary="$osum" ;; esac
      fi ;;
  esac
fi
```

Then change the existing summary line to only run when the outline did not fire:

```bash
[ -z "$summary" ] && { summary=$(quiet_result_summarize "$text" "$tool") || exit 0; }
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash tests/run.sh 2>&1 | grep 'native Read'`
Expected: `ok   native Read of big.py is outlined`

- [ ] **Step 5: Verify the whole suite is green**

Run: `bash tests/run.sh 2>&1 | tail -3`
Expected: `ALL TESTS PASSED`

- [ ] **Step 6: shellcheck**

Run: `shellcheck -S error adapters/claude-code-result.sh && echo clean`
Expected: `clean`

- [ ] **Step 7: Commit**

```bash
git add adapters/claude-code-result.sh tests/run.sh
git commit -m "feat(outline): outline large source reads on the native Read path"
```

---

### Task 5: Documentation, version bump, and final gate

**Files:**
- Modify: `README.md` (the "What it covers" table + a short subsection; the Configuration list)
- Modify: `CHANGELOG.md` (new version entry)
- Modify: version fields in `.claude-plugin/plugin.json`, `.github/plugin/marketplace.json`, `gemini-extension.json`, `.codex-plugin/plugin.json`

**Interfaces:**
- Consumes: nothing new.
- Produces: a released, documented feature at the next minor version (current is `1.14.0` → `1.15.0`).

- [ ] **Step 1: Add a row to the "What it covers" table in `README.md`**

Add immediately after the large-JSON/YAML row:

```markdown
| **Large source files** (`cat`/`Read` of a `.py`/`.ts`/`.go`/`.rs`/`.java`/`.rb`/`.c`/… file > 30 KB) | Signature outline: imports + class/function/method signatures with bodies elided, each with the exact line range to expand (`Read <file> offset=S limit=N`). File untouched on disk. < 3 symbols → falls back to head/tail. |
```

- [ ] **Step 2: Add a subsection to `README.md`**

After the `### Querying without re-reading (quiet-query)` section, add:

```markdown
### Outlining large source files

Reading a 1,800-line module dumps thousands of tokens the agent mostly skims —
and because the transcript is re-sent every turn, that file is re-billed on every
later turn. quiet-bash rewrites a large source-file read into a **signature
outline**: imports plus class/function/method signatures, bodies elided, each
annotated with the exact line range. The agent expands any body with a single
`Read <file> offset=<start> limit=<n>` (or `sed -n 'S,Ep' <file>`). The file is
never modified — it *is* the byte-exact backup.

Zero dependencies: symbols are found with `grep`/`awk` (no tree-sitter or ctags
required). Covers Python, JS/TS, Go, Rust, Java/Kotlin/Scala, Ruby, C/C++, PHP,
and Swift. Guards against regression: only files over `QUIET_OUTLINE_MIN_BYTES`
(default 30000) are outlined, only known source extensions, and a file with
fewer than `QUIET_OUTLINE_MIN_SYMBOLS` (default 3) symbols falls back to the
normal head/tail preview.
```

- [ ] **Step 3: Document the config knobs in `README.md`**

In the Configuration section, add:

```markdown
- `QUIET_OUTLINE_MIN_BYTES` (default 30000) — outline source files larger than this.
- `QUIET_OUTLINE_MIN_SYMBOLS` (default 3) — below this many symbols, skip outlining.
```

- [ ] **Step 4: Add the CHANGELOG entry**

At the top of `CHANGELOG.md` (above `## [1.14.0]`):

```markdown
## [1.15.0] — 2026-06-23

### Added
- **Source-file outlining** (`core/quiet-outline.sh`): large source reads
  (`.py`/`.ts`/`.go`/`.rs`/`.java`/`.rb`/`.c`/… > 30 KB) are replaced by a
  zero-dependency signature skeleton — imports + class/function/method
  signatures with bodies elided, each with the exact line range to expand
  (`Read <file> offset=S limit=N`). Wired into both the Bash `cat` path
  (`quiet_rewrite`) and the native `Read` path (PostToolUse adapter). The file
  on disk is the byte-exact backup; no spill is created. Guards: size threshold,
  source-extension allowlist, and a symbol-count floor (falls back to head/tail).
  New knobs `QUIET_OUTLINE_MIN_BYTES` (30000), `QUIET_OUTLINE_MIN_SYMBOLS` (3).
```

- [ ] **Step 5: Bump the version in all manifests**

Run (verify each file afterward):

```bash
cd /Users/yoeld/projects/claude-quiet-bash
for fjson in .claude-plugin/plugin.json .github/plugin/marketplace.json gemini-extension.json .codex-plugin/plugin.json; do
  tmp=$(mktemp); jq '(.version // .. ) ' "$fjson" >/dev/null 2>&1
  sed -i '' 's/"1\.14\.0"/"1.15.0"/' "$fjson" 2>/dev/null || sed -i 's/"1\.14\.0"/"1.15.0"/' "$fjson"
done
grep -RHo '"version"[^,]*' .claude-plugin/plugin.json .github/plugin/marketplace.json gemini-extension.json .codex-plugin/plugin.json
```
Expected: each shows `"version": "1.15.0"` (or the marketplace's nested version field updated).

- [ ] **Step 6: Run the final gate**

Run:
```bash
cd /Users/yoeld/projects/claude-quiet-bash
shellcheck -S error core/*.sh adapters/*.sh tests/*.sh install.sh && echo "shellcheck clean"
bash tests/run.sh 2>&1 | tail -3
for f in .claude-plugin/plugin.json .github/plugin/marketplace.json gemini-extension.json .codex-plugin/plugin.json; do jq -e . "$f" >/dev/null && echo "ok $f"; done
```
Expected: `shellcheck clean`, `ALL TESTS PASSED`, and `ok` for each JSON manifest.

- [ ] **Step 7: Commit**

```bash
git add README.md CHANGELOG.md .claude-plugin/plugin.json .github/plugin/marketplace.json gemini-extension.json .codex-plugin/plugin.json
git commit -m "docs+release: source-file outlining (v1.15.0)"
```

---

## Self-Review

**Spec coverage:**
- Core `quiet-outline.sh` mirroring `quiet-json.sh` → Task 1. ✓
- Zero-dep regex engine, all listed languages → Tasks 1–2. ✓
- Output format (imports collapse, signature + body range, footer with Read+sed idioms) → Task 1 implementation. ✓
- Bash read-path integration via `quiet_rewrite` → Task 3. ✓
- Native Read-path integration via adapter + `tool_input.path` → Task 4. ✓
- No-spill design (file is the backup; drill-in references `$f`) → Task 1 footer. ✓
- Regression guards: threshold, extension allowlist, symbol floor → Tasks 1 (floor/ext) + 3/4 (threshold). ✓
- Cache-safety (tail-only, deterministic) → inherent to both integration points; no history edits. ✓
- Config knobs `QUIET_OUTLINE_MIN_BYTES` / `QUIET_OUTLINE_MIN_SYMBOLS` → Task 1 + documented Task 5. ✓
- Testing strategy (per-language, threshold, symbol floor, range correctness, both paths, no-deps) → Tasks 1–4 tests. ✓
- Docs + version bump → Task 5. ✓

**Placeholder scan:** No TBD/TODO; every code step contains complete code; every test step contains real assertions. ✓

**Type/name consistency:** `quiet-outline.sh`, `QUIET_OUTLINE_MIN_BYTES`, `QUIET_OUTLINE_MIN_SYMBOLS`, the `@@FALLBACK@@`/`@@META@@` sentinels, and the extension allowlist are spelled identically across all tasks. The adapter uses the same `[quiet-bash]`-prefix guard the outliner emits. ✓
