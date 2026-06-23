# Launch posts — FINALIZED

Repo: **https://github.com/yoeld-wix/quiet-bash**
Chart (raw SVG): **https://raw.githubusercontent.com/yoeld-wix/quiet-bash/main/assets/savings-compact.svg**

Claims are softened to **verified-only**: Claude Code hook + universal MCP proxy
are proven (the proxy is live-tested against a real MCP server; 610 KB result →
2.2 KB, byte-exact spill). Codex / Gemini / Copilot adapters are labeled
experimental (contract-tested, not yet run on a live install).

> ⚠️ Posting status: HN / Reddit / X require interactive login — paste these
> yourself. The awesome-claude-code submission **must** be done by a human via
> the github.com UI (their CoC forbids `gh`/programmatic submission) and the
> resource must be **≥ 1 week old** (quiet-bash's first release was ~Jun 21, so
> submit on/after ~Jun 28).

---

## Show HN

**Title:**
> Show HN: quiet-bash – cut 537K tokens of agent build logs to 250

**Body:**
> Coding agents (Claude Code, Codex, Cursor, …) burn most of their token budget
> re-reading build and test output. Because the model is stateless, every turn
> re-sends the whole transcript — so a 900-line `yarn build` dump isn't paid for
> once, it's paid for on every turn that follows.
>
> quiet-bash is a pre-exec hook (plus a universal shell/PATH wrapper for agents
> without hooks) that redirects verbose command output to a temp log and leaves
> the agent a one-line summary. On failure it still surfaces the last 40 lines;
> small `git diff`s pass through untouched. The full log stays on disk, and a
> bundled `quiet-query` tool lets the agent interrogate a spilled JSON/YAML
> payload (count/group/stats/filter) without re-reading it.
>
> In a 10-command benchmark on a real monorepo, 536,957 tokens of command output
> became ~250 tokens of summaries — a 99.9% cut on command output, which works
> out to roughly ~30% lower total token cost for a typical session (more for
> build/test-heavy work).
>
> Verified today: the Claude Code hook, and a transport-level **MCP proxy** that
> shrinks large `tools/call` results for *any* MCP client (incl. Codex) — I ran
> it in front of a real filesystem MCP server and a 610 KB read collapsed to
> 2.2 KB, with the full payload kept byte-exact on disk. Adapters for
> Codex/Gemini/Copilot *hooks* exist but are still experimental (contract-tested,
> not yet run on a live install) — feedback from anyone on those very welcome.
> MIT.
>
> Repo: https://github.com/yoeld-wix/quiet-bash

*(First comment: paste the chart link
https://raw.githubusercontent.com/yoeld-wix/quiet-bash/main/assets/savings-compact.svg
— HN comments don't render images, so post it as a link.)*

---

## r/ClaudeAI (and r/ClaudeCode)

**Title:**
> I cut my Claude Code token bill by quieting build/test logs — 99.9% less command output

**Body:**
> Build and test logs were eating my context window. Since the whole transcript
> is re-sent every turn, a big `yarn test` dump gets re-billed again and again.
>
> So I made **quiet-bash**: a `PreToolUse` hook that sends verbose command output
> to a temp log and leaves Claude a one-line summary. Failures still show the
> last 40 lines; small `git diff`s come through normally; the full log is on disk
> if Claude needs to grep it (there's a `quiet-query` helper for spilled
> JSON/YAML).
>
> Benchmark on a real monorepo: 536,957 tokens of command output → ~250 tokens.
> Install is `/plugin marketplace add …` + `/plugin install …`.
>
> It also ships a transport-level **MCP proxy** that shrinks large tool results
> for any MCP client (I live-tested it against a real filesystem MCP server: a
> 610 KB read collapsed to 2.2 KB, full payload kept byte-exact on disk).
> Experimental hook adapters for Codex/Gemini/Copilot are in there too but aren't
> live-tested yet — would love feedback from anyone who can try them on a real
> install. MIT.
>
> Repo + chart: https://github.com/yoeld-wix/quiet-bash

---

## X / Twitter

> Your coding agent's bill is mostly re-read build logs.
>
> quiet-bash redirects verbose command output to a log and leaves a 1-line
> summary. 536,957 tokens → 250 in a real benchmark (99.9% of command output).
> Plus an MCP proxy that shrinks big tool results for any client.
>
> Claude Code + universal MCP proxy. MIT.
> https://github.com/yoeld-wix/quiet-bash
> #ClaudeCode

---

## Awesome-list submission — awesome-claude-code

**DO NOT submit via `gh`.** Their Code of Conduct requires submission by a human
through the github.com UI, and the resource must be ≥ 1 week old. Use the form:
https://github.com/hesreallyhim/awesome-claude-code/issues/new?template=recommend-resource.yml

Pre-filled field values:

- **Display Name:** quiet-bash
- **Category:** Hooks
- **Sub-Category:** (leave General / blank)
- **Primary Link:** https://github.com/yoeld-wix/quiet-bash
- **Author Name:** yoeld-wix
- **Author Link:** https://github.com/yoeld-wix
- **License:** MIT
- **Description** (1-3 sentences, no emoji, descriptive not promotional):
  > A PreToolUse hook and universal shell wrapper that redirects verbose command
  > output (builds, tests, large git diffs) to a temp log and leaves the agent a
  > one-line summary, surfacing the last lines only on failure. Includes a
  > transport-level MCP proxy that shrinks large tool results for any MCP client
  > and a quiet-query helper for interrogating spilled JSON/YAML.
- **Validate Claims:** Run any build/test-heavy command (e.g. `yarn build`) under
  an agent with the hook installed; the multi-hundred-line output is replaced by
  a one-line summary while the full log remains on disk.
- **Specific Task(s):** Ask the agent to build the project and then report the
  build result.
- **Specific Prompt(s):** "Run `yarn build` and tell me if it passed." Observe
  that the transcript gains a one-line summary instead of the full log.

---

## Awesome-list blurb (for any list that DOES accept PRs)

> **[quiet-bash](https://github.com/yoeld-wix/quiet-bash)** — Pre-exec hook +
> universal shell wrapper that redirects verbose command output (builds, tests,
> big git diffs) to a log and leaves the agent a one-line summary. ~99.9% less
> command output in context. Also ships an MCP proxy that shrinks large tool
> results for any client.
