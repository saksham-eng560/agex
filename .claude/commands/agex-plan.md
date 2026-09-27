---
description: "Create an AGEX execution plan without running it"
argument-hint: "<task description>"
allowed-tools: Bash(head *) Bash(echo *) Bash(git ls-files *)
---

# AGEX Plan (No Execution)

Produce an AGEX execution plan for the task below with the AGEX planner. This is plan-only mode: nothing gets executed and no file changes.

## Task

$ARGUMENTS

## Project Context

### Project instructions (CLAUDE.md, first 50 lines)

!`head -50 CLAUDE.md 2>/dev/null || echo "(no CLAUDE.md in project root)"`

### Project files (tracked and untracked, .gitignore respected, first 60)

```text
!`git ls-files --cached --others --exclude-standard 2>/dev/null | head -60`
```

An empty Project files block means this directory is not a git repository or has no files yet; the planner then explores with Glob and Read. The list is truncated, so it is orientation, not inventory.

## Instructions

1. If the Task section above is empty, ask the user what to plan and stop.
2. Stay in plan-only mode for the whole command:
   - Do NOT execute any step of the plan, and do not dispatch any agent other than the planner.
   - Do NOT create, modify, or delete files, and do not run commands that change state (installs, builds that write output, git operations beyond read-only inspection).
   - Reading files to understand the project is fine.
3. Dispatch the planner with the Agent tool: use `agex:planner` if the Agent tool lists it (plugin install); otherwise use `planner`. If neither is listed, or this session has no Agent tool, follow If the Planner Is Unavailable below instead of dispatching.
4. The planner sees only your prompt, so send a self-contained delegation packet:
   - **Objective**: a TaskPlan for the task.
   - **Inputs**: the task text verbatim, the CLAUDE.md excerpt, and the project file list above.
   - **Scope**: read-only inspection of the repository.
   - **Constraints**: assign every step to exactly one AGEX specialist (researcher, architect, coder, tester, reviewer, debugger, documenter, devops, refactor, security); follow the project conventions in CLAUDE.md; any remote or irreversible action (push, deploy, publish, tag) is a devops step that stops for human confirmation; keep the whole plan, expected feedback-loop cycles included, within AGEX's soft budget of 15 sub-agent dispatches, or flag the overrun under Risks & Mitigations.
   - **Expected Artifact**: TaskPlan, Status READY or NEEDS_INPUT.
   - **Cycle**: n/a.

   The plan must contain: numbered steps; the AGEX agent assigned to each step; the dependencies between steps; parallel groups and Execution Waves that make clear which steps run in parallel and which run sequentially; a complexity estimate (S/M/L) for every step; a Done When criterion for every step; risks with mitigations; and open questions.
5. Validate the returned artifact. It must start with `<!-- agex:artifact type=TaskPlan version=1 -->`, then the `## TaskPlan: <short title>` line and the `**Producer:** planner · **Status:** ... · **Confidence:** ...` line, followed by these sections in order:
   - `### Goal`
   - `### Assumptions`
   - `### Steps`, a table with the columns `# | Step | Agent | Depends On | Parallel Group | Complexity (S/M/L) | Done When`
   - `### Execution Waves` (Wave 1: steps ..., parallel or sequential)
   - `### Risks & Mitigations`
   - `### Open Questions`

   Also check that every Depends On entry names an existing step with no circular dependency, and that every Agent is one of the ten specialists listed above. If the artifact is missing, empty, or malformed, re-dispatch the planner once with simpler, narrower instructions that name the gaps. If the second attempt also fails, show what you received and list the gaps; do not silently rewrite the plan yourself.
6. Present the result:
   - The TaskPlan in full, exactly as returned.
   - A short summary: the overall AGEX complexity class (SIMPLE: one concern and 1-2 files; MEDIUM: 2-5 files in one component with a clear approach; COMPLEX: multiple components, a new data model or API, unclear requirements, more than 5 files, or cross-cutting risk), the number of steps and waves, the estimated number of sub-agent dispatches, and the highest risk.
   - If the Status is NEEDS_INPUT, list the Open Questions and ask the user to answer them. Once they answer, re-dispatch the planner with the answers, still in plan-only mode.
7. Finish by stating that nothing has been executed or changed. To run the plan, the user can invoke `/agex` with the same task (`/agex:agex` in a plugin install); this plan stays in the conversation as input for that run.

## If the Planner Is Unavailable

Follow this section only when neither `agex:planner` nor `planner` is available as an Agent type, or this session has no Agent tool.

1. Say so in one line, suggest `/agex-status` to diagnose it, and give the install commands: `curl -fsSL https://raw.githubusercontent.com/saksham-eng560/agex/main/install.sh | bash` (Windows: `irm https://raw.githubusercontent.com/saksham-eng560/agex/main/install.ps1 | iex`), or as a plugin, `claude plugin marketplace add saksham-eng560/agex` then `claude plugin install agex@agex-marketplace`.
2. Do the planner's job yourself, in this conversation, as the delegation packet in step 4 describes it, under the planner's constraints: read-only inspection with Read, Grep, and Glob; no file changes and no state-changing commands; every step assigned to exactly one of the ten specialists; nothing executed.
3. Produce the same TaskPlan, with the envelope and sections required in step 5, and set its Producer field to `planner (inline fallback)`. Check it against step 5 yourself, then present it as in steps 6 and 7. Wherever those steps say to dispatch or re-dispatch the planner, do that work inline instead.
4. NEVER substitute a different agent (such as a built-in general-purpose, Explore, or Plan agent, or another plugin's agent), and NEVER hand the work off by messaging other Claude sessions, starting background or remote tasks, scheduling wakeups or cron jobs, or launching Claude from a shell. The fallback always runs inline, in this conversation.
