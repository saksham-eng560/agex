---
description: "Show AGEX agent status and session info"
allowed-tools: Bash(ls *) Bash(echo *) Bash(head *) Bash(tail *) Bash(wc *)
---

# AGEX Status

Report the state of AGEX in this session. This command is read-only: do not create, modify, or delete anything (including `.agex/`), and do not dispatch any agent.

## Installed Components

### Project-level agents (.claude/agents)

```text
!`ls -1 .claude/agents 2>/dev/null || echo "(no project-level agents)"`
```

User-level agents in `~/.claude/agents` are not listed here: Claude Code blocks command-time listings outside the project directory, and such a listing would abort this command. The Agents step below relies on your Agent tool list instead, which covers them.

### Project-level commands (.claude/commands)

```text
!`ls -1 .claude/commands 2>/dev/null || echo "(no project-level commands)"`
```

## Session Log

### Last 20 events (.agex/session.log)

```text
!`tail -20 .agex/session.log 2>/dev/null || echo "(no AGEX session log yet)"`
```

### Line count

```text
!`wc -l .agex/session.log 2>/dev/null || echo "0 events logged"`
```

## Project

### Top-level listing (first 40 entries)

```text
!`ls -1A 2>/dev/null | head -40`
```

## Instructions

Write the report below in this order. Keep it concise and base every statement on the data above or on read-only checks you run now.

### 1. Agents

A table with the columns `Agent | Role | Model | Read-only | Available`, one row per AGEX agent. Use these values for the first four columns (the model is each agent's frontmatter default; users can change `model:` per agent):

| Agent | Role | Model | Read-only |
|---|---|---|---|
| orchestrator | Master coordinator: classifies, decomposes, dispatches, enforces circuit breakers, writes the AgexReport | opus | no edits (delegates) |
| researcher | Investigates code, docs, and the web; writes a ResearchBrief | sonnet | yes |
| architect | Designs components and atomic work units; writes a TechnicalRFC | sonnet | yes |
| coder | Implements one work unit at a time; writes a CodeDiff | sonnet | no |
| reviewer | Adversarial code review; writes a ReviewVerdict | sonnet | yes |
| tester | Writes and runs tests; writes a TestReport | sonnet | test files only |
| debugger | Reproduces, root-causes, and fixes bugs; writes a DebugReport | sonnet | no |
| documenter | Writes and updates docs; writes a DocUpdate | haiku | docs only |
| devops | CI/CD, Docker, deployment config; writes a DevOpsChange | sonnet | no (remote ops need human OK) |
| refactor | Behavior-preserving refactoring; writes a RefactorReport | sonnet | no |
| security | Secrets, OWASP Top 10, dependency, and config audit; writes a SecurityAuditReport | sonnet | yes |
| planner | Breaks tasks into ordered, assigned steps; writes a TaskPlan | haiku | yes |

Fill the Available column from the agent types your own Agent tool lists in this session. That list is authoritative and covers project, user, and plugin agents; the directory listing above only shows project files. If bare names are missing after a clone or symlink install, you may check `~/.claude/agents` with a normal Bash call such as `ls -1 ~/.claude/agents` (Claude Code will ask the user to approve it).

Write one of these plain-text values in the Available column (no symbols or emojis):

- `agex:<name>`: the scoped name is listed, so the agent comes from the plugin install. Scoped names cannot be shadowed by other agents.
- `<name>`: only the bare name is listed, so the agent comes from a project or user agent file (clone or symlink install). Bare names resolve project `.claude/agents` first, then `~/.claude/agents`, then plugins.
- `<name> (possible collision)`: the bare name is listed, but its description does not match the AGEX role above, so a non-AGEX agent may be using the name.
- `missing`: neither name is listed.
- `unknown`: you have no Agent tool in this session; say so below the table.

### 2. Commands

List the eight AGEX commands with a one-line purpose each: `/agex` (orchestrate any task), `/agex-plan` (plan without executing), `/agex-status` (this report), `/agex-research` (researcher), `/agex-review` (reviewer on recent changes), `/agex-test` (tester), `/agex-secure` (security audit), `/agex-docs` (documenter). Say how they are installed, judging from the project-level commands listing above and the commands available in this session: project `.claude/commands` files, user-level commands from the install script (`~/.claude/commands`), or plugin commands namespaced as `/agex:agex`, `/agex:agex-plan`, and so on.

### 3. Session Activity

Summarize the log: the total number of logged events (the line count above), sessions started (SESSION_START), files modified (FILE_MODIFIED, naming the most frequently modified paths), orchestrator dispatches (DISPATCH, by agent), artifacts (ARTIFACT, by type and status), feedback-loop cycles (CYCLE), escalations (ESCALATION), and completed runs (RUN_COMPLETE), plus the time range the last 20 events cover. The tail holds only the last 20 lines; for whole-log counts, use the Grep tool in count mode on `.agex/session.log`. The logger rotates the file at 1 MiB, so older events may be in `.agex/session.log.1`. Call out any escalation explicitly. If there is no log, say so and give the likely reason from the notes below.

### 4. Project Context

Two to four sentences from the top-level listing: the likely stack (which manifests are present), whether a CLAUDE.md exists, whether `.agex/` exists, and whether this is the AGEX repository itself.

### 5. Notes

- Session logging is written by the AGEX hooks, which are active in plugin installs and when working inside the AGEX repository itself. Symlink installs (install.sh or install.ps1) get agents and commands only; hooks can be added manually as described in docs/CUSTOMIZATION.md of the AGEX repository (https://github.com/saksham-eng560/agex/blob/main/docs/CUSTOMIZATION.md).
- The hooks log SESSION_START and FILE_MODIFIED lines with event names and paths only, never file contents; `.agex/` carries its own `.gitignore`, so it stays out of git. `/agex` runs append DISPATCH, ARTIFACT, CYCLE, ESCALATION, and RUN_COMPLETE lines when `.agex/` exists.
- Setting `AGEX_DISABLE_LOG=1` in the environment turns hook logging off.
- Finish with the concrete problems you found (missing agents, possible name collisions, no log) and the fix for each. To reinstall: `curl -fsSL https://raw.githubusercontent.com/saksham-eng560/agex/main/install.sh | bash`, or as a plugin: `claude plugin marketplace add saksham-eng560/agex` then `claude plugin install agex@agex-marketplace`. If everything is available, say so in one line.
