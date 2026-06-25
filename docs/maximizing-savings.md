# Maximizing savings: stack the lossless levers

No single *lossless* technique cuts agent cost/latency by more than ~25–30% on
real coding work — "build less" (anti-over-engineering) is about the ceiling for
one lever. To go further **without regression**, stack levers that target
**different token categories** so they compound instead of overlap.

## The stack (each independently low/no-regression)

| Lever | Tool | What it cuts | Rough effect | Regression risk |
|---|---|---|---|---|
| Keep verbose command/file output out of context | **quiet-bash hooks** | **input** tokens (re-sent every turn) | up to ~99% of command output; ~15–50% of a log-heavy session's tokens | none — full payload spilled to disk, byte-exact |
| Terser generation | **quiet-bash `Concise` output style** | **output** tokens (priced 3–5×, serial) | ~10% faster, ~10–15% smaller output | low — no-loss guardrails, measured no content lost |
| Build less code | **ponytail** (separate plugin) | **generated code** → output + downstream input | ~−20% cost, ~−27% time, ~54% less code (their benchmark) | low — keeps safety/validation 100% |
| Drop stale tool results / defer tool schemas | **Anthropic native** (context-editing, Tool Search) | **history + tool-def** bloat | up to ~84% on long tool-heavy sessions (their numbers) | low — placeholders + on-demand reload |
| Reuse the cached prefix | **Anthropic prompt caching** | **input** re-processing | cache reads = 0.1× input price | none — built-in |

## Why they stack (and don't double-count)

- **quiet-bash** removes verbose *tool output* from context. **ponytail** reduces
  the *code the agent writes*. **Concise** trims the *prose Claude generates*.
  Three different sources → largely additive on their own slices.
- **Caching** and **context-editing** operate on the *history* layer, orthogonal
  to the above.

The combined effect is **sub-additive** (some overlap — e.g. ponytail and Concise
both touch output), so don't expect 10%+27%+… to literally sum. Realistically,
stacking lands well above any single lever — but the exact number depends on your
workload (log-heavy vs generation-heavy). **Measure on your own repo**, don't
trust a headline.

## Enable the stack

1. **quiet-bash hooks** — install the plugin (default on).
2. **Concise output style** — `/config` → Output style → **Concise**.
3. **ponytail** — `/plugin marketplace add DietrichGebert/ponytail` →
   `/plugin install ponytail@ponytail` (complementary, no overlap with quiet-bash).
4. **Prompt caching** — on by default in Claude Code.
5. **Context editing** — enable `clear_tool_uses` (Agent SDK / API) for long
   tool-heavy sessions; gate with `clear_at_least` so clears beat the cache-write.

## The honest ceiling

Beyond stacking, the remaining levers all trade away something: model-routing to
cheaper models risks quality; aggressive prompt compression (LLMLingua) drops
load-bearing tokens; a compiled rewrite or daemon buys invisible per-call ms at
the cost of the zero-dependency design. Stacking lossless levers is the
no-regression frontier.
