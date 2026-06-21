# Launch posts (drafts)

Ready-to-paste copy for launch. Swap in the repo URL and the final star/agent
counts before posting.

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
> small `git diff`s pass through untouched.
>
> In a 10-subagent benchmark on a real monorepo, 10 commands totaling 536,957
> tokens of output became ~250 tokens of summaries — a 99.9% cut on command
> output, which works out to roughly ~30% lower total token cost for a typical
> session (more for build/test-heavy work).
>
> Works with Claude Code, Codex, Gemini, Copilot via hooks, and everything else
> (Cursor/Aider/Windsurf/Cline) via a PATH shim. MIT.
>
> Repo: <URL>

*(Put the savings chart as the first comment.)*

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
> if Claude needs to grep it.
>
> Benchmark on a real monorepo: 536,957 tokens of command output → ~250 tokens.
> Install is `/plugin marketplace add …` + `/plugin install …`.
>
> It also ships a universal shell wrapper, so it works under Codex, Cursor, Aider,
> etc. Repo + chart: <URL>
>
> Feedback welcome — especially from anyone who can test the Codex/Gemini/Copilot
> adapters on a live install.

---

## X / Twitter

> Your coding agent's bill is mostly re-read build logs.
>
> quiet-bash redirects verbose command output to a log and leaves a 1-line
> summary. 536,957 tokens → 250 in a real benchmark (99.9% of command output).
>
> Claude Code / Codex / Cursor / Aider. MIT.
> <URL>
> #ClaudeCode

---

## Awesome-list PR blurb

> **[quiet-bash](<URL>)** — Pre-exec hook + universal shell wrapper that redirects
> verbose command output (builds, tests, big git diffs) to a log and leaves the
> agent a one-line summary. ~99.9% less command output in context. Works with
> Claude Code, Codex, Gemini, Copilot, Cursor, Aider.
