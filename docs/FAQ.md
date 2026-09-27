# AGEX FAQ

Answers to common questions about installing, running, and trusting AGEX. Answers use the short names of a script install (`/agex`, `planner`). With the plugin install, add the `agex:` prefix: `/agex` becomes `/agex:agex` and `planner` becomes `agex:planner`.

If your question is not answered here, see the [Quickstart](QUICKSTART.md), [Architecture](ARCHITECTURE.md), and [Customization](CUSTOMIZATION.md) guides, or open an issue at [github.com/saksham-eng560/agex/issues](https://github.com/saksham-eng560/agex/issues).

- [General](#general)
- [Installation](#installation)
- [Usage](#usage)
- [Safety & Security](#safety--security)
- [Troubleshooting](#troubleshooting)

## General

### What is AGEX?

AGEX (Agent Executor) is an open-source multi-agent orchestration framework for Claude Code, released under the MIT license. It ships 12 subagents (an orchestrator and 11 specialists) and 8 slash commands as plain Markdown files. When you run `/agex <task>`, an orchestrator classifies the task as SIMPLE, MEDIUM, or COMPLEX, dispatches the specialists it needs (planner, researcher, architect, coder, tester, reviewer, and others), passes typed handoff artifacts between them, runs coder-tester and coder-reviewer feedback loops behind circuit breakers, and ends with a single AgexReport.

There is no server, daemon, SDK, or runtime dependency. The only executable code is the POSIX `sh` logging hook, the installers, and the repository validator. AGEX is an independent community project; it is not made or endorsed by Anthropic.

### What do I need to run it?

- **Claude Code v2.1 or later.** AGEX is developed and tested against 2.1.283. Check your version with `claude --version`.
- **Access to the models the agents use:** Opus for the orchestrator, Haiku for the planner and documenter, and Sonnet for everything else. If your plan does not include one of them, change the `model:` line of the affected agents (see [Changing models per agent](CUSTOMIZATION.md#changing-models-per-agent)).
- **For the script installers:** `git`, plus `bash` and `curl` on macOS and Linux, or PowerShell on Windows. The plugin install needs only Claude Code.

You do not need Node, Python, or Docker to use AGEX. Python 3.8 or later is needed only by contributors who run `scripts/validate.py`.

### How is AGEX different from asking Claude Code directly?

For a small, well-understood change, asking Claude Code directly is often the right choice, and AGEX's SIMPLE path behaves much the same way: a direct answer or exactly one specialist. AGEX adds structure for larger work:

- **Separation of duties.** The agent that writes the code is not the one that tests or reviews it. The reviewer cannot edit files, so it reports problems instead of quietly patching them.
- **Least privilege.** Each agent gets only the tools its job needs.
- **Typed artifacts.** Every agent returns a fixed-format artifact with a status from a closed set, so the orchestrator routes mechanically and you can audit every decision afterwards.
- **Bounded loops.** Failing tests and review findings go back to the coder automatically, but for at most 3 cycles per work unit; then you decide.
- **A quality gate.** A run is reported DONE only with a passing TestReport, an approved ReviewVerdict, no open CRITICAL or HIGH security findings, and every acceptance criterion checked.

Claude Code's built-in subagents are general purpose; AGEX is a specific team built on the same subagent mechanism, so the two coexist. The price of the extra structure is more tokens and more wall-clock time than a single conversation.

### How much does a run cost, and how can I reduce it?

AGEX adds no charges of its own: what you pay is Claude Code model usage under your plan or API account. Every dispatch is a separate model conversation with its own context, and feedback loops add dispatches, so a COMPLEX run uses considerably more tokens than one conversation would. AGEX does not publish per-run estimates, because they depend on your repository, your task, and your model choices.

The defaults are `opus` for the orchestrator, `haiku` for the planner and documenter, and `sonnet` for the other nine agents. When you use `/agex`, your main conversation plays the orchestrator, so orchestration runs on your session model (the one `/model` shows), not on the orchestrator file's `opus`. That setting applies when the orchestrator runs as a subagent or through `claude --agent orchestrator`.

Ways to spend less:

1. **Write specific tasks.** A task that names the file or endpoint, the expected behavior, and how you will know it is done is classified SIMPLE or MEDIUM. Vague tasks such as "improve the API" land in the COMPLEX pipeline. SIMPLE tasks skip the planner and use at most one specialist.
2. **Use a focused command** when you know which specialist you need: `/agex-review`, `/agex-test`, `/agex-research`, `/agex-secure`, and `/agex-docs` each dispatch a single agent (the review command adds the security agent only when sensitive code is touched).
3. **Preview with `/agex-plan`.** The planner runs on Haiku and returns a TaskPlan with steps, agents, and execution waves without executing anything. You see how large a run would be before paying for it, and can trim the scope first.
4. **Change models per agent.** Setting the orchestrator to `sonnet` works well for MEDIUM tasks with clear acceptance criteria. `inherit` makes an agent follow your session model. See [Changing models per agent](CUSTOMIZATION.md#changing-models-per-agent).
5. **Rely on the dispatch budget.** A run has a soft cap of 15 sub-agent dispatches (retries and each member of a parallel batch count). Before exceeding it, the orchestrator stops, summarizes progress and the remaining work, and asks you. Declining, or narrowing the remaining scope, caps the spend.
6. **Lower the loop limit** if your failures are usually clear-cut. See [Can I change the 3-cycle limit?](#can-i-change-the-3-cycle-limit)
7. **Cap headless runs** with `--max-budget-usd` (see [Can I run AGEX headless or in CI?](#can-i-run-agex-headless-or-in-ci)).

### What are AGEX's known limitations?

1. **"Read-only" is enforced at the tool level for Write and Edit only.** The researcher, reviewer, and security agents keep Bash for inspection; their prompts forbid changes through it, but that is not a sandbox.
2. **Plugin subagents ignore the `hooks`, `mcpServers`, and `permissionMode` frontmatter fields.** AGEX agents do not use them.
3. **Script installs share the global agent namespace.** A pre-existing `~/.claude/agents/planner.md`, or any agent whose `name` matches an AGEX agent, can collide. The plugin install avoids this through `agex:` scoping.
4. **Cost.** The orchestrator uses Opus, the planner and documenter use Haiku, and the others use Sonnet. You can change `model:` per agent.
5. **Session logging hooks are active only in plugin installs and inside the AGEX repository.** Script installs and project copies get agents and commands only; the hooks can be added by hand ([instructions](CUSTOMIZATION.md#enabling-session-log-hooks-for-symlink-installs)).

Further constraints that follow from the design:

- Artifact formats and prompt-level rules (the tester touches only test files, devops stops before remote operations) depend on model adherence. The orchestrator validates every artifact and retries once, but there is no parser or sandbox behind it.
- Parallel coders have no file locking. Safety relies on the orchestrator assigning disjoint file sets, which the TechnicalRFC's Parallel-safe flag supports.
- The session log records file changes made with the Write, Edit, and MultiEdit tools only, not changes made by shell commands such as formatters, code generators, or `sed -i`.
- In `/agex` mode the main conversation keeps its own tools, so "the orchestrator never edits files" is a prompt rule there. Use `claude --agent orchestrator` to enforce it at the tool level.

## Installation

### Should I use the plugin, install.sh / install.ps1, or copy AGEX into my project?

| | Plugin | Script install (`install.sh` / `install.ps1`) | Project copy |
|---|---|---|---|
| How | `claude plugin marketplace add saksham-eng560/agex`, then `claude plugin install agex@agex-marketplace` | The one-line installer, or a clone in `~/.agex` plus `./install.sh` (Windows: `.\install.ps1`) | Copy AGEX's `.claude/agents/` and `.claude/commands/` into the project's `.claude/` directory |
| Available in | Every project where the plugin is enabled | Every project (user scope, `~/.claude`) | That project only; commit the files to share them with your team |
| Agent names | `agex:orchestrator`, `agex:planner`, ... | `orchestrator`, `planner`, ... | `orchestrator`, `planner`, ... |
| Command names | `/agex:agex`, `/agex:agex-plan`, ... | `/agex`, `/agex-plan`, ... | `/agex`, `/agex-plan`, ... |
| Session logging hooks | Active | Not installed; can be added by hand | Not installed; can be added by hand |
| Collisions with your own agents | Cannot affect AGEX's dispatches | Possible | Only with the project's own agents; the copies take precedence over your user agents of the same name |
| Changing the prompts | Fork the repository | Edit the files in `~/.agex` | Edit and commit them in the project |
| Updating | `claude plugin update agex@agex-marketplace` | `git -C ~/.agex pull` | Copy the files again |

If you are unsure, use the plugin. Choose the script install for short names or to edit the prompts for all your projects, and a project copy when a team wants a pinned AGEX version in its repository or needs AGEX in CI. Use one method at a time: with two, agents and commands can show up twice.

A project copy, run from the project root:

```bash
git clone --depth 1 https://github.com/saksham-eng560/agex.git /tmp/agex
mkdir -p .claude/agents .claude/commands
cp -i /tmp/agex/.claude/agents/*.md .claude/agents/
cp -i /tmp/agex/.claude/commands/*.md .claude/commands/
```

`cp -i` asks before overwriting a file the project already has.

### Why are the commands called /agex:agex and /agex:agex-plan in a plugin install?

Claude Code namespaces every plugin component with the plugin's name, as `<plugin>:<component>`. The plugin is named `agex` and the main command's file is `agex.md`, so it becomes `/agex:agex`; `agex-plan.md` becomes `/agex:agex-plan`, and the agents become `agex:orchestrator`, `agex:coder`, and so on. You do not have to type the full name: type `/agex` and pick the command from the autocomplete list.

The namespace is also what protects AGEX from name collisions. The orchestrator dispatches `agex:<name>` whenever the Agent tool lists it, and no project or user agent can shadow a scoped name. If you prefer the short names, use the script install or a project copy and accept the collision caveat in the next answer.

### I already have agents named planner or reviewer. Will AGEX collide with them?

With the plugin install, no. With the script install, it can:

- Claude Code identifies an agent by the `name` in its frontmatter and resolves a bare name by scope: project (`.claude/agents/`) first, then user (`~/.claude/agents/`), then plugins. A script install puts AGEX's agents in `~/.claude/agents/` under bare names, which is the same namespace your own user agents live in. A pre-existing `~/.claude/agents/planner.md`, or any agent whose `name` is one of the twelve AGEX names, collides.
- `install.sh` and `install.ps1` never overwrite an existing file. If a file with the same name as an AGEX file already exists in `~/.claude/agents` or `~/.claude/commands`, the installer skips it with a warning. Re-run it with `--force` (`-Force` on Windows) to replace the file: the installer first moves your file to a backup directory, `~/.claude/.agex-backup/<timestamp>/`, and `--uninstall` puts it back later. The installer also warns when a file with a different name declares the same `name` as an AGEX agent, because that collides too.
- While a collision is in place, a bare-name dispatch reaches your agent instead of AGEX's. Your agent does not return the AGEX artifact format, so the orchestrator treats its reply as malformed, retries once, and then escalates.
- A project-level agent with an AGEX name, such as a `reviewer` in a project's `.claude/agents/`, overrides the AGEX agent inside that project even when the installer linked everything cleanly.

A project copy works the other way around: the copied files are project-level agents, so inside that project they take precedence over your user agents of the same name, and `cp -i` keeps them from overwriting the project's own files.

To check, run `/agex-status`. Its Available column marks a bare name whose description does not match the AGEX role as `(possible collision)`.

Fixes, best first:

1. Switch to the plugin install; `agex:` names cannot be shadowed.
2. Rename your own agent: change both its `name` field and its file name, then start a new session.
3. Re-run the installer with `--force` to replace your agent with AGEX's; your file waits in the backup directory until you uninstall.

Even with the plugin, your own `reviewer` still answers when you ask for "the reviewer agent" in plain language, because bare names resolve to project and user agents first. Say "the agex:reviewer agent" to get AGEX's.

### Does AGEX work on Windows?

Yes, in three ways:

- **Plugin.** The two `claude plugin` commands work the same on Windows and involve no links. This is the simplest option.
- **`install.ps1`.** Run `irm https://raw.githubusercontent.com/saksham-eng560/agex/main/install.ps1 | iex`, or clone the repository to `$HOME\.agex` and run `.\install.ps1`. If your execution policy blocks local scripts, run `powershell -ExecutionPolicy Bypass -File .\install.ps1`, which relaxes the policy for that one process only. It accepts `-Uninstall`, `-Force`, `-Dir <path>`, `-NoUpdate`, and `-Help`, and the same `AGEX_HOME`, `AGEX_REPO`, `CLAUDE_HOME`, and `NO_COLOR` overrides as `install.sh`. Because `irm ... | iex` cannot pass parameters, it also reads `AGEX_UNINSTALL=1`, `AGEX_FORCE=1`, and `AGEX_NO_UPDATE=1` from the environment, for example `$env:AGEX_UNINSTALL = '1'` before the one-liner.
- **WSL.** If you run Claude Code inside WSL, install with `install.sh` inside WSL. Windows and WSL have separate home directories and therefore separate `~/.claude` configurations.

Windows creates symbolic links only when Developer Mode is enabled or the shell runs elevated (Run as administrator). When neither is true, `install.ps1` copies the agent and command files instead of linking them. The copies work exactly the same, but they do not follow `git pull`: after updating the clone, run `install.ps1` again to refresh them. Running the `irm` one-liner again does both. Use `install.ps1` rather than `install.sh` on Windows: `install.sh` stops with an error when it cannot create real symbolic links, as in Git Bash.

AGEX's command context injections and its logging hook are POSIX shell snippets (`head`, `2>/dev/null`, `|| echo`). On native Windows they depend on Claude Code running shell commands through Git Bash from Git for Windows. If a command aborts with "Shell command failed" on Windows, check that Git for Windows is installed and used by Claude Code, or run Claude Code in WSL.

### How do I update AGEX?

**Plugin:**

```bash
claude plugin marketplace update agex-marketplace
claude plugin update agex@agex-marketplace
```

The first command refreshes the marketplace listing, so the second one finds the new version.

**install.sh (macOS, Linux):**

```bash
git -C ~/.agex pull
```

Or run the curl one-liner again, which updates the clone and re-links. The installed agents and commands are links into `~/.agex`, so a pull takes effect in your next Claude Code session. If a release adds new agent or command files, run `~/.agex/install.sh --no-update` once so they get linked too.

**install.ps1 (Windows):**

```powershell
git -C "$HOME\.agex" pull
& "$HOME\.agex\install.ps1" -NoUpdate
```

The second line refreshes copied files and links new ones. Running the `irm` one-liner again does both steps.

**Project copy:** copy the files again from a fresh clone (see [the install comparison](#should-i-use-the-plugin-installsh--installps1-or-copy-agex-into-my-project)), review the result with `git diff`, and commit it.

In every case, start a new Claude Code session afterwards: agents and commands load when a session starts. To review changes before taking them on a script install, run `git -C ~/.agex fetch` and read `git -C ~/.agex log -p HEAD..origin/main`. If you edited files in `~/.agex`, keep those edits on a branch and rebase it onto each release, as described in [Customization](CUSTOMIZATION.md#where-the-agex-files-live). The [CHANGELOG](../CHANGELOG.md) lists what changed in each release.

### How do I uninstall AGEX?

**Plugin:**

```bash
claude plugin uninstall agex@agex-marketplace
claude plugin marketplace remove agex-marketplace
```

The second command is optional; it removes the marketplace entry as well.

**install.sh (macOS, Linux):**

```bash
~/.agex/install.sh --uninstall
rm -rf ~/.agex
```

Without a local clone, `curl -fsSL https://raw.githubusercontent.com/saksham-eng560/agex/main/install.sh | bash -s -- --uninstall` does the same as the first line. The second line deletes the clone and is optional.

**install.ps1 (Windows):**

```powershell
& "$HOME\.agex\install.ps1" -Uninstall
Remove-Item -Recurse -Force "$HOME\.agex"
```

If you installed into a custom `CLAUDE_HOME`, set the same value when uninstalling. Uninstalling removes only the links or copies the installer created and restores any files that `--force` (`-Force`) backed up. Your own agents and commands, including files the installer skipped, are left alone, and the checkout itself stays until you delete it.

**Project copy:** from the project root, delete the 12 agent files and 8 command files (use `git rm` instead of `rm` if you committed them):

```bash
rm .claude/agents/{orchestrator,researcher,architect,coder,reviewer,tester,debugger,documenter,devops,refactor,security,planner}.md
rm .claude/commands/agex.md .claude/commands/agex-{plan,status,research,review,test,secure,docs}.md
```

What is left behind: the `.agex/` session-log directories in your projects (safe to delete; git ignores them) and any logging hooks you added to a `settings.json` by hand.

## Usage

### What is the difference between /agex, the orchestrator agent, and claude --agent orchestrator?

All three run the same orchestration protocol. They differ in where the orchestrator runs, which model and tools it has, and how escalations reach you.

| How you start | Orchestrator runs as | Model | Tools | Escalations reach you |
|---|---|---|---|---|
| `/agex <task>` | Your main conversation | Your session model | The main conversation's tools; "delegate, do not edit" is a prompt rule | Immediately; the run waits for your answer |
| "Use the orchestrator agent to ..." or an @-mention (plugin: `agex:orchestrator`) | A subagent, one layer below your conversation | `opus` | Agent, Read, Grep, Glob, Bash; no Write or Edit | At the end, inside an AgexReport with status ESCALATED |
| `claude --agent orchestrator` (plugin: `claude --agent agex:orchestrator`) | The whole session | `opus` | Agent, Read, Grep, Glob, Bash for the whole session | Immediately |

- **`/agex`** is the default. You see every dispatch and artifact as it happens and can interrupt and redirect the run at any point, as with any Claude Code turn.
- **The orchestrator subagent** keeps your main context clean: the whole run happens in a separate context and only the AgexReport comes back. A subagent cannot ask you questions mid-run, so prefer `/agex` when you expect to steer.
- **`claude --agent orchestrator`** makes the orchestrator's restrictions real for the whole session: no Write or Edit tool exists, so it can only delegate.

In every mode the specialists run one layer below the orchestrator, each in its own context window.

### When should I use /agex and when a focused command?

Use a focused command when you already know which specialist you need. It dispatches one agent and presents its artifact, without the planning and loop machinery:

| You want | Command | Artifact |
|---|---|---|
| A plan to look at before anything runs | `/agex-plan <task>` | TaskPlan |
| An answer about the codebase, with `file:line` evidence | `/agex-research <topic>` | ResearchBrief |
| A review of staged changes, a path, or a git ref | `/agex-review [path or git ref]` | ReviewVerdict |
| Tests written and run | `/agex-test [target]` | TestReport |
| A scan for secrets, OWASP Top 10 issues, and risky dependencies | `/agex-secure [scope]` | SecurityAuditReport |
| Documentation written or updated | `/agex-docs <docs task>` | DocUpdate |
| A change that must be implemented, tested, and reviewed | `/agex <task>` | AgexReport |

Focused commands never chain into fixes on their own. For example, when `/agex-test` finds a bug in application code, it offers `/agex` with the failure traces, so the fix runs under the circuit breakers. You can also call any agent in plain language: "Use the debugger agent to find out why `tests/test_parser.py` fails".

### Does AGEX need a git repository?

No. Every command's context injection ends in a fallback, so the commands work in brand-new and non-git directories; the orchestrator then explores with Read, Grep, and Glob. Git does help: `/agex-review` reviews staged changes, unstaged changes, or the last commit when you do not name a path, and starting a run from a clean working tree means `git diff` afterwards shows exactly what AGEX changed.

### How does AGEX detect my language, test runner, and linter?

AGEX has no language-specific code or configuration to set up. At the start of each run the agents read your project:

1. **`CLAUDE.md`.** The orchestrator reads your project instructions and passes the conventions and commands they contain to every specialist in the Constraints field of its delegation packet. The coder also reads the `CLAUDE.md` files in the directories it touches.
2. **Manifests and lockfiles:**

   | File | What the agents use |
   |---|---|
   | `package.json` | The `test`, `lint`, and `typecheck` scripts; the lockfile picks the package manager (`pnpm-lock.yaml` for pnpm, `yarn.lock` for yarn, `bun.lock` for bun, otherwise npm); jest, vitest, mocha, playwright, or cypress configuration; `npx tsc --noEmit` and `npx eslint` as fallbacks |
   | `pyproject.toml`, `pytest.ini`, `tox.ini` | pytest or unittest, ruff, mypy or pyright, prefixed with `uv run` or `poetry run` when `uv.lock` or `poetry.lock` exists |
   | `go.mod` | `go vet` and `go test ./...`, with `-race` when concurrency is involved |
   | `Cargo.toml` | `cargo check`, `cargo clippy`, and `cargo test` |
   | `Makefile` | Existing `test`, `lint`, or `check` targets |

3. **Existing tests.** The tester studies nearby test files (`*.test.*`, `*.spec.*`, `test_*.py`, `*_test.go`) and copies their framework, placement, naming, fixtures, and mocking style.

Other ecosystems work too, because the agents read whatever build files they find, but for predictable results state the exact commands near the top of your `CLAUDE.md`. The `/agex` command shows the orchestrator the first 40 lines before the run starts, and the orchestrator reads the rest itself:

```markdown
## Commands
- Test: bundle exec rspec
- Lint: bundle exec rubocop
- Type check: not configured
```

The tester does not install missing tools or change manifests; if a required tool is missing, it reports status ERROR with the command you would run. The coder adds a dependency only when the TechnicalRFC calls for it. Coverage is reported only when the project already has a coverage tool configured; otherwise the TestReport says "not measured".

### Can subagents spawn subagents?

Yes. Claude Code supports nested subagents by default up to 3 layers below the main conversation, and the `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH` environment variable changes that limit. This is what lets a delegated orchestrator (layer 1) dispatch specialists (layer 2).

AGEX never needs more than two layers, because only the orchestrator has the Agent tool. The eleven specialists are leaves and cannot spawn anything. That is deliberate: every loop counter and the dispatch budget live in one place, and a read-only agent cannot get around its restrictions by delegating a write to an agent that has Write.

If you lower the limit to 1, a delegated orchestrator cannot dispatch specialists. It escalates instead of doing the work itself. In that configuration use `/agex` or `claude --agent orchestrator`, which keep the orchestrator in the main session so that specialists run at layer 1. See [Nesting Model](ARCHITECTURE.md#nesting-model) for details.

### What happens when a circuit breaker trips?

AGEX runs two feedback loops per work unit, coder ⇄ tester and coder ⇄ reviewer, each with its own counter. A breaker trips when:

| Breaker | Trips when |
|---|---|
| Coder ⇄ tester | The re-run that closes the 3rd cycle still fails, which is the third failing TestReport inside the loop |
| Coder ⇄ reviewer | The re-review that closes the 3rd cycle is not APPROVED. A BLOCKED verdict stops the loop at once: the orchestrator either escalates or routes the unit once to the architect for a redesign, and a second BLOCKED on the same unit always escalates |
| No progress | Two consecutive cycles fail with the same failure signature (the same failing tests and errors, or the same review issues) |
| Sub-agent failure | An agent errors, returns nothing, or returns a malformed artifact, and the one retry with narrower instructions fails too |

The orchestrator then stops work on that unit and emits this block:

```text
### ESCALATION: <loop or agent> circuit breaker tripped
- What was attempted: <cycles, agents>
- Evidence: <latest artifact excerpt>
- Options: 1) ... 2) ... 3) ...
- Recommended: <option>
```

With `/agex` the block appears immediately and the run waits for your decision. Reply with an option number or new direction: allow one more cycle, send the unit to the architect for a redesign, narrow the scope, or take over by hand. With a delegated orchestrator the block arrives inside the Open Issues & Escalations section of an AgexReport whose status is ESCALATED. When `.agex/` exists, an ESCALATION line is also written to the session log.

AGEX does not roll anything back. Changes made before the breaker tripped stay in your working tree; inspect them with `git diff` and keep, fix, or discard them. A run with a tripped breaker is never reported as DONE.

The 15-dispatch budget works differently: reaching it is a checkpoint, not a failure. The orchestrator summarizes progress and asks whether to continue.

### Can I change the 3-cycle limit?

Yes, but it is an instruction in two prompts, not a setting:

- `.claude/agents/orchestrator.md` applies when the orchestrator agent runs, delegated or through `claude --agent orchestrator`. The limit appears in the Loop step and in Hard Constraints.
- `.claude/commands/agex.md` applies when you type `/agex`. The limit appears in the Circuit breakers section and in Hard Rules.

Change the same number in both files, or the two entry points will behave differently. The coder, tester, and reviewer prompts also mention the cap when they describe their place in the pipeline; update those sentences as well. To find every line involved on a script install:

```bash
grep -nE "[0-9]+ cycles|dispatches|consecutive|retry" ~/.agex/.claude/agents/orchestrator.md ~/.agex/.claude/commands/agex.md
grep -rlE "[0-9]+ cycles" ~/.agex/.claude/agents
```

Edit the files in `~/.agex` on a branch for a script install, in the project for a project copy, or in your fork for a plugin install (plugin files are replaced on every update). For a single run you do not need to edit anything: when the escalation arrives, authorize the extra cycles in your reply.

A limit of 2 saves cost when your test suite is fast and failures are clear-cut, and 4 or 5 can help in large legacy codebases with slow feedback. Above 5 rarely helps, because repeated failures usually point to a design problem. Keep the no-progress rule and the BLOCKED stop either way. Details are in [Tuning the circuit breakers](CUSTOMIZATION.md#tuning-the-circuit-breakers).

### Can I run AGEX headless or in CI?

Yes, through Claude Code's print mode. For example:

```bash
claude -p "/agex Fix the failing test in tests/test_parser.py" \
  --permission-mode acceptEdits \
  --allowedTools "Bash(pytest *)" "Bash(ruff check *)" \
  --permission-prompts none \
  --max-budget-usd 5 \
  --output-format json
```

With the plugin, use `/agex:agex`. To run the orchestrator agent itself, with its tool restrictions, use `claude --agent orchestrator -p "<task>"`.

Things to know:

- **AGEX must be available in the job.** Either commit a [project copy](#should-i-use-the-plugin-installsh--installps1-or-copy-agex-into-my-project) of the agents and commands to the repository, or clone AGEX in the job and load it for that session only with `--plugin-dir`, which gives you the plugin names:

  ```bash
  git clone --depth 1 https://github.com/saksham-eng560/agex.git /tmp/agex
  claude -p "/agex:agex-review" --plugin-dir /tmp/agex
  ```

- **Nobody can answer permission prompts.** Decide in advance what the run may do: `--permission-mode acceptEdits` accepts file edits, `--allowedTools` pre-approves specific commands such as your test runner and linter, and `--permission-prompts none` denies everything else automatically. Deny rules in your settings still apply.
- **Escalations and questions end the run.** In print mode an ESCALATION block, a NEEDS_INPUT plan, or the 15-dispatch checkpoint becomes the final output. Check the AgexReport status (DONE, PARTIAL, or ESCALATED) before acting on the result.
- **Be careful with autonomous edits.** Run on a disposable branch or container, and have the CI job, not AGEX, open a pull request so that a person reviews the diff before it merges. Do not give the job production credentials, and do not use `--dangerously-skip-permissions` on untrusted input: pull requests from forks can carry prompt injection. In print mode nobody can confirm the devops agent's remote operations, so it stops at READY_FOR_CONFIRMATION; keep it that way.
- **Cap the spend** with `--max-budget-usd`, set to what you are willing to pay per job.
- **Start with read-only runs.** `/agex-review` and `/agex-secure` return a ReviewVerdict or SecurityAuditReport without changing any file, which makes them the safest place to begin.

Authenticate Claude Code in the job as you would for any other headless use, with the credentials stored as CI secrets.

### How do I add my own agent?

1. Copy [templates/custom-agent.md](../templates/custom-agent.md) to `.claude/agents/<name>.md` in your project, or to `~/.claude/agents/<name>.md` for every project. Keep your own agents out of `~/.agex`, which belongs to the installer.
2. Fill in the frontmatter: a `name` equal to the file name (and not one of the twelve AGEX names), a one-line double-quoted `description` that starts with the role and says when to use the agent, the smallest `tools` list that works, a `model`, and a `color`.
3. Write the prompt with the template's sections: persona, place in the pipeline, numbered procedure, at least four NEVER constraints, and an output format that uses the AGEX artifact marker line, so the orchestrator can validate the result and route on its status. Keep it between 300 and 800 words.
4. Check it: run `claude plugin validate --strict .`, start a new session, confirm it appears in `/agents`, and call it once directly.
5. Make the orchestrator route to it, either with a routing note in your project's `CLAUDE.md` or by editing the routing tables in `orchestrator.md` and `agex.md`.

The full walkthrough, including tool choices and an example artifact, is in [Adding a custom agent](CUSTOMIZATION.md#adding-a-custom-agent) and [Making the orchestrator route to your agent](CUSTOMIZATION.md#making-the-orchestrator-route-to-your-agent). Custom commands start from [templates/custom-command.md](../templates/custom-command.md). To contribute an agent back to AGEX, read [Contributing custom agents upstream](CUSTOMIZATION.md#contributing-custom-agents-upstream) and [CONTRIBUTING](../CONTRIBUTING.md).

### Will AGEX commit, push, or deploy for me?

No. AGEX leaves its changes in your working tree for you to review. The coder never commits or pushes, and the orchestrator never runs remote or irreversible operations (push, deploy, publish, tag, release). Deployment work goes to the devops agent, which verifies changes locally and then stops with status READY_FOR_CONFIRMATION, listing every remote or irreversible action with its exact command. The orchestrator shows you that list verbatim; running any of it is your decision.

These are prompt-level rules, so add Claude Code permission rules as a second barrier, for example an `ask` or `deny` rule for `Bash(git push *)`. [SECURITY.md](../SECURITY.md) has a ready-made example.

## Safety & Security

### Are the read-only agents really read-only?

Partly, and the distinction matters:

| Agents | What enforces the restriction |
|---|---|
| architect, planner | The tool list. They have only Read, Grep, and Glob: no Bash, Write, or Edit, so they cannot change anything |
| researcher, reviewer, security | Write and Edit are denied at the tool level (`disallowedTools`), but they keep Bash to inspect the project (run tests, read `git log`, run dependency audits). Their prompts forbid redirects to files, installs, and git state changes. That is an instruction, not a sandbox |
| tester (test files only), documenter (docs only) | They have Write and Edit, and the path restriction is prompt-level. The documenter has no Bash |
| orchestrator | No Write or Edit tool when it runs as an agent or through `claude --agent orchestrator`. Under `/agex` the main conversation keeps its own tools, and "delegate, do not edit" is a prompt rule |

The real enforcement boundary for Bash is Claude Code's permission system. Every tool call a subagent makes passes through your permission mode and your allow, ask, and deny rules, exactly as in the main conversation. So:

- Keep permission prompts on for commands you have not pre-approved, and read them.
- Add deny rules for commands that must never run. Permission rules apply to the whole session, every subagent included; they cannot target a single agent.
- For a reviewer that truly cannot change anything, remove Bash from its tools (`tools: Read, Grep, Glob`). It then relies on what the orchestrator passes it and no longer runs tests or `git diff` itself.
- Do not combine AGEX with `--dangerously-skip-permissions` on code you have not vetted.

Plugin subagents ignore the `permissionMode`, `hooks`, and `mcpServers` frontmatter fields. AGEX agents do not use them, so an agent cannot grant itself extra permissions that way, and you cannot use those fields to restrict a plugin agent either.

### Does AGEX send my code or any data anywhere?

AGEX itself has no telemetry, no analytics, and no network code. It consists of Markdown prompts, a local shell logger that writes only to your project's `.agex/` directory, the installers, and the repository validator.

Network traffic during a run comes from:

- **Claude Code itself.** As in any Claude Code session, your prompts and the file contents that agents read are sent to the model provider Claude Code is configured to use. AGEX does not change where that data goes.
- **The researcher's web tools.** The researcher is the only AGEX agent with WebSearch and WebFetch. Remove them from its `tools` line to keep runs offline (see [Restricting or granting tools](CUSTOMIZATION.md#restricting-or-granting-tools)).
- **Commands you approve.** A dependency audit or a package manager command, for example, may contact its registry.
- **Installation and updates.** The installers clone and update the repository from GitHub, and the plugin install fetches it through the marketplace.

The session log never leaves your machine, and `.agex/` is ignored by git.

### Where are the logs, what do they contain, and how do I turn them off?

**Location.** `.agex/session.log` in the project root. Once the file passes 1 MiB it is rotated to `session.log.1`, and one previous generation is kept. `/agex-status` shows the last 20 events.

**Writers.**

- The hooks, active in plugin installs and inside the AGEX repository, write `SESSION_START` when a session starts or resumes, and `FILE_MODIFIED` after every Write, Edit, or MultiEdit tool call.
- The orchestrator, whenever `.agex/` already exists, writes `DISPATCH`, `ARTIFACT`, `CYCLE`, `ESCALATION`, and `RUN_COMPLETE`.

```text
[2026-09-27T10:15:02Z] SESSION_START source=startup
[2026-09-27T10:16:40Z] DISPATCH agent=coder unit=WU-1
[2026-09-27T10:17:55Z] FILE_MODIFIED tool=Write path=src/middleware/rateLimit.ts
[2026-09-27T10:19:12Z] ARTIFACT type=TestReport status=FAIL
[2026-09-27T10:19:13Z] CYCLE loop=coder-tester n=1/3
```

**Contents.** Timestamps, event names, tool and agent names, artifact statuses, and file paths (relative to the project root for files inside it, absolute for files outside it). Never file contents, diffs, prompts, or command output. File paths can still be sensitive; if yours are, turn logging off.

**Turning it off.** Set `AGEX_DISABLE_LOG=1`, either with `export AGEX_DISABLE_LOG=1` in your shell profile or in the `env` block of a Claude Code `settings.json` (see [Disabling logging](CUSTOMIZATION.md#disabling-logging)). The hook script then exits before writing anything and no longer creates `.agex/`. The variable does not affect the orchestrator, which logs only when `.agex/` exists, so delete that directory as well to stop logging in a project completely.

**Script installs and project copies** have no hooks, so there is no log by default. Add the hooks by hand ([instructions](CUSTOMIZATION.md#enabling-session-log-hooks-for-symlink-installs)), or create the directory yourself to record only the orchestrator's events:

```bash
mkdir -p .agex && printf '*\n' > .agex/.gitignore
```

**Why `.agex/` never shows up in `git status`.** When the hook script creates `.agex/`, it also writes `.agex/.gitignore` containing the single pattern `*`. That pattern ignores every file in the directory, including the `.gitignore` itself, so git has nothing to report and you never need to edit your project's own `.gitignore`. The orchestrator never creates the directory. With the plugin install, the SessionStart hook creates `.agex/` in every project you open; it is safe to delete at any time.

### Is it safe to run AGEX on an untrusted repository?

Be careful. Agents read project files, and the researcher reads web pages. A malicious README, code comment, test fixture, or web page can contain prompt injection that tries to make an agent run commands or ignore its constraints. Recommendations:

- Open untrusted code in a container, virtual machine, or dev container that holds no production credentials.
- Never combine that with `--dangerously-skip-permissions`.
- Deny reads of secret files with permission rules such as `Read(./.env)`, `Read(./.env.*)`, and `Read(./secrets/**)`.
- Review every diff before you commit it.

On its side, no AGEX prompt or command asks for credentials or reads `.env` contents, `/agex-secure` lists environment file names only, and the security agent redacts any secret it finds to the first 4 characters followed by `****`. The trust model and the full list of recommendations are in [SECURITY.md](../SECURITY.md).

To report a vulnerability in AGEX itself, use [GitHub private vulnerability reporting](https://github.com/saksham-eng560/agex/security/advisories/new), never a public issue.

## Troubleshooting

### A command fails with "Shell command failed" or "Shell command permission check failed"

AGEX commands collect project context with `!` shell injections, which Claude Code runs before the model sees the prompt. If an injection is not permitted, or exits with a non-zero status, Claude Code aborts the whole command with an error that begins with "Shell command permission check failed" or "Shell command failed" and names the injection that failed. AGEX's injections use only `git status`, `git ls-files`, `git diff`, `git log`, `grep`, `head`, `tail`, `ls`, `echo`, and `wc`, each pre-approved in the command's `allowed-tools`, and each ends in a fallback so it succeeds even outside a git repository.

**"Shell command permission check failed"** almost always comes from your own permission rules. Deny rules take precedence over a command's `allowed-tools`. Typical examples are a deny rule for `Bash(grep *)`, added to steer Claude toward its Grep tool, which breaks `/agex-test`, `/agex-secure`, and `/agex-docs`; or a broad `Bash(git *)` deny, which breaks every command that reads git state. An `ask` rule matching one of those programs has the same effect, because a slash command cannot stop to ask for approval. To fix it:

1. Find the rule. Look at `permissions.deny` and `permissions.ask` in `~/.claude/settings.json`, `.claude/settings.json`, and `.claude/settings.local.json`, plus managed settings if your organization uses them. The `/permissions` command in Claude Code shows the rules in effect.
2. Narrow it. Deny the dangerous forms, such as `Bash(git push *)` or `Bash(git reset *)`, instead of a whole program.
3. If the rule is managed by an administrator and cannot change, call the agents in plain language instead, for example "Use the reviewer agent to review my staged changes". That path involves no injections.

The same error appears if a customized command reads outside the project directory at injection time (for example `ls ~/.claude/agents`), because Claude Code requires approval for that. AGEX's own commands stay inside the project for this reason.

**"Shell command failed"** means an injection exited with a non-zero status. AGEX's shipped injections always end in a fallback, so the usual causes are a locally modified command file with an injection that lacks `2>/dev/null || echo "..."`, or a shell that is not POSIX-compatible (native Windows without Git Bash; see [Does AGEX work on Windows?](#does-agex-work-on-windows)). On a script install, `git -C ~/.agex diff .claude/commands` shows your local edits. For your own commands, follow the [Shell injection safety rules](CUSTOMIZATION.md#shell-injection-safety-rules).

### /agex is not recognized, or the AGEX agents are missing

1. **Check the name.** Plugin installs namespace everything: type `/agex` and pick `/agex:agex` from the autocomplete list.
2. **Start a new session.** Agents and commands load when a session starts. After installing the plugin mid-session, `/reload-plugins` also works.
3. **Check the install:**
   - Plugin: `claude plugin list` should show `agex`. If it is disabled, run `claude plugin enable agex@agex-marketplace`.
   - Script install: `ls -l ~/.claude/agents ~/.claude/commands`. Each AGEX entry should point into `~/.agex/.claude/`. A broken link means `~/.agex` was moved or deleted; run the installer again. If Claude Code reads its configuration from another directory (for example through `CLAUDE_CONFIG_DIR`), the installer still writes to `~/.claude` unless `CLAUDE_HOME` is set, and it prints a note when it sees `CLAUDE_CONFIG_DIR`; re-run it with `CLAUDE_HOME` set to that directory.
   - Project copy: the files must be in the project's `.claude/agents/` and `.claude/commands/`, and Claude Code must be started in that project.
4. **List what Claude Code sees.** `/agents` should show all 12 agents, and `/agex-status` reports each one as available, missing, or a possible collision.
5. **Look for skipped files.** If the installer skipped files because agents with the same names already existed, see [I already have agents named planner or reviewer](#i-already-have-agents-named-planner-or-reviewer-will-agex-collide-with-them).

When an agent the orchestrator needs is listed under neither its scoped nor its bare name, `/agex` and the orchestrator tell you which one is missing and stop rather than doing that agent's job themselves.

The focused commands (`/agex-plan`, `/agex-research`, `/agex-review`, `/agex-test`, `/agex-secure`, and `/agex-docs`) behave differently: if their specialist is listed under neither name, or the session has no Agent tool, they say so, suggest `/agex-status`, and do the task inline in your main conversation, following the specialist's procedure and constraints and returning the same artifact with the Producer `<name> (inline fallback)`, for example `reviewer (inline fallback)`. They never substitute a different agent (such as a built-in general-purpose agent) and never hand the work to another session or to a background, remote, or scheduled task. Inline, the specialist's tool restrictions are prompt rules only, because the main conversation keeps its own tools, so treat an inline fallback as a sign to fix the install and prefer the real agent for anything important.

### Every agent and command appears twice

AGEX is installed in two ways at once, most often the plugin plus a script install. Keep one and remove the other with the matching command from [How do I uninstall AGEX?](#how-do-i-uninstall-agex), then start a new session.

### No .agex/session.log is created

Work through the likely causes:

- **Script install or project copy.** Neither installs the logging hooks. Add them by hand or create `.agex/` for orchestrator events only, as described in [the logging answer](#where-are-the-logs-what-do-they-contain-and-how-do-i-turn-them-off).
- **`AGEX_DISABLE_LOG=1` is set** in your shell environment or in the `env` block of a settings file.
- **The file was changed by a shell command.** `FILE_MODIFIED` covers only the Write, Edit, and MultiEdit tools.
- **No orchestrator events.** The orchestrator writes only when `.agex/` already exists and never creates it.
- **The hook cannot write.** The script always exits 0, so a logging failure never interrupts a session and is silent by design. Check that the project directory is writable and that `sh` is available.

### AGEX stopped and asked me a question. Is something wrong?

Usually not. A run pauses by design when:

- **The dispatch budget is reached.** The next dispatch would exceed 15 in this run. Answer yes to continue, or narrow the remaining work.
- **A plan or design needs input.** A TaskPlan or TechnicalRFC with status NEEDS_INPUT means the requirements are ambiguous and the orchestrator could not settle them from context. Answer the questions it relays and the run continues.
- **Devops needs confirmation.** A DevOpsChange with status READY_FOR_CONFIRMATION lists remote or irreversible commands that were not run. Run them yourself or decline.
- **A circuit breaker tripped.** You see an ESCALATION block; see [What happens when a circuit breaker trips?](#what-happens-when-a-circuit-breaker-trips)

### The AgexReport says PARTIAL even though the tests pass

The quality gate needs more than passing tests. A run is DONE only when the latest TestReport is PASS (or tests are explicitly not applicable), the latest ReviewVerdict is APPROVED, no CRITICAL or HIGH security findings are open, and every acceptance criterion from the TechnicalRFC or TaskPlan has been checked. "Latest" means produced after the most recent code change, so a review-driven fix must be re-tested before the gate can pass. The report's Open Issues & Escalations section names the condition that failed and the Next Steps section says what to do about it.
