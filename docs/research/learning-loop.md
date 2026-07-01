# From quieting to learning — a recognize → crystallize → reuse loop for quiet-bash

*Research report · June 2026 · for the quiet-bash maintainer · broad exploration, not a committed spec*

**The idea, in one line.** Today quiet-bash *shrinks* each result the moment it's produced. The
next step is to make it *learn*: **observe** where an agent's tokens actually go, **recognize**
the recurring expensive work, **crystallize** that work into the cheapest deterministic artifact
that still covers it — a cached result, a script, a hook, a markdown **skill**, or an **MCP
tool** — **verify** the artifact is safe, then **reuse** it so the same work runs deterministically
and nearly free next time. And keep the loop **open**: artifacts are continuously re-checked,
updated when the pattern drifts, and retired when they go stale.

This generalizes the earlier "cache the answer" framing in two ways the maintainer asked for:

1. **Not tied to one tool.** It's a generic loop over *any* recurring tool-use pattern, keyed by
   a fingerprint, not a hand-coded list of commands.
2. **Cache the *procedure*, not just the *answer*.** Re-serving a cached result is the simplest
   rung. The richer rungs *compile a repeated LLM-driven loop into a deterministic artifact* — a
   script/hook/skill/MCP — so future runs skip the model entirely. This is the "meta-tool" /
   "tool-maker → tool-user" pattern from the literature (LATM, AWO, Voyager).

**Relationship to what's shipped.** `quiet-dedup.sh` (suppress unchanged re-reads, one session)
and the existing summarize-on-emit behavior are the *zeroth* rungs of this same ladder — they
already recognize-and-reuse within a session. This doc widens all three axes: from *file reads*
to *any operation*, from *one session* to *persistent/cross-repo*, and from *re-serving bytes*
to *crystallizing procedures*.

---

## 1. The crystallization ladder (the core new framing)

When a recurring expensive pattern is recognized, it should be crystallized into the **lowest
rung that still covers the pattern's variability**. Lower rungs are cheaper, safer, and more
deterministic; higher rungs handle more variability at the cost of needing synthesis and trust.

| Rung | Artifact | Determinism | Covers | Synthesis cost | Retrieval |
|---|---|---|---|---|---|
| 0 | **Cached result** | total | identical inputs recur | none (just store) | exact key match |
| 1 | **Script** (`quiet-*`) | total | a fixed deterministic procedure (parse, count, extract) | mechanical template, or LLM-once | exact / name |
| 2 | **Hook** | total at exec | intercept a known op, serve deterministic result, no LLM | mechanical or LLM-once | pattern match in hook |
| 3 | **Skill (`.md`)** | model-guided | a repeated *workflow* that still needs LLM judgment, made cheaper/consistent | LLM-synthesized from traces; human-reviewable | progressive disclosure (name+desc → body) |
| 4 | **MCP tool** | total at exec | a parameterized operation callable as a tool, file/db-backed | LLM-synthesized + verified | vector-db embedding + name/docstring |

The rule of thumb (from CRAFT/AWO): **choose the least-intelligent representation that still
covers the pattern.** Fully deterministic + no params → rung 0–2. Parameterized → rung 4. Needs
the model's judgment but can be guided → rung 3. The economics is LATM's "tool-maker vs
tool-user": spend a *strong* model once to *make* the artifact, then a *cheap* path (or pure
runtime) *uses* it many times — LATM reports up to **79% lower per-instance cost** this way.

### 1.1 Two tracks: executable *and* instructional

Not every crystallization is code. An artifact can save tokens in one of two ways, and the
crystallizer should choose across *both*:

- **Executable (deterministic) track** — runs with **no model at execution**: a cached result, a
  script, a hook, an MCP tool. The work itself is replaced.
- **Instructional (guidance) track** — a **non-AI instruction**: learning captured *once* as plain
  text the agent reads and follows next time, with **no AI call needed to regenerate it**. The model
  still does the task, but it follows a proven recipe instead of re-deriving the approach. Cheaper
  and more reliable than re-reasoning; safe where the work needs judgment a script can't encode.

The instructional track has two delivery modes, differing only in *how the guidance reaches the
next session*:

| Instructional artifact | Delivery | Carrying cost | Best for |
|---|---|---|---|
| **Recipe / playbook** (incl. a skill body) | **retrieved** just-in-time when relevant (progressive disclosure / vector-db) | ~0 until loaded | task-specific how-tos — *"to find a specific log, grep `logs/` for the request-id, read ±20 lines"* |
| **Injected instruction** (`CLAUDE.md` / `AGENTS.md` / memory) | **always-on**, auto-loaded at session start, no retrieval | permanent, every session | broadly-applicable, high-value rules the agent should *always* know |

The **skill (rung 3) is the hinge** between the tracks: its body is an instruction, its bundled
script is executable. Prefer the lowest-carrying-cost option that works — a deterministic artifact
if the work is mechanical, a retrieved recipe if it needs judgment, an injected instruction *only*
when the learning is valuable enough to pay a permanent per-session tax (§12).

A cost subtlety that matters (§5, §12): an **injected** instruction lands in the *stable system
prefix at session start*, so it's **prompt-cache-friendly** — but it bills every session forever. A
**retrieved** recipe costs nothing until needed. So **inject sparingly, retrieve by default.** Both
kinds earn reputation from real use exactly like executable artifacts (§13).

---

## 2. The loop: six stages, narrow interfaces

```
 tool calls ─▶ [1 OBSERVE] ledger: {fingerprint, tokens, cost, inputs, ts}
                   │
                   ▼
             [2 RECOGNIZE] frequency-threshold trace mining → recurrence × cost ranking
                   │
                   ▼
             [3 CRYSTALLIZE] pick rung 0–4 · synthesize (mechanical | LLM | HITL)
                   │
                   ▼
             [4 VERIFY] differential test vs golden · sandbox · sign/pin → promote
                   │
                   ▼
             [5 REUSE] retrieve (exact key | vector-db | progressive disclosure) · serve cache-safe
                   │
                   ▼
             [6 MAINTAIN] shadow re-check · invalidate on drift · retire · re-learn
```

Each stage is independently useful and independently shippable. Stage 1 alone is a measurement
tool; 1–2 alone are a "what's worth crystallizing" report; 3+ is where tokens are actually saved.
The discipline throughout: **promotion is slow and evidence-gated; demotion is instant and
automatic** — a drifting artifact must fail *safe* (fall back to the LLM), never serve stale or
poisoned behavior.

---

## 3. Stage 1 — Observe

Every mature LLM-observability tool (LangSmith, Langfuse, Helicone, Phoenix, the OpenTelemetry
GenAI conventions) uses **one record per operation**, token counts attached, cost derived as
`tokens × price`. None cluster by *operation content* — they segment by model/tool/user/session
or a manual tag. **That content-clustering gap is the fingerprint** (§4).

quiet-bash already sits at the boundary (the `PostToolUse` path in `quiet-core.sh` sees every
command + output). The observability layer appends one ledger row per tool call:

```json
{"fp":"a1b2c3d4","tool":"Bash","canon":"npm test","tok_in":21,"tok_out":0,
 "bytes":40660,"inputs":["pkg.json:9f2","src/**:hash"],"ts":1750000000,"repo":"quiet-bash"}
```

- **Tokens:** usage payload when available, else `bytes/4` (already used in bench) for portability
  across the 8 supported agents.
- **Cost:** `tok_in·price_in + tok_out·price_out`, derived, never stored as truth.
- **Storage:** the **sqlite** tier (§8) — cheap `GROUP BY fingerprint` ranking. Pure append, off
  the hot path, **never edits the transcript → zero prompt-cache impact**.

Stage 1 is valuable alone: it finally answers *"where did this session's tokens actually go?"*.

---

## 4. Stage 2 — Recognize

**When are two operations "the same"?** Too strict → nothing recurs; too loose → wrong reuse.
Two mature normalization traditions transfer directly:

- **SQL query fingerprinting** — collapse literals to typed placeholders, normalize
  whitespace/case → a stable "shape" (`WHERE id=42` ≡ `WHERE id=99`).
- **Drain log-template parsing** — a fixed-depth parse tree masks variable tokens.

Applied per tool family:

| Family | Canonical form | Clusters |
|---|---|---|
| **Bash** | `argv[0]` + flag *names*; literals → `<PATH>`/`<NUM>`/`<HASH>`/`<URL>`/`<STR>`; sort order-independent flags; drop post-pager tail | `grep -n "foo" a.ts` ≡ `grep -n "bar" b.ts` |
| **Read/Edit** | `tool + dirname + ext`, ranges dropped | reads of `.ts` in `src/` |
| **MCP/other** | `tool + sorted(arg_keys)`, values → type placeholders | same call shape |

`fingerprint = sha1(canonical)[:12]`. Then **trace mining + a frequency threshold T**, exactly as
in AWO (Microsoft, arXiv 2601.22037): build a state graph from past runs, merge equivalent
states, keep only sub-sequences with weight ≥ T, and rank by **recurrence × cost**. AWO turns the
survivors into deterministic composite "meta-tools" and reports **5.6–11.9% fewer LLM calls,
+4.2pp success, 4.2–15% cost reduction**. The top of that ranking *is* the crystallization queue.

**Single calls vs. sequences.** A "pattern" isn't always one call. The richest crystallization
targets are recurring *multi-step sequences* — the read → edit → run-tests loop, or the "find
which file logs X, grep it, extract the line" dance. AWO's state-graph merge recognizes these by
collapsing semantically equivalent states; the recurring sub-path becomes one artifact that
replaces the whole loop. Single-call patterns crystallize to rungs 0–2; recurring *sequences*
are what become rung-3 skills and rung-4 tools.

**Variability analysis decides the rung.** Within a fingerprint cluster, separate what's *fixed*
from what *varies*: the varying slots (`<PATH>`, `<STR>`, a range) become the artifact's
**parameters**; the fixed structure becomes its body. No variation → rung 0–2 (cache/script);
a few typed parameters → rung 4 (a parameterized MCP tool); variation that needs judgment →
rung 3 (a skill that guides the model). This is the mechanical bridge from "a recognized pattern"
to "a typed tool signature."

Crucial: **the fingerprint is for visibility, never for keying a served result.** It's
intentionally coarser than the cache key (§5.1) — coarse fingerprints make recurrence *visible*;
a precise input-addressed key makes reuse *sound*.

---

## 5. Stage 3 — Crystallize: the synthesis spectrum

The maintainer wants the whole spectrum, not one mechanism. The prior art lays it out as a
continuum of *how much intelligence is spent at crystallization time*:

- **Mechanical (templates only).** AWO-style: mine a frequent deterministic tool-call sequence,
  emit a composite script/hook with zero LLM at execution *and* zero LLM at synthesis. Safest,
  limited to fully deterministic patterns. → rungs 0–2.
- **LLM-synthesized once, then deterministic.** LATM / CREATOR / CRAFT / Voyager: a strong model
  *abstracts* a verified, deduplicated function/tool from observed traces; a cheap path or pure
  runtime executes it forever. → rungs 1, 4 (and code-bearing skills). This is where most of the
  saving lives (LATM's 79%).
- **Human-in-the-loop / declarative.** Anthropic **Agent Skills** (open standard, Dec 2025):
  package a repeated procedure as `SKILL.md` (YAML frontmatter `name`/`description` + body +
  optional bundled scripts), authored or reviewed by a person. → rung 3.

These are not exclusive — a single crystallizer escalates: try mechanical; if the pattern has
parameters/judgment, fall to LLM synthesis; route anything privileged or ambiguous to HITL
approval. **Pick the lowest-intelligence representation that still covers the pattern's
variability**, then verify before trusting.

### 5.1 Keying & invalidation — learn from Bazel/Nix, not from LLM caches

For rung 0 (and any artifact whose *output* is cached), the soundest lossless model is
**input-addressed exact-match keying with implicit invalidation** (Bazel Action Cache, Nix
derivations): the key hashes *every input that affects the output* — command, input-file
content-digests, relevant env, **tool version**, and a **cache-schema version** (Aider bakes
`v3` into its cache path). Any input change → different key → natural miss; entries are never
"stale," they're unreachable.

The universal failure mode is **under-keying** — Bazel's false hits come from *untracked* inputs
(a system compiler, an undeclared env var); LangChain's `SQLiteCache` serves stale answers
because it never invalidates on *model* change. Lesson: **over-include inputs, version the
schema, deny-list anything whose inputs can't be enumerated.**

### 5.2 Rung 4 — generating an MCP tool, the right way

A recognized *parameterized* pattern maps cleanly onto an MCP tool: the fingerprint's varying
slots become the tool's **JSON input schema**, the fixed procedure becomes the handler, and the
file/sqlite/vector-db tiers (§9) are its backing store. Anthropic's tool-writing guidance sets
the bar the generator must hit:

- **Few, richly-scoped tools, not many micro-tools.** Replace `list_x`+`get_x`+`filter_x` with one
  `find_x` that does the whole job — fewer ambiguous decision points, less context.
- **Concise, paginated outputs.** Default to a compact result (Anthropic shows **72 vs 206 tokens**
  for the verbose form, ~⅔ off) with a `detail_level` knob. On-brand for quiet-bash.
- **Strict schemas, self-documenting params** (`user_id`, not `user`); **actionable errors**
  ("Field 'x' not found. Available: a, b, c"), never raw tracebacks.
- **Idempotent & deterministic** — a tool is a contract between a deterministic system and a
  non-deterministic agent; identical inputs must give identical results.
- **Annotations for destructive / open-world access**, and **schema-pinning** (re-verify the
  approved schema on every load — defends the MCP "rug-pull").

### 5.3 Rung 3 — authoring the *best* skill (the LLM's how-to guidance)

The skill is where an LLM writes **guidance for the recurring task itself** — e.g. *"to find a
specific log, grep `logs/` for the request-id, then read ±20 lines"* — so the next session
follows a proven path instead of re-discovering it. Anthropic's skill best-practices set the bar:

- **The `description` is the retrieval key.** Only `name` + `description` stay resident in context;
  write the description in **third person**, stating *what it does AND when to use it*, packed with
  concrete trigger phrases (Claude tends to *under*-trigger). This is literally how the next agent
  *knows what to use*.
- **Thin body, progressive disclosure.** Keep `SKILL.md` < 500 lines; push detail to reference
  files linked one level deep, loaded on demand; bundled scripts cost **zero tokens until run**.
- **Push determinism into bundled scripts** — a generated skill should carry the rung-1/2 script
  that does the deterministic part, and reserve prose for the judgment part.
- **Single responsibility, concrete examples, no time-sensitive text**, generated with ≥3 evals.

So the crystallizer writes a skill as **high-signal description (discovery) + thin how-to body
(the LLM's learned guidance) + bundled deterministic script (the cheap path)**.

---

## 6. Stage 4 — Verify & promote: the trust ladder

An LLM-generated artifact is **untrusted code** until proven. The literature is blunt about how:

- **Earn trust by execution, not assertion.** Voyager admits a generated skill to its library
  only after *environment feedback* + a *critic* confirm it worked.
- **Differential testing is the right gate here.** Capture the original LLM-driven run's output
  as a **golden/snapshot**, then require the generated artifact to reproduce it on the captured
  inputs *and* a held-out sample before promotion.
- **Caveat: agent-*generated* tests are weak validators.** A 2026 SWE-agent study found generated
  tests are 70–77% value-revealing prints, 19–30% fail at process level, and prompting for them
  raised cost ~20% with no resolution gain. Treat generated tests as *supplementary*, not the
  sole gate.

**The trust ladder — `proposed → shadow → trusted → retired`:**

1. **Proposed** — synthesized, **signed + schema-pinned**, runs only in a least-privilege sandbox,
   never relied upon.
2. **Shadow** — runs *in parallel* with the LLM loop on real traffic; outputs differentially
   compared against the LLM golden. Low divergence accrues confidence. (Cost note: shadow pays
   *both* artifact and LLM cost, so the window must be bounded.)
3. **Trusted** — graduates through a bounded canary (1–5% → wider; low-risk ops first) under a
   confidence threshold; high-privilege actions still gated by risk-tiered human approval. Now it
   replaces the LLM loop and the saving materializes.
4. **Retired** — the instant staleness fires (changed upstream, TTL/confidence-decay lapse, or a
   shadow re-run *contradicts* the artifact): auto-disabled, loop falls back to the LLM, pattern
   re-queued for re-learning.

The ladder is deliberately **asymmetric**: slow evidence-gated promotion, instant automatic
demotion → fail safe.

---

## 7. Stage 5 — Reuse: retrieval + cache-safe serving

**Retrieval tiers, matched to the rung:**

- **Rung 0–2 (deterministic):** exact key match (input-addressed) or a hook pattern match. Cheap,
  no model.
- **Rung 4 (MCP tools) & code skills:** **vector-db** embedding index (Voyager retrieves top-5 by
  description embedding; CRAFT does multi-view matching on task + function name + docstring). This
  is the maintainer's "vector db" tier — semantic lookup of *which crystallized artifact fits this
  new task*. Pair embedding recall with a name/docstring precision filter.
- **Rung 3 (skills):** **progressive disclosure** — only `name`+`description` sit in context;
  the full `SKILL.md` body loads when the model judges it relevant; bundled scripts/files load
  only at execution. Hundreds of skills installable at negligible context cost.

**Cache-safe serving (the constraint that governs everything).** All three providers (Anthropic,
OpenAI, Gemini) cache on **longest-exact-prefix**. Editing only the **tail** preserves the cached
prefix; splicing into the **middle** busts everything downstream (0.1× read → 1.0× re-bill + write
surcharge). So:

- ✅ **Serve a hit on a *fresh* tool call** — it lands at the tail, exactly where quiet-bash
  already safely rewrites. The agent is about to run `npm test`; the hook substitutes the cached
  result / invokes the crystallized artifact instead. Tail edit → cache-safe. **This is the
  recommended regime.**
- ⚠️ **Never retroactively rewrite an old result** in v1 — that's Anthropic's `clear_tool_uses`
  invalidation, only worth it behind a "minimum tokens cleared" threshold. Out of scope first cut.

(See `docs/token-reduction-research.md`, "the prompt cache governs whether transcript edits help.")

---

## 8. Stage 6 — Maintain & retire: invalidating *procedures*, not just data

Cache invalidation for a *procedure* needs explicit freshness machinery (agent-memory eviction
taxonomy):

- **Input-addressed** (default): file-touching ops invalidate when an input content-hash/mtime
  changes — nothing to expire.
- **TTL**: for ops with un-enumerable inputs (network, clock).
- **Event-driven**: invalidate on a changed upstream API/source (most correct, most coupled).
- **Contradiction-triggered**: a periodic **shadow re-run** disagrees with the artifact → demote.
- **Confidence decay**: confidence falls unless reinforced by fresh successes.

Every artifact carries **provenance + freshness metadata**, and age is surfaced at retrieval.
Consequential procedures are **re-verified before high-impact use**. Keep a **versioned archive**
(ADAS-style) so artifacts are refined, not just replaced, as new traces arrive — "open to change
and learn more," as requested.

---

## 9. Storage architecture (file + sqlite + vector-db, layered)

Matching the chosen "both layered" + the "vector db" addition:

| Tier | Holds | Why |
|---|---|---|
| **Files** (`.quiet-cache/`, generated `skills/`, `hooks/`, `mcp/`, `recipes/`, plus injected `CLAUDE.md`/`AGENTS.md`/memory) | the artifacts themselves — executable *and* instructional; spilled byte-exact outputs | zero-dependency, git-reviewable, matches quiet-bash ethos; lossless recovery one `Read`/`jq` away |
| **sqlite** | the observability ledger + recurrence ranking | cheap `GROUP BY`/sort for "what's worth crystallizing"; one dependency, local |
| **vector-db** | embeddings of artifact descriptions/patterns | semantic retrieval (Voyager top-k / CRAFT multi-view) for rung-3/4 artifacts where exact match won't find the right tool |

**Scope, layered:** **per-repo** by default (same codebase → same answers; safe, high-signal),
plus an **opt-in global tier** restricted to provably repo-independent artifacts (`node --version`,
`which bazel`, OS facts) on an allowlist — never open, to avoid cross-repo poisoning. Eviction:
LRU + TTL to bound disk.

---

## 10. Security — generated artifacts are untrusted code

Crystallized scripts/hooks/MCP tools run under containment proportional to their origin (MCP
Security Best Practices, OWASP MCP Top 10):

- **Least privilege / scope minimization** — grant only what the recognized pattern needs; start
  read-only, elevate incrementally; run non-root; restrict fs/network.
- **Sign + schema-pin, re-verify on load.** The **MCP "rug pull"** attack approves a benign tool,
  then mutates it post-approval; "full-schema poisoning" hides malice beyond the description. Hash
  the approved artifact/schema and re-check every load; version-pin; treat shell/credential access
  as tier-0.
- **Prompt-injection into generated tools** is a first-class risk — anything synthesized from
  traces that include external content must be sandboxed and human-gated before privileged use.

Containment scales with privilege tier so the friction doesn't eat the very savings the artifact
exists to create.

---

## 11. Mechanical core vs. LLM tiers (keep them strictly separated)

- **Mechanical core (default, lossless).** Rungs 0–2, exact input-addressed keys. A hit means
  byte-identical inputs → correct by construction; only failure mode is a *miss*. No trust needed.
  On-brand: deterministic, zero-dependency.
- **LLM-assisted tiers (opt-in, gated).** Rung 3–4 synthesis, vector-db semantic retrieval, and
  any fuzzy match. Failure mode is **silent wrong answers** (the InfoQ banking study measured a
  *99%* false-positive baseline before guardrails). Non-negotiables: fuzzy *retrieves*, a verifier
  *decides*; confidence-gate not just distance-gate (≈0.90–0.95 floor); category bypass for
  time-sensitive / entity-parameterized / side-effecting / multi-step ops; continuous proof of
  <5% wrong-hit rate or auto-disable.

Recommendation: **ship the mechanical core first; fence every LLM tier off-by-default** behind the
trust ladder. Different risk class, governed differently.

---

## 12. Cost economics — when crystallizing actually pays

Crystallization is an *investment*: a one-time synthesis cost, recovered over many reuses. The
decision rule is a break-even:

```
N_breakeven      = synthesis_cost / per_use_saving
crystallize only when  projected_reuses > N_breakeven
```

This is exactly why **Stage 2 ranks by recurrence × cost** — it estimates the payoff. The
"tool-maker → tool-user" split (LATM) is the same economics: spend a strong (expensive) model
*once* to make the artifact; a cheap path or pure runtime *uses* it — up to **−79% per-instance
cost**.

Three costs the accounting must not ignore:

1. **Synthesis cost** (one-time): the strong-model call that writes the artifact. Amortized over reuses.
2. **Shadow cost** (transient): during shadow the artifact runs *alongside* the LLM loop, so you
   pay **both** — the window must be bounded or it never nets out.
3. **Carrying cost** (ongoing, the subtle one): every resident tool definition / skill description
   costs context tokens **every turn**. Anthropic measured ~**55K tokens for 58 tools** before any
   conversation (134K internally pre-optimization); past a point, extra tools also *degrade
   accuracy* ("context rot"). A resident artifact is a standing tax.

The carrying-cost tax is why **you cannot crystallize everything**, and why retrieval is deferred:
Anthropic's Tool Search loads a ~500-token index instead of ~77K of definitions — an **~85% token
cut that also *raised* tool-use accuracy** (49%→74% on Opus 4). Design consequences:

- Keep only a small **resident index** (names + descriptions); defer full schemas / skill bodies
  behind just-in-time search (the vector-db tier, §9).
- **Net savings = reuse_saving − synthesis − shadow − carrying.** An artifact whose net goes
  negative (rarely used, yet resident) is **evicted**, not kept. Carrying cost makes the active set
  self-pruning.

## 13. Usage feedback & reputation — every reuse is a vote

When an artifact is used — *including by another session or another agent* — that use is a signal.
Each invocation records two things:

- **good-or-not** — did it produce a correct/useful result? (a verifiable check, the agent's
  accept/retry/abandon behavior, or an explicit signal).
- **action cost** — the tokens/time that use actually took.

These accumulate into a per-artifact **reputation**: `success_rate`, `net_tokens_saved`, `uses`,
`last_good`. Reputation then drives three things at once:

- **Retrieval ranking** — the next agent choosing a tool sees the highest-reputation, best-fitting
  artifact first. **Reputation × description-match is the ranking key**, so the next LLM *knows what
  to use* and trusts it for the right reasons.
- **Trust-ladder promotion** — accumulating good, low-cost uses is exactly the evidence that moves
  an artifact proposed → shadow → trusted (§6); a run of bad uses or a cost regression demotes it.
- **Eviction** — low-reputation, low-net-savings artifacts are retired to keep carrying cost (§12)
  bounded.

This closes the loop: artifacts that keep working and keep saving rise; ones that drift or cost too
much fall — automatically, from real usage, across sessions and agents.

## 14. Design space & open questions (the "broad exploration" part)

| Decision | Options | Trade-off |
|---|---|---|
| **First thing to ship** | observe-only · observe+report · mechanical crystallize · full loop | Observe-only is zero-risk and answers "is there enough recurrence to bother?" — the right first commit. |
| **Synthesis depth** | mechanical only · + LLM-once · + HITL | Escalation ladder, not a single choice; start mechanical, add LLM tier behind the trust ladder. |
| **Crystallization target** | result · script · hook · skill · MCP | Lowest rung that covers the pattern; deterministic wins. |
| **Retrieval** | exact key · vector-db · progressive disclosure | Tier to the rung; exact for deterministic, vector-db for parameterized/judgment artifacts. |
| **Token counts** | usage payload (accurate, agent-specific) · `bytes/4` (portable) | Start portable, upgrade where payload exists. |
| **Reuse fires** | PreToolUse (skip the work) · PostToolUse (quiet output) | Pre saves the most (work never runs) but riskier — allowlisted idempotent ops only; Post otherwise. |
| **Global tier** | off · allowlist-only · open | Allowlist-only is the sane middle. |

**Open questions worth resolving before any spec:**

1. **Is there enough recurrence to matter?** Unknown until stage 1 runs on the bench corpus
   (543-commit monorepo, real sessions). *The single most important thing to measure first.*
2. **PreToolUse skip vs. PostToolUse quiet** — does skipping a re-run break any adapter's
   expectations? Validate per agent.
3. **Mechanical correctness budget** — target *zero* wrong hits (input-addressed; any non-zero
   means an under-keyed input, a bug).
4. **Shadow-window cost** — how long must an artifact run in parallel (paying double) before the
   saving is net positive?
5. **Who runs the LLM synthesis step?** Async/offline between sessions? On a maintainer command?
   This decides whether the loop is fully autonomous or supervised.

---

## 15. Risks & failure modes

- **Under-keying → wrong hits** (cardinal sin) → over-include inputs, version schema, deny-list.
- **Trusting a bad generated artifact** → trust ladder; differential gate; generated tests are
  *supplementary* only.
- **Drift / stale procedures** → shadow re-run contradiction + TTL/event invalidation; instant demotion.
- **Security (rug-pull, injection, over-privilege)** → sign/pin, sandbox, least privilege, HITL for tier-0.
- **Prompt-cache busting** → serve only at the tail / fresh calls; never rewrite old results in v1.
- **Cross-repo poisoning** → per-repo default; global allowlist-only.
- **Shadow/synthesis overhead** → bounded windows; mechanical-first.
- **Fuzzy tier silently degrading quality** → off by default, self-disabling on >5% wrong-hit rate.

---

## 16. A light recommended direction

Not a committed plan — but the lowest-risk, highest-information path:

1. **Observe-only** behind a flag — sqlite ledger of fingerprint + cost; add to `bench/` reporting.
   Output: the recurrence×cost distribution on real sessions — the evidence for everything else.
2. **Recognition report** — a `quiet-*` helper that prints the top recurring expensive fingerprints
   per session/repo. Still zero reuse, zero risk.
3. **Mechanical crystallization** — for the narrowest safe slice: input-addressed, per-repo,
   idempotent-allowlisted ops → cached result / generated `quiet-*` script or hook, served at the
   tail. Wrong-hit rate must be zero; measure savings on the bench corpus.
4. **LLM-synthesized skills/MCP tools + vector-db retrieval** — separate, later, opt-in; each
   artifact climbs the trust ladder (proposed → shadow → trusted) before it's relied upon.
5. **Maintenance loop** — shadow re-checks + drift retirement; keep the archive versioned.

The throughline: **measure recurrence before building reuse; crystallize at the lowest rung; make
each artifact earn trust before it replaces the model — and let it fail safe back to the LLM.**

---

## Appendix — prior art (sources)

**Self-generated tools / skills / meta-tools**
- Voyager — generated skill library, embedding-indexed top-5 retrieval, self-verify gate: https://voyager.minedojo.org/ · https://arxiv.org/abs/2305.16291
- LATM (LLMs As Tool Makers) — strong model makes, cheap model uses; up to 79% cheaper: https://arxiv.org/abs/2305.17126 · https://github.com/ctlllll/LLM-ToolMaker
- CREATOR — disentangled tool creation/execution/rectification: https://arxiv.org/pdf/2305.14318
- CRAFT — abstract reusable functions from traces; multi-view (task/name/docstring) retrieval: https://github.com/lifan-yuan/CRAFT
- ADAS (Automated Design of Agentic Systems) — meta-agent programs new agents; versioned archive: https://arxiv.org/pdf/2408.08435
- Anthropic Agent Skills — `SKILL.md`, progressive disclosure: https://www.anthropic.com/engineering/equipping-agents-for-the-real-world-with-agent-skills
- Anthropic skill-authoring best practices — third-person description as retrieval key, <500-line body, bundled scripts: https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices
- AWO (Optimizing Agentic Workflows using Meta-tools) — frequency-threshold trace mining → deterministic composites; 5.6–11.9% fewer calls: https://arxiv.org/abs/2601.22037

**MCP tool design & the context-cost of carrying tools**
- Writing effective tools for agents — few rich tools, concise outputs (72 vs 206 tok), strict schemas: https://www.anthropic.com/engineering/writing-tools-for-agents
- Advanced tool use / Tool Search Tool — ~55K tok for 58 tools; deferred loading; ~85% cut, 49%→74% accuracy: https://www.anthropic.com/engineering/advanced-tool-use
- Code execution with MCP — 150K→2K tokens (98.7%) via code-API exposure: https://www.anthropic.com/engineering/code-execution-with-mcp

**Verifying / sandboxing / maintaining generated artifacts**
- Voyager self-verification (env feedback + critic): https://arxiv.org/abs/2305.16291
- Weak agent-generated tests (caveat): https://arxiv.org/html/2602.07900v2 · Rethinking verification: https://arxiv.org/pdf/2507.06920
- Skill-graph with verifiable rewards + persistence layer: https://arxiv.org/pdf/2512.23760
- MCP Security Best Practices (sandbox, least privilege, consent): https://modelcontextprotocol.io/docs/tutorials/security/security_best_practices
- OWASP MCP Top 10 / Cheat Sheet: https://owasp.org/www-project-mcp-top-10/ · https://cheatsheetseries.owasp.org/cheatsheets/MCP_Security_Cheat_Sheet.html
- MCP rug-pull / tool poisoning: https://policylayer.com/attacks/mcp-rug-pull · https://arxiv.org/html/2508.14925v1 · https://simonwillison.net/2025/Apr/9/mcp-prompt-injection/
- Agent memory eviction policies (TTL/event/decay/contradiction): https://medium.com/@bhagyarana80/agent-memory-eviction-8-policies-that-stop-stale-tool-decisions-fa84ec80d144
- Safe ML rollout (shadow/canary/auto-rollback): https://www.calibreos.com/learn/mlsd-canary-deployment

**Caching / memoization / build caches**
- Bazel remote cache — input-addressed Action Cache + CAS; under-keying = false hits: https://bazel.build/remote/caching
- Nix — input/content-addressed derivations, early cutoff: https://github.com/NixOS/rfcs/blob/master/rfcs/0062-content-addressed-paths.md
- Aider repo-map cache — mtime invalidation, schema version in path: https://github.com/Aider-AI/aider/issues/592
- LangChain `SQLiteCache` — exact key, no auto-invalidation hazard: https://python.langchain.com/docs/integrations/llm_caching/
- LlamaIndex `IngestionCache` — (content_hash, transform) key: https://github.com/run-llama/llama_index/blob/main/llama-index-core/llama_index/core/ingestion/cache.py
- Cursor codebase index — Merkle content hashing: https://cursor.com/blog/secure-codebase-indexing

**Exact vs. semantic caching & vector retrieval**
- GPTCache — exact + embedding modes; false-hit caveat: https://github.com/zilliztech/GPTCache · https://aclanthology.org/2023.nlposs-1.24.pdf
- RedisVL SemanticCache — cosine threshold default 0.1: https://docs.redisvl.com/en/latest/user_guide/03_llmcache.html
- Portkey — hidden threshold, internal confidence gating: https://dev.to/portkey/semantic-caching-thresholds-and-why-they-matter-4ab3
- vLLM prefix caching — SHA256 blocks, cache_salt isolation: https://docs.vllm.ai/en/latest/design/v1/prefix_caching.html
- InfoQ banking study — 99%→3.8% false positives via stacked guardrails: https://www.infoq.com/articles/reducing-false-positives-retrieval-augmented-generation/

**Prompt-cache / context-editing interplay**
- Anthropic prompt caching — longest-exact-prefix, 5-min TTL, 0.1× read: https://platform.claude.com/docs/en/build-with-claude/prompt-caching
- Anthropic context editing — clear_tool_uses_20250919; clearing busts the prefix: https://platform.claude.com/docs/en/build-with-claude/context-editing
- OpenAI prompt caching — automatic implicit prefix: https://developers.openai.com/api/docs/guides/prompt-caching
- Claude Code memory (CLAUDE.md + auto memory): https://code.claude.com/docs/en/memory

**Observability / cost attribution / fingerprinting**
- LangSmith cost tracking: https://docs.langchain.com/langsmith/cost-tracking
- Langfuse token & cost tracking: https://langfuse.com/docs/observability/features/token-and-cost-tracking
- Helicone custom properties (segment cost by dimension): https://docs.helicone.ai/features/advanced-usage/custom-properties
- OpenTelemetry GenAI semantic conventions: https://opentelemetry.io/docs/specs/semconv/gen-ai/gen-ai-spans/
- Arize Phoenix cost tracking: https://arize.com/docs/phoenix/tracing/how-to-tracing/cost-tracking
- SQL query fingerprinting: https://bytes.engineer/blog/sql-slow-query-fingerprinter/
- Drain log-template parsing: https://arxiv.org/pdf/2510.24031
