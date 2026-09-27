# Examples

Learn AGEX by example: five complete walkthroughs, from a REST API build to a security audit, and a set of quick recipes for everyday tasks, each with the agent chain you should expect. To install AGEX first, see the [Quickstart](QUICKSTART.md); for what each agent does, see [Agents](AGENTS.md).

## Worked Examples

| Example | Scenario | Command | Agents involved | Complexity |
|---|---|---|---|---|
| [Build a REST API with JWT authentication](../examples/web-app-build/task.md) | A Node.js and TypeScript service that only answers a health check gains registration, login, owner-scoped todo CRUD, validation, tests, and API docs | `/agex Build a REST API for a todo app with JWT authentication, input validation, and tests` | planner, researcher, architect, coder (4 work units, 2 in parallel), tester, reviewer, documenter; 15 dispatches | COMPLEX |
| [Fix a logout-on-refresh authentication bug](../examples/bug-fix/task.md) | Users are signed out on every page reload since the API moved under `/api`, while all tests stay green | `/agex Fix the auth bug where users are logged out after refreshing the page` | debugger, tester, reviewer; 3 dispatches | MEDIUM |
| [Review a payment webhook handler](../examples/code-review/task.md) | Staged changes verify a webhook signature with a comparison that is not constant-time | `/agex-review`, then optionally `/agex` with the findings | reviewer and security in parallel; the optional fix run uses coder, tester, reviewer, and security | Focused command; fix run MEDIUM |
| [Build a streaming CSV-to-JSON command-line tool](../examples/full-project/task.md) | A new Python 3.11 tool built from an almost empty package with the standard library, argparse, and pytest | `/agex Build a CLI tool that converts CSV files to JSON with streaming support` | planner, researcher, architect, coder (3 work units, 2 in parallel), tester, reviewer, documenter; 14 dispatches | COMPLEX |
| [Audit a Flask shop and fix its critical findings](../examples/security-audit/task.md) | A live key in a tracked `.env`, SQL injection, no CSRF protection, outdated dependencies, and a container running as root | `/agex-secure`, then `/agex Fix the CRITICAL and HIGH findings from the security audit` | security; the fix run uses coder (2 in parallel), tester, reviewer, and a security re-check | Focused command; fix run MEDIUM |

What each walkthrough shows:

- **REST API:** the full COMPLEX pipeline, parallel coders kept on disjoint files, a coder-tester loop that catches an authorization hole before review, a coder-reviewer loop, and a run that lands exactly on the soft budget of 15 dispatches.
- **Bug fix:** why bugs go to the debugger first. It reproduces, isolates, and root-causes the failure before a minimal fix, and the tester adds a regression test that would have caught the original bug.
- **Code review:** the security agent joining the reviewer automatically for cryptography and untrusted input, two artifacts merged into one bottom line, and the decision rule that turns a single HIGH issue into CHANGES_REQUESTED.
- **Command-line tool:** a TaskPlan's execution waves turned into parallel work, tests derived from the design catching what a smoke test missed, a fix that moves only one work unit's loop counter, and a README written after the review approves.
- **Security audit:** secrets that are never printed, severity rating, a fix run scoped to CRITICAL and HIGH findings, why a FINDINGS re-check can still pass the quality gate, and why rotating a leaked key matters more than deleting it.

Every walkthrough uses the same sections: Scenario, The Command, What AGEX Does, Illustrative Artifact Excerpts, Expected Outcome, and Variations and Tips. The projects, paths, line numbers, command output, and counts are illustrative rather than recorded, but internally consistent, so you can follow every decision. The envelopes, section names, statuses, and routing rules are the ones AGEX uses, as defined in the [Handoff Protocol](HANDOFF-PROTOCOL.md). Commands are shown in their script-install form; with the plugin install, use `/agex:agex`, `/agex:agex-secure`, and so on (typing `/agex` autocompletes them).

## Quick Recipes

Each recipe is one line to type plus the chain AGEX is expected to run. Chains follow the routing table in [Architecture](ARCHITECTURE.md#complexity-tiers-and-routing). For `/agex` tasks, the orchestrator adapts the chain to the complexity it assigns, and it always states the class and the planned chain before it dispatches anything.

### Investigate how something works

```text
/agex-research how does caching work in this repo
```

**Chain:** researcher → ResearchBrief.

Read-only from start to finish. The researcher searches the codebase first and the web second, and anchors every claim to a `path:line` or a documentation link. The main conversation spot-checks two or three of the cited locations, then presents the brief with a direct answer.

### Write and run tests for one area

```text
/agex-test the date utilities
```

**Chain:** tester → TestReport; if the tests expose a bug, an `/agex` run with the Failure Traces sends it to the debugger or coder.

The tester detects the test runner, follows the style of nearby tests, and only creates or edits test files. When a test reveals a bug in application code, it reports a failure trace instead of fixing it, and the command offers an `/agex` run that fixes it under the circuit breakers. Without an argument, `/agex-test` tests your uncommitted changes, or the last commit when the working tree is clean. A missing test tool produces status ERROR with the install command for you to run; the tester never installs anything.

### Document a module's public API

```text
/agex-docs document the public API of the payments module
```

**Chain:** documenter → DocUpdate.

The documenter reads every signature before documenting it, follows the project's docstring or JSDoc conventions, and keeps existing documentation unless you ask it to replace something. It has no shell, so its examples are checked against the code rather than executed, and the DocUpdate says so. Run `/agex-docs` without a task to get an audit of documentation gaps: it proposes changes and writes nothing until you choose which ones to apply.

### Refactor without changing behavior

```text
/agex Refactor the order service to remove duplication
```

**Chain:** refactor → RefactorReport → reviewer → ReviewVerdict.

The refactor agent runs the full test suite before touching anything. If the baseline is red, or no tests cover the code, it stops with ABORTED and recommends running the tester first. Otherwise it applies one named refactoring at a time (Extract Function, Move Function, and so on), re-runs the suite after each step, and reverts any step that changes a result. A COMPLETE report states `Behavior Change: None`.

### Set up continuous integration

```text
/agex Set up GitHub Actions CI with lint and test jobs
```

**Chain:** devops → DevOpsChange → reviewer → ReviewVerdict, then your confirmation for any remote step.

The devops agent writes the workflow with pinned action versions and read-only default permissions, and verifies it locally: with `actionlint` when it is installed, and by running the lint and test commands the jobs will call. The workflow only runs on GitHub after a push, and a push is a remote operation, so the DevOpsChange comes back READY_FOR_CONFIRMATION with the exact `git push` command listed, not executed. The orchestrator shows you that list verbatim. Push yourself, or confirm the numbered item, and devops is dispatched again with your confirmation quoted.

### Plan a large change before starting it

```text
/agex-plan migrate from REST to GraphQL
```

**Chain:** planner → TaskPlan. Nothing is executed.

The plan lists every step with its agent, dependencies, parallel group, and complexity, groups the steps into execution waves, and pairs each risk with a mitigation; the summary estimates the number of dispatches. A migration this size typically exceeds the soft budget of 15 dispatches per run, which the plan flags, and typically comes back NEEDS_INPUT with questions only you can answer, such as whether the REST endpoints must keep working during the transition. Answer them, then run the waves as separate `/agex` tasks, each ending with its own quality gate.

### Fix a failing test

```text
/agex Fix the failing test tests/test_parser.py::test_empty_row
```

**Chain:** debugger → DebugReport → tester (regression test) → reviewer.

Bugs go to the debugger first: it reproduces the failure, isolates it, and names the root cause at a `path:line` before it makes a minimal fix. A failing test id, stack trace, or exact reproduction steps in the task shorten the reproduce step. See the [bug fix example](../examples/bug-fix/task.md).

### Review a branch before merging

```text
/agex-review main
```

**Chain:** reviewer → ReviewVerdict, plus security → SecurityAuditReport in parallel when the diff touches authentication, input handling, cryptography, or secrets.

A git ref reviews everything on your branch since it diverged from that ref, and a path reviews that path. Without an argument, the command reviews staged changes, then unstaged and untracked changes, then the last commit. It is read-only; fixes go through `/agex`. See the [code review example](../examples/code-review/task.md).

### Check the installation and recent activity

```text
/agex-status
```

**Chain:** none; no agent is dispatched.

Lists the AGEX agents Claude Code can see, the tail of `.agex/session.log`, and a summary of the project context. Run it first whenever a command reports that an AGEX agent is not available.

### Run a dedicated orchestration session

```bash
claude --agent orchestrator
```

With the plugin install: `claude --agent agex:orchestrator`.

**Chain:** whatever each task needs; the session itself is the orchestrator.

The whole session adopts the orchestrator's prompt, model (Opus), and tools (Agent, Read, Grep, Glob, Bash). You type tasks in plain language without `/agex`, and escalations come straight to you. With `/agex`, your main conversation keeps its own tools and the "delegate, do not edit" rule lives in the command prompt; in this session the orchestrator has no Write or Edit tool at all. [Nesting Model](ARCHITECTURE.md#nesting-model) compares this with `/agex` and with delegating a task to the orchestrator as a subagent.

### Run AGEX headless in scripts or CI

```bash
claude -p "/agex Add input validation to POST /users, with tests" \
  --permission-mode acceptEdits \
  --allowedTools "Bash(npm test)" "Bash(npm test *)" "Bash(npm run lint)" "Bash(npx tsc --noEmit)" \
  --disallowedTools "Bash(git push *)" "Bash(npm publish *)" \
  --max-budget-usd 5 \
  --output-format json > agex-run.json
jq -r .result agex-run.json
```

**Chain:** the same as an interactive `/agex` run; the AgexReport is the `result` field of the JSON output.

Print mode (`-p`) expands custom slash commands, so `/agex` works unchanged (`/agex:agex` with the plugin install). Nobody is present to answer a permission prompt, so decide up front what the run may do:

- **Pre-approve narrowly.** A tool call that is not pre-approved is refused instead of being asked about, and the affected agent reports that it could not run it. Allow exactly the commands the task needs. `acceptEdits` lets every agent that has Write or Edit change files without asking, so start from a clean branch and review `git diff` afterwards.
- **Deny remote operations explicitly,** as above. The devops agent stops before them on its own, but a permission rule holds no matter what any prompt says.
- **Never bypass permissions outside a sandbox.** Do not use `--dangerously-skip-permissions` or `--permission-mode bypassPermissions` except in a disposable environment with no credentials and no network access.
- **Run it only in repositories you trust.** Print mode skips the workspace trust dialog, and agents read project files, which can contain prompt injection.
- **Expect questions to end the run.** A NEEDS_INPUT plan or an ESCALATION block ends a headless run with the question in the result. Continue interactively with `claude --continue` in the same directory.
- **Cap the cost.** The orchestrator runs on Opus; `--max-budget-usd` sets a spending limit for the run.

For tool-level enforcement of the orchestrator's own restrictions, run `claude -p --agent orchestrator "Add input validation to POST /users, with tests"` with the same permission flags. Project-wide allow and deny rules can also live in `.claude/settings.json`; see [Restricting or granting tools](CUSTOMIZATION.md#restricting-or-granting-tools).

## Writing Tasks That Work Well

- **Say what done looks like.** "Add pagination to GET /orders, with tests" gives the tester and reviewer a target; "improve the orders endpoint" does not.
- **State decisions you have already made.** Name the database, library, or runtime version you want, and the planner records it as a constraint instead of an assumption.
- **Give bugs evidence.** Include the exact error, the failing test id, or the reproduction steps.
- **Slice large work.** Keep each `/agex` task within about 15 dispatches; every slice then ends with its own quality gate.
- **Put your commands in `CLAUDE.md`.** The orchestrator copies the build, lint, and test commands into every delegation packet.
- **Start from a clean working tree.** Then `git diff` shows exactly what AGEX changed, and nothing is committed until you commit it.

## Related Documentation

- [Quickstart](QUICKSTART.md): install AGEX and run your first task.
- [Architecture](ARCHITECTURE.md): the pipeline, circuit breakers, quality gate, and install modes.
- [Agents](AGENTS.md): every agent's role, tools, model, and artifact.
- [Handoff Protocol](HANDOFF-PROTOCOL.md): the exact format of every artifact shown in the examples.
- [Customization](CUSTOMIZATION.md): add your own agents and commands, change models, and tune the breakers.
- [FAQ](FAQ.md): cost, safety, and troubleshooting.
