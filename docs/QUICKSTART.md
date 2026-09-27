# Quickstart

This guide takes you from nothing to a finished multi-agent task in about five minutes: install AGEX, check that Claude Code sees it, run your first `/agex` task, and read the report it produces. For the design behind what you will see, read [Architecture](ARCHITECTURE.md) afterwards.

## Prerequisites

| Requirement | Why AGEX needs it | Check with |
|---|---|---|
| Claude Code v2.1 or later, signed in | AGEX is a set of Claude Code agents and slash commands; it relies on plugins and nested subagents | `claude --version` |
| git | The installers clone the repository, and several commands read `git status`, `git diff`, and `git log` | `git --version` |
| bash and curl (macOS, Linux, WSL) | The one-command installer | `bash --version`, `curl --version` |
| PowerShell 5.1 or later (Windows) | The Windows installer, `install.ps1` | `$PSVersionTable.PSVersion` |

AGEX has no runtime of its own: no Node, Python, or Docker is required to use it. Everything runs inside Claude Code.

## Step 1: Install

Pick one of the three methods.

```bash
# One-command install (macOS/Linux)
curl -fsSL https://raw.githubusercontent.com/saksham-eng560/agex/main/install.sh | bash

# Or clone manually
git clone https://github.com/saksham-eng560/agex.git ~/.agex
cd ~/.agex && ./install.sh

# Or install as a Claude Code plugin
claude plugin marketplace add saksham-eng560/agex
claude plugin install agex@agex-marketplace
```

The first two methods keep a clone of the repository in `~/.agex` and symlink its 12 agents into `~/.claude/agents/` and its 8 commands into `~/.claude/commands/`, so they are available in every project. The plugin method lets Claude Code manage the files for you.

The installers never overwrite a file they did not create. If you already have a file with the same name as an AGEX file, it is skipped with a warning and the summary tells you how many were skipped; re-run with `--force` to move your file to `~/.claude/.agex-backup/<timestamp>/` and link the AGEX version (`--uninstall` restores it later). Run `./install.sh --help` for every option, including `--dir <path>` for a checkout elsewhere and `CLAUDE_HOME` for a different Claude Code configuration directory.

### Windows

In PowerShell:

```powershell
irm https://raw.githubusercontent.com/saksham-eng560/agex/main/install.ps1 | iex
```

Or clone the repository and run the installer yourself:

```powershell
git clone https://github.com/saksham-eng560/agex.git "$HOME\.agex"
cd "$HOME\.agex"
.\install.ps1
```

If your execution policy blocks local scripts, run `powershell -ExecutionPolicy Bypass -File .\install.ps1` instead; this relaxes the policy for that one process only. When Windows does not allow symbolic links (Developer Mode off and not running as administrator), `install.ps1` copies the files instead; copies do not follow `git pull`, so re-run the installer after each update. The one-liner cannot take parameters, so set `AGEX_FORCE=1`, `AGEX_NO_UPDATE=1`, or `AGEX_UNINSTALL=1` in the environment instead. The plugin commands above work the same way on Windows.

### Which method should I choose?

| | Plugin | `install.sh` / `install.ps1` |
|---|---|---|
| Agent names | `agex:orchestrator`, `agex:planner`, ... | `orchestrator`, `planner`, ... |
| Command names | `/agex:agex`, `/agex:agex-plan`, ... (type `/agex` and pick from the autocomplete list) | `/agex`, `/agex-plan`, ... |
| Session logging hooks | Enabled automatically | Not installed; add them by hand if you want them (see [Customization](CUSTOMIZATION.md#enabling-session-log-hooks-for-symlink-installs)) |
| Name collisions with agents you already have | Impossible: the `agex:` prefix keeps them apart | Possible if you already have agents with the same names |
| Editing the agents | Fork the repository | Edit the files in `~/.agex` directly |
| Updating | `claude plugin update agex@agex-marketplace` | `git -C ~/.agex pull` |

If you are unsure, use the plugin. Choose the installer if you want short command names or plan to edit the agent prompts. Install only one way at a time; with both, every agent and command shows up twice.

The rest of this guide uses the short names. With the plugin, add the `agex:` prefix: `/agex-status` becomes `/agex:agex-status`, and the `planner` agent is `agex:planner`.

## Step 2: Verify the installation

Start Claude Code in any directory and run the status command:

```text
/agex-status
```

It lists the AGEX agents and their roles, the tail of the session log if one exists, and a short summary of the current project. If the command is not recognized, start a new Claude Code session: agents and commands are loaded when a session starts.

You can also run Claude Code's built-in `/agents` command. It should list all 12 agents: `orchestrator`, `researcher`, `architect`, `coder`, `reviewer`, `tester`, `debugger`, `documenter`, `devops`, `refactor`, `security`, and `planner`. Plugin installs show them as `agex:orchestrator`, `agex:researcher`, and so on.

For installer-based setups you can inspect the symlinks directly:

```bash
ls -l ~/.claude/agents ~/.claude/commands
```

Each AGEX entry should point into `~/.agex/.claude/`. A broken link usually means `~/.agex` was moved or deleted; run the installer again.

## Step 3: Run your first task

Open a terminal in a project you are working on and start Claude Code:

```bash
cd ~/code/my-api
claude
```

Give AGEX a concrete task, with the outcome and how you will know it is done:

```text
/agex Add input validation to the POST /users endpoint: reject a missing or malformed email with a 400 response and a JSON error body, and add tests for both cases
```

Good tasks name the thing to change (an endpoint, a file, a failing test), the expected behavior, and the acceptance criteria. Vague tasks such as "improve the API" push AGEX into the most expensive COMPLEX pipeline and usually end in questions for you.

Starting from a clean working tree is recommended, so that `git diff` afterwards shows exactly what AGEX changed.

## What happens during a run

The `/agex` command turns your main conversation into the AGEX orchestrator. You can watch every step as it happens.

1. **Orientation.** The orchestrator reads your `CLAUDE.md` files and `git status`, and detects your test, lint, and type-check commands from files such as `package.json`, `pyproject.toml`, `go.mod`, `Cargo.toml`, or a `Makefile`.
2. **Complexity classification.** It classifies the task and picks a pipeline:

   | Class | Typical task | Pipeline |
   |---|---|---|
   | SIMPLE | One concern, one or two files, obvious change | A direct answer, or exactly one specialist |
   | MEDIUM | Two to five files in one component, clear approach | (planner, optional) then coder, tester, and reviewer |
   | COMPLEX | Several components, a new data model or API, unclear requirements, or more than five files | planner, researcher, architect, parallel coders, tester, reviewer, and documenter when public APIs or docs change |

   The example task above is typically MEDIUM: a route handler, a validation helper, and a test file.
3. **Dispatches.** The orchestrator sends each specialist a self-contained delegation packet (objective, inputs, scope, constraints, expected artifact). Specialists work in their own context windows and never see your conversation. Independent work units are dispatched in parallel.
4. **Artifacts.** Every specialist returns one typed handoff artifact. Each starts with a marker line such as `<!-- agex:artifact type=CodeDiff version=1 -->`, followed by a title and a Producer, Status, and Confidence line. The coder returns a CodeDiff, the tester a TestReport, the reviewer a ReviewVerdict, and so on. [Handoff Protocol](HANDOFF-PROTOCOL.md) documents all twelve formats.
5. **Feedback cycles.** A failing TestReport goes back to the coder with the failure traces; a CHANGES_REQUESTED ReviewVerdict goes back with the listed issues. Each loop is capped at 3 cycles per work unit. If the cap is reached, the same failure repeats twice in a row, or the reviewer returns BLOCKED, the orchestrator stops and shows you an ESCALATION block with options and a recommendation.
6. **Quality gate.** Before reporting success, the orchestrator checks that the latest TestReport is PASS, the latest ReviewVerdict is APPROVED, no CRITICAL or HIGH security findings are open, and every acceptance criterion is met.
7. **Final report.** Every run that dispatched at least one agent ends with an AgexReport. A simple read-only question is answered directly, without a report.

## Reading the AgexReport

The report opens with the same kind of envelope as every other artifact:

```markdown
<!-- agex:artifact type=AgexReport version=1 -->
## AgexReport: Validate email on POST /users
**Producer:** orchestrator · **Status:** DONE · **Confidence:** HIGH
```

The Status tells you what to do next:

| Status | Meaning | What you do |
|---|---|---|
| DONE | The quality gate passed | Review the diff and commit it |
| PARTIAL | Some of the work is verified, but the quality gate did not fully pass (for example, an acceptance criterion is unmet or the dispatch budget ran out) | Read Open Issues & Escalations and decide whether to continue |
| ESCALATED | A circuit breaker tripped or a decision needs you | Pick one of the options in the ESCALATION block, or give new direction |

Then come seven sections, always in this order:

| Section | What to look for |
|---|---|
| Task | Your request restated, with the complexity class the orchestrator chose |
| Outcome | What now works, or the answer to your question |
| Agents Deployed | One row per dispatch: `# \| Agent \| Artifact \| Status \| Cycle`. Repeated coder and tester rows show feedback cycles |
| Changes | Every file created, modified, or deleted |
| Verification Evidence | The exact test, lint, and type-check commands that were run, with their results. Claims without a command behind them do not belong here |
| Open Issues & Escalations | LOW-severity review items, unresolved findings, and any ESCALATION blocks |
| Next Steps | Concrete follow-ups for you |

For the example task, an Agents Deployed table in which the first test run failed and the second passed would look like this (illustrative):

| # | Agent | Artifact | Status | Cycle |
|---|---|---|---|---|
| 1 | coder | CodeDiff | IMPLEMENTED | n/a |
| 2 | tester | TestReport | FAIL | n/a |
| 3 | coder | CodeDiff | IMPLEMENTED | coder-tester 1/3 |
| 4 | tester | TestReport | PASS | coder-tester 1/3 |
| 5 | reviewer | ReviewVerdict | APPROVED | n/a |

The first implementation and its first test run are not cycles; the Cycle column counts only fixes inside a feedback loop.

AGEX leaves its changes in your working tree. Review them with `git diff` before you commit. The coder never commits or pushes, and remote or irreversible operations such as pushing, tagging, or deploying only happen through the devops agent after you confirm them explicitly.

## Next commands to try

| Command | What it does | Artifact |
|---|---|---|
| `/agex-plan <task>` | Plans a task without executing anything: ordered steps, an agent per step, dependencies, parallel waves, and risks. A cheap way to preview a big task | TaskPlan |
| `/agex-review [path or git ref]` | Adversarial, read-only review of what you name; otherwise of your staged changes, then unstaged and untracked changes, then the last commit. Adds the security agent when authentication, input handling, cryptography, or secrets are involved | ReviewVerdict |
| `/agex-test [what to test]` | Writes and runs tests for what you name, or for recently changed code, and reports failures with traces the coder can act on | TestReport |
| `/agex-secure [path or concern]` | Scans the project, or the scope you name, for leaked secrets, OWASP Top 10 issues, risky dependencies, and unsafe configuration, without changing any file | SecurityAuditReport |
| `/agex-docs <documentation task>` | Writes or updates READMEs, API references, doc comments, and changelog entries. With no task, it audits your docs and proposes updates without writing anything | DocUpdate |
| `/agex-research <topic or question>` | Read-only investigation of your codebase and the web, with `file:line` evidence | ResearchBrief |
| `/agex-status` | Lists the AGEX agents, recent session activity, and project context | none |

Arguments in square brackets are optional.

You can also call a single agent without the orchestrator, in plain language: "Use the debugger agent to find out why `tests/test_parser.py` fails" (plugin: "Use the agex:debugger agent ..."). To make the orchestrator your whole session instead of a slash command, start Claude Code with `claude --agent orchestrator` (plugin: `claude --agent agex:orchestrator`).

[Examples](EXAMPLES.md) walks through complete runs for a REST API, a bug fix, a code review, a CLI tool, and a security audit.

## Updating

| Install method | Update command |
|---|---|
| Installer (macOS, Linux) | `git -C ~/.agex pull`, or run the curl one-liner again |
| Installer (Windows) | `git -C "$HOME\.agex" pull`, or run the `irm` one-liner again |
| Plugin | `claude plugin update agex@agex-marketplace` |

Because the installed agents and commands are symlinks into `~/.agex`, a `git pull` takes effect in your next Claude Code session. If a release adds new agent or command files, or `install.ps1` installed copies instead of links, run the installer again so that the files are linked or refreshed too; it also removes links to files a release deleted. If a plugin update is not found, refresh the marketplace first with `claude plugin marketplace update agex-marketplace`. [CHANGELOG](../CHANGELOG.md) lists what changed in each release.

## Uninstalling

| Install method | Uninstall command |
|---|---|
| Installer (macOS, Linux) | `~/.agex/install.sh --uninstall` (or `curl -fsSL https://raw.githubusercontent.com/saksham-eng560/agex/main/install.sh \| bash -s -- --uninstall`) |
| Installer (Windows) | `& "$HOME\.agex\install.ps1" -Uninstall` |
| Plugin | `claude plugin uninstall agex@agex-marketplace` |

Uninstalling removes AGEX's agents and commands from Claude Code. The script uninstall removes only the links (and, on Windows, unmodified copies) that it created, puts back any files that `--force` backed up, and leaves the checkout in `~/.agex` for you to delete. Session logs live in each project's `.agex/` directory; that directory ignores itself in git, and you can delete it whenever you like.

## Where to go next

- [Agents](AGENTS.md): what each of the 12 agents does, its tools, and its model.
- [Customization](CUSTOMIZATION.md): add your own agents and commands, change models, and tune the circuit breakers.
- [FAQ](FAQ.md): cost, safety, Windows, CI, and troubleshooting.
