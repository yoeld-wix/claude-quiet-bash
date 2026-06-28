# Coinbase cut its AI bill in half. Their playbook is quiet-bash's thesis.

Coinbase CEO Brian Armstrong [posted how they halved AI spend][post] while token
usage kept growing exponentially — and they did it **without capping a single
engineer's tokens**. 91% of employees never hit their quota anyway, so lowering
caps was theater. They fixed the defaults instead.

The line that matters:

> The goal isn't fewer tokens. It's fewer **wasted** tokens.

That's been quiet-bash's whole pitch since day one. An agent is stateless, so it
re-sends the entire transcript every turn — a 600-line test log near the start of
a task is re-billed on every later turn. That's waste, and you can cut it without
taking anything away from the agent.

## The four levers

| Lever | What Coinbase did | quiet-bash |
|---|---|---|
| **Defaults** | Default to cheap open-weight models (GLM 5.2, Kimi 2.7) via an internal gateway; engineers still pick any model | — |
| **Routing** | Harness pre-processes the prompt, routes by price + cache-hit odds — strong model to plan, cheap model to execute | — |
| **Caching** | Every request is cache-aware and reuses what's warm; LibreChat hit rate went 5% → 60% | **✓** |
| **Lean context** | Fresh session per task, fewer files in context, prune unused tools — *not* blind compression | **✓** |

The two Coinbase calls highest-impact — **caching** and **lean context** — are
exactly what quiet-bash automates.

## Where quiet-bash fits

Re-sending a fat build log every turn busts your stable prefix and tanks your
cache-hit rate. quiet-bash spills that output to disk byte-exact and leaves a
one-line summary in its place — so the prefix stays warm and the context stays
lean, mechanically, on every command. In a 10-command benchmark on a real
monorepo, 536,957 tokens of command output became ~250 — a **99.9% cut** on
command output *(measured)*.

It doesn't do routing or model defaults — those are different levers, and they
**stack** with it. See [comparison.md](../comparison.md) for the full field map.

## Try it

```bash
curl -fsSL https://raw.githubusercontent.com/yoeld-wix/quiet-bash/main/install.sh | bash
```

Repo: **https://github.com/yoeld-wix/quiet-bash** · MIT.

---

*Coinbase's figures — GLM 5.2 / Kimi 2.7 pricing and the 5% → 60% LibreChat
cache-hit jump — are their own reported numbers, not ours. Source: [Armstrong's
post][post].*

[post]: https://x.com/brian_armstrong/status/2070670644577280109
