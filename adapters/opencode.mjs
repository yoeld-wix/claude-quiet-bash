// quiet-bash — OpenCode plugin.
//
// OpenCode exposes `tool.execute.after(input, output)`, which fires after a tool
// runs and lets a plugin modify the result before the model sees it. This is the
// PostToolUse analog: when a `bash` tool result is large, spill the byte-exact
// payload to a temp file and replace `output.output` with a compact quiet-bash
// summary (reusing core/quiet-result.sh — the same summarizer the Claude Code
// adapter and MCP proxy use, so there's one source of truth). Lossless: only the
// preview shrinks; the full output stays on disk and the summary says how to query
// it. Small results and non-bash tools pass through untouched.
//
// Install (project): copy/symlink this file to `.opencode/plugin/quiet-bash.mjs`,
// or reference the package in opencode.json `"plugin"`. Requires bash + jq on PATH.

import { execFileSync } from "node:child_process";
import path from "node:path";
import { fileURLToPath } from "node:url";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const SUMMARIZER = path.resolve(HERE, "..", "core", "quiet-result.sh");
const MIN_BYTES = Number(process.env.QUIET_RESULT_MIN_BYTES || 25000);

export default async () => ({
  "tool.execute.after": async (input, output) => {
    try {
      if (!input || input.tool !== "bash") return;          // only quiet shell output
      const text = output && output.output;
      if (typeof text !== "string" || !text) return;
      if (text.includes("[quiet-bash]")) return;            // never double-wrap
      if (Buffer.byteLength(text, "utf8") <= MIN_BYTES) return; // small → leave it
      let summary;
      try {
        summary = execFileSync("bash", [SUMMARIZER, "bash"], {
          input: text,
          maxBuffer: 1 << 30,
        }).toString();
      } catch {
        return;                                             // summarizer failed → leave untouched
      }
      if (summary && summary.trim()) output.output = summary;
    } catch {
      /* never break the tool call */
    }
  },
});
