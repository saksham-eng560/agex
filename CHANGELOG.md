# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.0] - 2026-09-27

First public release of AGEX, the master agent orchestrator for Claude Code.

### Added

- Twelve subagents in `.claude/agents/`, an orchestrator and eleven specialists, each with a least-privilege tool list, a 300-800 word system prompt, explicit NEVER constraints, and a typed output format:
  - `orchestrator` (Opus): classifies tasks as SIMPLE, MEDIUM, or COMPLEX, routes them by task type, dispatches independent work units in parallel, enforces circuit breakers and the quality gate, and synthesizes an AgexReport.
  - `researcher`, `architect`, `reviewer`, `security`, and `planner`: read-only agents without Write or Edit tools that produce a ResearchBrief, TechnicalRFC, ReviewVerdict, SecurityAuditReport, and TaskPlan.
  - `coder`, `tester`, `debugger`, `documenter`, `devops`, and `refactor`: agents that produce a CodeDiff, TestReport, DebugReport, DocUpdate, DevOpsChange, and RefactorReport, with the tester limited to test files, the documenter limited to documentation, and devops stopping for explicit human confirmation before any remote or irreversible operation.
- Eight slash commands: `/agex`, `/agex-plan`, `/agex-status`, `/agex-research`, `/agex-review`, `/agex-test`, `/agex-secure`, and `/agex-docs`. Their project-context injections are strictly read-only and always fall back gracefully, so they work in empty and non-git directories. When a focused command's specialist is not available in the session, the command performs the task inline under that specialist's constraints and marks the artifact's Producer as `<name> (inline fallback)`.
- Typed handoff protocol with twelve artifact types, each starting with a `<!-- agex:artifact type=<Type> version=1 -->` marker line, a fixed status enum, and ordered sections, plus the ReviewVerdict decision rule (any CRITICAL is BLOCKED; any HIGH or MEDIUM is CHANGES_REQUESTED).
- Circuit breakers: at most 3 coder-tester and 3 coder-reviewer cycles per work unit with independent counters, early escalation when two consecutive cycles share a failure signature, one simplified retry for a failed sub-agent, a soft cap of 15 dispatches per run, and a standard escalation block.
- Claude Code plugin manifest (`.claude-plugin/plugin.json`) and a single-plugin marketplace (`agex-marketplace`), so AGEX installs with `claude plugin install agex@agex-marketplace` and its components are namespaced as `agex:<name>` and `/agex:<command>`.
- Session logging hooks (SessionStart, and PostToolUse on Write, Edit, and MultiEdit) backed by a POSIX sh script that appends event lines with paths only to `.agex/session.log`, rotates the log at 1 MiB, keeps `.agex/` out of git, always exits 0, and is disabled with `AGEX_DISABLE_LOG=1`. The orchestrator adds DISPATCH, ARTIFACT, CYCLE, ESCALATION, and RUN_COMPLETE events.
- Installers for macOS/Linux (`install.sh`, Bash 3.2 compatible) and Windows (`install.ps1`, PowerShell 5.1 and 7) that clone or update AGEX in `~/.agex` and link its agents and commands into `~/.claude` (`install.ps1` copies them when Windows does not permit symbolic links), with `--force`, `--uninstall`, `--dir`, `--no-update`, and `--help` options (PowerShell: `-Force`, `-Uninstall`, `-Dir`, `-NoUpdate`, `-Help`), an install manifest (`~/.claude/.agex-manifest`), skipping of pre-existing files unless `--force` backs them up to `~/.claude/.agex-backup/<timestamp>/`, restore of those backups on uninstall, warnings for same-named user agents, and `AGEX_HOME`, `AGEX_REPO`, `CLAUDE_HOME`, and `NO_COLOR` overrides (plus `AGEX_UNINSTALL`, `AGEX_FORCE`, and `AGEX_NO_UPDATE` for the PowerShell one-liner).
- Repository validator (`scripts/validate.py`, Python 3.8+ standard library only) and a GitHub Actions CI workflow that runs on pull requests and pushes to `main`: the validator, ShellCheck, `claude plugin validate --strict`, installer smoke tests on Ubuntu, macOS, and Windows, and hook logger tests. Also issue forms, a pull request template, CODEOWNERS, and Dependabot configuration.
- Documentation suite in `docs/`: Architecture, Agents, Quickstart, Customization, Handoff Protocol, Examples, and FAQ, plus a project `CLAUDE.md` that imports the architecture and agent references.
- Five worked examples in `examples/`: web app build, bug fix, code review, full project, and security audit.
- Templates for user-defined agents and commands in `templates/`.
- Community and project files: MIT `LICENSE`, `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md` (Contributor Covenant 2.1), `SECURITY.md` with GitHub private vulnerability reporting, `.editorconfig`, `.gitattributes`, and `.gitignore`.

[Unreleased]: https://github.com/saksham-eng560/agex/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/saksham-eng560/agex/releases/tag/v1.0.0
