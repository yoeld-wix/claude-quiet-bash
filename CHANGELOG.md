# Changelog

All notable changes to this project are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/); versioning is [SemVer](https://semver.org/).

## [1.5.0] — 2026-06-21

### Added
- **Test suite** (`tests/run.sh`) covering core decisions, all four hook adapter
  output shapes, and PATH-shim wrap/passthrough behavior.
- **CI** (GitHub Actions): ShellCheck + JSON validation + the test suite on every
  push and PR.
- **One-command installer** (`install.sh`) with `shims`, `shell`, `claude`,
  `codex`, `gemini`, and `copilot` targets.
- **FAQ** and a before/after **examples** transcript in the docs.
- Badges and a per-workflow cost-saving chart in the README.

## [1.4.0] — 2026-06-21

### Added
- **PATH shims** (`adapters/quiet-shim.sh`, `adapters/install-shims.sh`) so
  quiet-bash works under non-interactive agent shells (Cursor/Aider/…) that never
  source rc.
- **Measured savings + chart**: 10-subagent benchmark (`assets/savings.svg`) —
  536,957 tokens of command output → ~250 tokens of summaries.

### Fixed
- macOS `/var`→`/private/var` self-detection that made shims `exec`-loop.

## [1.3.0] — 2026-06-21

### Added
- **Universal shell wrapper** (`adapters/shell-wrapper.sh`) + `quiet_run` runtime
  executor in the core.
- Project **logo** (`assets/logo.svg`).

## [1.2.0] — 2026-06-21

### Added
- Adapters for **Codex CLI, Gemini CLI, and GitHub Copilot CLI** (documented hook
  formats; only the Claude Code adapter is live-tested).

## [1.1.0] — 2026-06-21

### Changed
- Broadened verbose-command coverage across JS/Python/JVM/Go/Rust/Ruby/C and
  containers; recognize path-prefixed tools like `./gradlew`.

## [1.0.0] — 2026-06-21

### Added
- Initial release: Claude Code `PreToolUse` hook that redirects verbose command
  output to a temp log and surfaces only a summary, with a smart `git`
  diff/show/log path and automatic log pruning.
