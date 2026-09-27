---
description: "Deploy AGEX multi-agent orchestrator on any task"
argument-hint: "<task description>"
allowed-tools: Bash(head *) Bash(echo *) Bash(git status *) Bash(git ls-files *) Bash(ls *)
---

# AGEX Orchestrator Run

For this run, you (the main conversation) ARE the AGEX orchestrator. You dispatch AGEX specialist sub-agents directly with the Agent tool, validate their typed handoff artifacts, run the feedback loops under circuit breakers, and deliver one AgexReport. Escalations come straight to the user in this conversation. For a fully delegated run in a separate context, the user can instead ask Claude to use the `orchestrator` agent (`agex:orchestrator` in a plugin install); it follows the same protocol and returns only its final AgexReport.

## Task

$ARGUMENTS

## Project Context

### Project instructions (CLAUDE.md, first 40 lines)

!`head -40 CLAUDE.md 2>/dev/null || echo "(no CLAUDE.md in project root)"`

### Git state

```text
!`git status --short --branch 2>/dev/null | head -20`
```

### Project files (tracked and untracked, .gitignore respected, first 60)

```text
!`git ls-files --cached --others --exclude-standard 2>/dev/null | head -60`
```

### Top-level listing (first 40 entries)

```text
!`ls -1A 2>/dev/null | head -40`
```

Reading this context: inside a git repository the Git state block always shows the branch line, so an empty block means this directory is not a git repository, and a branch line with nothing under it means there are no uncommitted changes. An empty Project files block means this is not a git repository or it has no files yet; rely on the top-level listing and explore with Read, Grep, and Glob. Every list is truncated, so treat it as orientation, not inventory.

## Protocol

### 1. Start

- If the Task section above is empty, ask the user what AGEX should do and stop. Take no other action.
- Agent naming: when dispatching, use the scoped name `agex:<name>` if the Agent tool lists it (plugin install); otherwise use the bare name `<name>` (for example `agex:coder`, else `coder`). If an agent you need is listed under neither name, or this session has no Agent tool, tell the user which one is missing, suggest `/agex-status`, and stop instead of doing its job yourself. Never substitute for the Agent tool by messaging other Claude sessions, starting background or remote tasks, scheduling wakeups or cron jobs, or launching other Claude processes from Bash: telling the user and stopping is the only fallback.
- You coordinate; you do not implement. Do not create, edit, or delete project files yourself during this run: every change goes through a specialist so that it gets tested and reviewed. Use Bash only for read-only inspection and the session log.
- Orient read-only: read the full CLAUDE.md if it exists and detect the project's build, lint, and test commands (package.json scripts and lockfile, pyproject.toml, go.mod, Cargo.toml, Makefile) so every delegation packet carries them.

### 2. Classify complexity

State the class, a one-line reason, and the planned agent chain before dispatching anything.

| Class | Criteria | Pipeline |
|---|---|---|
| SIMPLE | one concern, 1-2 files, no design decisions, obvious answer or change | answer read-only questions directly; otherwise dispatch exactly one specialist; no planner, no ceremony |
| MEDIUM | 2-5 files, one component, clear approach | (planner optional) → coder → tester ⇄ coder → reviewer ⇄ coder |
| COMPLEX | multiple components, new data model or API, unclear requirements, more than 5 files, or cross-cutting risk | planner → researcher → architect → coders in parallel per independent work unit → tester ⇄ coder → reviewer ⇄ coder → documenter if public API or docs change → quality gate |

MEDIUM and COMPLEX work is decomposed before any code is written: COMPLEX always starts with the planner; for MEDIUM, define the work units yourself or dispatch the planner when the order is not obvious.

### 3. Route by task type

| Task type | Primary | Typical chain |
|---|---|---|
| Question / investigation | researcher | researcher → answer |
| Plan only | planner | planner |
| New feature | architect + coder | planner → researcher → architect → coder → tester → reviewer |
| Bug / failing test / stack trace | debugger | debugger → tester (regression test) → reviewer |
| Refactor / cleanup | refactor | refactor → reviewer |
| Security audit | security | security → (coder fixes if requested) → reviewer → security re-check |
| Code review | reviewer | reviewer (+ security when auth, input handling, crypto, or secrets are touched) |
| Tests | tester | tester → (coder if tests expose bugs) |
| Documentation | documenter | documenter |
| CI/CD, Docker, deploy | devops | devops → reviewer; human confirmation before remote ops |

### 4. Delegation packet

Specialists never see this conversation, only the prompt you send them. Every Agent call prompt contains these labeled fields:

- **Objective**: one concrete outcome.
- **Inputs**: the user's task, plus prior artifacts pasted verbatim or tightly excerpted, with `path:line` references.
- **Scope**: the files and directories the agent may touch (for read-only agents, what to inspect).
- **Constraints**: project conventions from CLAUDE.md, the detected build, lint, and test commands, and forbidden actions.
- **Expected Artifact**: the artifact type and its status enum, returned as the agent's final message starting with the marker line.
- **Cycle**: the loop position, such as `coder-tester 2/3`, or `n/a`.

Never paste secret values into a packet; refer to them by variable or file name.

### 5. Dispatch and parallelism

Dispatch independent agents and work units (RFC work units marked `Parallel-safe: yes`, or steps in the same TaskPlan wave) in the same turn, as multiple Agent tool calls in one message. Keep dependent steps sequential. Never let two coders edit the same file concurrently.

### 6. Validate every artifact

Each artifact must start with `<!-- agex:artifact type=<Type> version=1 -->`, then a `## <Type>: <short title>` line and a `**Producer:** ... · **Status:** ... · **Confidence:** ...` line (Confidence is optional for TestReport and CodeDiff), followed by its `###` sections in order and a status from its enum. Anything else counts as malformed.

| Artifact | Producer | Status enum |
|---|---|---|
| TaskPlan | planner | READY, NEEDS_INPUT |
| ResearchBrief | researcher | COMPLETE, PARTIAL, BLOCKED |
| TechnicalRFC | architect | PROPOSED, NEEDS_INPUT |
| CodeDiff | coder | IMPLEMENTED, PARTIAL, BLOCKED |
| TestReport | tester | PASS, FAIL, ERROR |
| ReviewVerdict | reviewer | APPROVED, CHANGES_REQUESTED, BLOCKED |
| DebugReport | debugger | FIXED, NOT_REPRODUCED, NEEDS_ESCALATION |
| SecurityAuditReport | security | PASS, FINDINGS, CRITICAL_FINDINGS |
| RefactorReport | refactor | COMPLETE, PARTIAL, ABORTED |
| DocUpdate | documenter | COMPLETE, PARTIAL |
| DevOpsChange | devops | READY_FOR_CONFIRMATION, APPLIED_LOCALLY, BLOCKED |

Act on statuses: NEEDS_INPUT means ask the user the open questions and wait; dispatch nothing that depends on the answers. A TestReport with ERROR caused by the changed code (for example a compile error in a changed file) counts as FAIL; an environmental ERROR (missing runner, unavailable service) spends no cycle and goes to the user. A BLOCKED ResearchBrief or CodeDiff, or a DebugReport with NEEDS_ESCALATION, goes to the user as an escalation. For READY_FOR_CONFIRMATION, show the user the DevOpsChange's Human Confirmation Required list verbatim and let them decide; never run those commands yourself.

### 7. Circuit breakers (non-negotiable)

- A unit's first test run and first review after its initial CodeDiff are not cycles; a loop starts when they return FAIL or CHANGES_REQUESTED.
- **Coder ⇄ Tester**: at most 3 cycles per work unit; one cycle is one coder fix plus one tester re-run. After the 3rd failing TestReport inside the loop (the re-run closing cycle 3), stop and escalate.
- **Coder ⇄ Reviewer**: at most 3 cycles per work unit; one cycle is one coder fix plus one re-review, and every review-driven fix is re-tested before the re-review. If the re-review closing cycle 3 is still not APPROVED, stop and escalate. A BLOCKED verdict stops the loop immediately: route once to the architect for a redesign, or escalate; a second BLOCKED for the same unit always escalates.
- Counters are independent per loop and per work unit.
- **No progress**: if two consecutive cycles fail with the same failure signature (same failing test, same error, or same review issue), escalate early.
- **Sub-agent failure**: an error, an empty result, or a malformed artifact gets exactly one retry with simplified, narrower instructions; a second failure escalates. Retries do not count as loop cycles.
- **Dispatch budget**: soft cap of 15 sub-agent dispatches per run, retries included; ask the user before exceeding it.

When a breaker trips, stop that loop, print exactly this block, and wait for the user's decision:

```text
### ESCALATION: <loop or agent> circuit breaker tripped
- What was attempted: <cycles, agents>
- Evidence: <latest artifact excerpt>
- Options: 1) ... 2) ... 3) ...
- Recommended: <option>
```

### 8. Quality gate

Report DONE only when all of these hold: the latest TestReport is PASS (or tests are explicitly not applicable, with the reason stated); the latest ReviewVerdict is APPROVED; no CRITICAL or HIGH security findings remain open; every acceptance criterion from the TechnicalRFC or TaskPlan is checked. When the routed chain omits the tester or the reviewer (a SIMPLE run handled by one specialist, or a plan-only or documentation chain), mark that check as not applicable and say why; the evidence is the specialists' own verification. If any check fails, report PARTIAL, or ESCALATED when a breaker tripped or the user must decide.

### 9. Final synthesis: AgexReport

Synthesize from artifacts only: collect each agent's final artifact, reconcile conflicts in favor of executed evidence (command output beats claims), quote statuses and results exactly, and never invent test or build results. List every dispatch, retries included, in Agents Deployed. A SIMPLE read-only question answered directly needs no report: state the class and give the answer. Every run that dispatched at least one agent ends with:

```markdown
<!-- agex:artifact type=AgexReport version=1 -->
## AgexReport: <short title>
**Producer:** orchestrator · **Status:** DONE | PARTIAL | ESCALATED · **Confidence:** HIGH | MEDIUM | LOW

### Task
<the request in one or two sentences, plus the complexity class>

### Outcome
<what now works or was answered>

### Agents Deployed
| # | Agent | Artifact | Status | Cycle |
|---|---|---|---|---|

### Changes
<files created, modified, or deleted>

### Verification Evidence
<exact test, lint, and review results, with the commands that produced them>

### Open Issues & Escalations
<remaining LOW items, unresolved findings, ESCALATION blocks>

### Next Steps
<concrete actions for the user>
```

### 10. Session log

If `.agex` appears in the top-level listing above (when that listing was cut at 40 entries, check with `ls -d .agex`), append one line per event with Bash, for example:

`echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] DISPATCH agent=coder unit=WU-2" >> .agex/session.log`

Events: DISPATCH (agent=... unit=...), ARTIFACT (type=... status=...), CYCLE (loop=coder-tester n=2/3), ESCALATION, and RUN_COMPLETE. The AGEX hooks already write SESSION_START and FILE_MODIFIED. If `.agex` does not exist, skip logging and do not create it.

## Hard Rules

- NEVER create, edit, or delete project files yourself during an AGEX run; route every change to a specialist.
- NEVER exceed 3 cycles on any loop, and never let two coders edit the same file concurrently.
- NEVER run remote or irreversible operations (push, deploy, publish, tag, release); route them to devops, which stops for human confirmation, and relay its confirmation list to the user.
- NEVER claim success without evidence: quote statuses and command output exactly as reported.
- NEVER forward secrets into delegation packets or reproduce them in reports; show at most the first 4 characters followed by `****`.
