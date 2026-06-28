# Frontier build — design spec (quiet-patch, quiet-applies, dfirst-audit)

**Status:** design spec
**Date:** 2026-06-28
**Research:** `docs/superpowers/research/2026-06-28-frontier-directions.md`; framework `docs/deterministic-first-frontier.md`.

Build the two reachable frontier pieces. Orchestration ships as the research doc
(only `quiet-cache` is buildable and it's deferred). Invariant: **mechanical,
lossless, no extra LLM call, no regression, zero-dependency** (bash + git; auditor
uses python3 like the existing `bench/session-savings.py`).

---

## 1. `quiet-applies` — patch pre-check (highest-confidence, zero Edit overlap)

### Problem
To know whether a diff applies, the model reasons over two file versions
(unreliable — Diff-XYZ). `git apply --check` answers deterministically.

### Mechanism
`core/quiet-applies.sh [-R] [-f FILE]` (diff from `-f` file or stdin):
- git-repo guard (`git rev-parse --is-inside-work-tree`).
- empty/missing input → usage + exit 2.
- `git apply --check [-R] <tmp>`: rc 0 → `[quiet-applies] APPLIES — <n> file(s), +<add> −<del>` (counts from `git apply --numstat`), exit 0; rc≠0 → `[quiet-applies] CONFLICT — <first line of git stderr>`, exit 1.
- Read-only (never writes).

## 2. `quiet-patch` — apply a diff atomically

### Problem
Re-emitting a whole file (or hand-applying a diff) is expensive/fragile. For an
**existing diff blob** or an **atomic multi-file** patch, apply it deterministically.

### Mechanism
`core/quiet-patch.sh [-R] [-f FILE]`:
- git-repo guard; empty/missing → exit 2; read diff into a temp file (stdin is read twice).
- **check first:** `git apply --check [-R] <tmp>`; if it fails → `[quiet-patch] FAIL — does not apply cleanly; no changes written` + git's reason, **exit 1, tree untouched**.
- only then `git apply [-R] <tmp>` → `[quiet-patch] OK — applied <n> file(s), +<add> −<del>`, exit 0.
- **Never** pass `--reject`/`--whitespace=fix` (no partial apply, no `.rej`). `git apply` is all-or-nothing → a bad diff can't corrupt the tree.

### Honest scope (skill nudge)
The native **Edit** tool already handles single small edits — quiet-patch is a
*complement*. The `deterministic-first` SKILL row reaches for it only on:
(1) an existing diff blob (Edit can't consume a diff), (2) atomic multi-file
patches, (3) no-Edit contexts; and always runs `quiet-applies` before reasoning
about fit. Single small edits go back to Edit.

---

## 3. `bench/dfirst-audit.py` — the meta auditor (v1: two reliable detectors)

### Problem / goal
Find where the model did tool-shaped work in real transcripts → surface the next
quiet-bash candidates from data, not brainstorming.

### Mechanism
Extend `bench/session-savings.py` (reuse its glob discovery + per-line JSON parse).
Flatten each session's `tool_use`/`tool_result` events in file order, run detectors,
emit a ranked report. **v1 = the two highest-confidence, structural detectors**
(the rest are documented in the research doc as future, gated tiers — not built v1,
to avoid noisy/vanity output):
- **P4 — toolchain probing → `quiet-env`:** count `Bash` tool_use commands matching
  a version/availability probe (`<rt> --version`/`-v`/`-version`, `which X`,
  `command -v X`). ≥2 in a session = the agent discovered its env by probing.
- **P2 — unchanged re-read → `quiet-dedup`:** a `Read` tool_use of a `file_path`
  already Read earlier in the same session with no intervening `Edit`/`Write` to
  that path = a re-billed re-read.

Report per pattern: sessions hit, total occurrences, the implied lever, and a
"directional" note (no fabricated token totals — billing stays in `bench/run.sh` +
`session-savings.py`). CLI: `bench/dfirst-audit.py [GLOB] [--top N]` (default glob
= session-savings.py's). Honest framing: the value is *candidate discovery* (a
rising pattern with no shipped lever = build it next), not a savings headline.

### Testing (no live `~/.claude` in CI)
Hand-written fixtures `tests/fixtures/transcripts/{probe,reread,clean}.jsonl`;
assert P4 fires on `probe.jsonl` (not `clean`), P2 fires on `reread.jsonl` (not
`clean`), and a malformed line doesn't crash. Run with an explicit glob arg.

---

## Cross-cutting
- **Surface:** README row (apply/check diffs; transcript audit); SKILL.md rows
  ("Apply a diff" → quiet-patch/applies). Keep existing headings/refs intact.
- **Tests** (`tests/run.sh`): quiet-applies (clean diff → APPLIES exit 0; bad diff
  → CONFLICT exit 1; non-git → exit 2; empty → exit 2); quiet-patch (applies a real
  diff to a temp git repo then verifies the file changed; bad diff → FAIL exit 1 +
  tree untouched; usage exit 2); dfirst-audit fixtures.
- **Tasks:** quiet-applies; quiet-patch; dfirst-audit (integration — read
  session-savings.py); docs surface.

## Open questions (resolved)
- v1 flags: `-R` (reverse) + `-f FILE` only (drop `-p`/`--root` — YAGNI; standard
  git diffs apply from repo root at -p1).
- auditor v1: P4 + P2 only; P1/P3/P6/P7 documented as future gated tiers.
