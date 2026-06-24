# Speed & Cost Research — findings (partial)

Captured from three deep-research runs on 2026-06-24. A provider session limit
interrupted the runs, so confidence varies by section — labeled honestly below.
The cost survey and a Claude-Code-CLI-specific run still need a re-run after the
limit resets.

---

## A. Claude latency / context / caching — ✅ VERIFIED (3-0 / 2-1 adversarial votes)

All from official Anthropic docs; independently verified before the limit hit.

### Prompt caching economics
- Cache **reads cost 0.1× base input price** (90% discount); **writes cost 1.25×**
  (5-min TTL) or **2×** (1-hr TTL). — docs.claude.com/.../prompt-caching
- Up to **4 cache breakpoints** per request (via `cache_control` on content
  blocks); the system checks ≤20 positions per breakpoint for a match.
- Default cache TTL is **5 minutes, refreshed free on every use**; 1-hr TTL at
  extra cost; both behave identically for latency.
- **Anything that changes the cached prefix busts it.** Changing thinking
  params invalidates *message-level* cache breakpoints (system + tools stay
  cached).

### Context editing (`clear_tool_uses_20250919`)
- Auto-clears **oldest tool results** once context exceeds a threshold, leaving
  placeholder text. Built for heavy-tool-use agents.
- Defaults: **trigger 100,000 input tokens, keep 3 most recent** tool
  use/result pairs; tunable via `clear_at_least`, `exclude_tools`; trigger can
  be lowered (e.g. 30k) for more aggressive clearing.
- **Clearing tool results invalidates the cache prefix → costs a cache-write.**
  Use `clear_at_least` to clear enough that the re-cache pays off. (This is the
  same cache-discipline constraint from `docs/token-reduction-research.md` —
  now confirmed against the docs.)

### Latency levers
- **Haiku 4.5** (`claude-haiku-4-5`) is the fastest model for speed-critical
  work while keeping high intelligence.
- **Fewer input + output tokens → lower latency** (less to process and
  generate). This is the core quiet-bash thesis, restated by Anthropic.
- **Streaming** (`"stream": true`, SSE) improves perceived latency
  (time-to-first-token).
- Extended thinking: `display:"omitted"` gives **faster TTFT but NOT lower
  cost** (full thinking tokens still billed). `budget_tokens` must be <
  `max_tokens`; Claude often won't use the full budget above ~32k.

**Actionable for quiet-bash:** reinforces the cache-discipline direction — keep
rewrites at the transcript tail (don't bust the cached prefix), and if we ever
do cross-turn masking, gate it behind a `clear_at_least`-style token threshold.

---

## B-VERIFIED. Claude Code hook `if` field — checked against the docs, REJECTED as low-fit

Confirmed real (code.claude.com/docs/en/hooks + /permissions): hooks support an
optional **`if`** field that filters with **permission-rule syntax**
(gitignore-style globs, e.g. `Read(*.py)`, `Bash(git *)`) and **short-circuits
before the command process spawns**. `async`/`asyncRewake` also exist (not usable
for our rewrite hooks — they must be synchronous).

**Decision: do NOT use `if`-gating in quiet-bash.** Reasons:
- It matches only **static** patterns; quiet-bash's decisions are **runtime**
  (`cat *.json` only if >25 KB; outline only if >30 KB; the large verbose-command
  set). Permission globs can't see file size or output content.
- **No brace expansion** (`Read(*.{py,ts})` unsupported) — covering ~22 source
  extensions would need ~22 separate hook entries.
- Gating the **Bash** hook is unsafe: an incomplete `if` pattern would miss
  quieting a big log (a real regression, worse than a wasted spawn).
- Gating the **Read** hook is the only legal target, but saves only the ~40 ms
  spawn on non-source reads — latency already invisible vs the LLM turn.

The `if` field is excellent for its actual purpose (security gating); it's just a
poor fit for quiet-bash's runtime-conditional logic.

## B-LEADS. Other shell-hook latency leads — NOT VERIFIED THIS RUN

The verification agents failed on the session limit (votes came back `0-0`,
which the harness mislabeled as "refuted" — they were *not* disproven, just
un-checked). Sources are credible (Claude Code docs, jaq, bats-core). Treat as
leads to confirm, not facts.

- **Two Claude Code hook leads worth verifying against current docs:**
  - An **`if` condition field** may short-circuit a hook *before the process
    spawns* — could skip quiet-bash's ~40 ms entirely for non-matching calls.
  - **`async: true`** runs a hook in the background — but **NOT usable for our
    rewrite hooks** (they must be synchronous to replace output before it enters
    context). Confirms the earlier "async is impossible for the rewrite path."
- `jq` startup is already fast in 1.7+ (~0.5–0.85 ms/call on a startup
  benchmark); **gojq** is the startup winner — but the gain is sub-millisecond,
  not worth a dependency.
- One `jq` call can emit multiple fields via the comma operator — **already
  applied** in v1.15.2's single-pass adapter extraction.
- Avoiding subshells/forks gave 23–43% in *test-suite* contexts; `$(<file)` over
  `$(cat file)`; spawn by absolute path over PATH search. Micro-gains.
- A pure-shell JSON parser (JSON.sh) is possible but has incomplete
  escape/Unicode handling — correctness tradeoff vs jq.
- Daemon/persistent-helper amortizes startup (15–75% on repeated runs, Gradle
  analogy) but is heavy/risky for editor hooks.

**Actionable for quiet-bash:** verify the `if`-condition hook field — if real,
it's the cleanest further speedup (skip the hook at ~0 cost when irrelevant).
Everything else is sub-ms or not worth the dependency/complexity, consistent
with the "don't rewrite in Rust" conclusion.

---

## B-POC. Compiled (Rust/Go) outliner vs shell — MEASURED 2026-06-24

Built a Go outliner (Rust stand-in: native binary, native regex, ~fast startup)
replicating `quiet-outline.sh`'s Python logic; identical output (164 symbols,
same ranges). Benchmarked vs the shell grep+awk pipeline:

| File | shell (grep+awk) | compiled | speedup |
|---|---|---|---|
| 135 KB real `.py` (164 sym) | 94.6 ms | 8.5 ms | **11.1×** |
| 860 KB huge `.py` (20k sym) | 316.3 ms | 19.4 ms | **16.3×** |

**Conclusion:** compiled is genuinely ~11–16× faster on the outliner (the one
compute-bound path) — but the absolute saving (~85–300 ms, on the infrequent
large-source-read path) is invisible against the multi-second LLM turn, and a
compiled binary would cost the zero-dep / drop-in / auditable-shell identity
(per-platform builds + release pipeline + binary trust). Verdict: keep shell as
the default. If ever wanted, ship a compiled binary as an **optional accelerator**
(use-if-present, shell fallback), like the ctags/tree-sitter ladder. NOT for the
hook dispatch — that was fork-bound and already fixed in shell (v1.16.1).

## C. Cost-saving survey — ❌ NO DATA (re-run needed)

The cost workflow fetched 0 sources (all failed on the limit). Re-run after the
limit resets. Intended scope: token reduction, prompt/response caching, model
routing/cascades (RouteLLM), semantic caching (GPTCache), batching/pricing
(Message Batches API), and OSS cost tooling (LiteLLM, Helicone, Langfuse) — each
with lossless-vs-lossy labeling and reported savings.

---

## Re-run after the session limit resets
- Cost-saving survey (Section C) — fresh run.
- Claude Code CLI speed — a Claude-Code-specific run (the earlier run was
  mis-scoped to "cloud"; this run also failed on the limit).
