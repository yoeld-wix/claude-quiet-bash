# Before / after

What the agent's context window actually receives.

## `yarn build` in a monorepo

**Without quiet-bash** — ~900 lines, re-sent on every following turn:

```
$ yarn build
yarn run v1.22.19
$ turbo run build
• Packages in scope: @app/api, @app/web, @app/shared
• Running build in 3 packages
@app/shared:build: cache miss, executing 9f2a...
@app/shared:build: $ tsc -p tsconfig.build.json
@app/shared:build: src/index.ts → dist/index.js
@app/web:build: cache miss, executing 1b7c...
@app/web:build: $ vite build
@app/web:build: vite v5.0.10 building for production...
@app/web:build: transforming...
@app/web:build: ✓ 1463 modules transformed.
@app/web:build: dist/index.html                   0.46 kB
@app/web:build: dist/assets/index-a1b2c3.css      12.84 kB
@app/web:build: dist/assets/index-d4e5f6.js      284.21 kB
... 870 more lines ...
Done in 42.13s.
```

**With quiet-bash** — one line:

```
[ok: exit 0 — 912 lines hidden in /tmp/claude-cmd-9OW69C; grep/tail it only if you need details]
```

The full log still exists on disk — the agent can `grep`/`tail` it if it ever
needs a detail — but it never enters (and re-enters) the context window.

## A failing test run

On failure, you still get the part that matters — the tail — plus a pointer to
the full log:

```
[FAILED: exit 1 — 1461 lines in /tmp/claude-cmd-mZJafw | last 40 below; grep that file for the rest]
  ● auth › rejects expired tokens
    expect(received).toBe(expected)
    Expected: 401
    Received: 200
      at Object.<anonymous> (test/auth.spec.ts:88:31)
  Tests: 1 failed, 212 passed, 213 total
```

## Small `git diff` is shown as normal

quiet-bash only quiets *large* git output. A small diff passes straight through,
because the content is the point:

```
$ git diff
diff --git a/src/index.ts b/src/index.ts
@@ -1,3 +1,3 @@
-export const PORT = 3000
+export const PORT = Number(process.env.PORT ?? 3000)
```
