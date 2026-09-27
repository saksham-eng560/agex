---
description: "Deploy AGEX tester agent to write and run tests"
argument-hint: "[what to test, e.g. a module or feature]"
allowed-tools: Bash(head *) Bash(echo *) Bash(git ls-files *) Bash(grep *) Bash(git status *)
---

# AGEX Test

Write and run tests with the AGEX tester and present its TestReport. The tester only creates or edits test files; this command never changes application code.

## What to Test

$ARGUMENTS

## Project Context

### Project instructions (CLAUDE.md, first 30 lines)

!`head -30 CLAUDE.md 2>/dev/null || echo "(no CLAUDE.md in project root)"`

### Existing test files (first 30)

```text
!`git ls-files --cached --others --exclude-standard 2>/dev/null | grep -E '(\.(test|spec)\.[A-Za-z]+$|(^|/)(tests?|__tests__)/|_test\.(go|py)$|(^|/)test_[^/]+\.py$)' | head -30`
```

### Test scripts (package.json)

```text
!`grep -A15 '"scripts"' package.json 2>/dev/null || echo "(no package.json scripts)"`
```

### Uncommitted changes (first 30)

```text
!`git status --short 2>/dev/null | head -30`
```

An empty Existing test files block means no test files were found or this is not a git repository. An empty Uncommitted changes block means a clean working tree or not a git repository. The tester detects other runners itself (pyproject.toml, go.mod, Cargo.toml, Makefile).

## Instructions

1. Choose the target and state it in one line:
   - If the What to Test section above is filled in, test that.
   - If it is empty, test recently changed code: the modified and untracked source files in Uncommitted changes (ignore documentation-only changes); if the working tree is clean, the files changed in the most recent commit (the tester can list them with `git log -1 --stat`).
   - If nothing was given and there is no recent change to test (clean tree with no commits, or not a git repository), ask the user what to test and stop.
2. Dispatch the tester with the Agent tool: use `agex:tester` if the Agent tool lists it (plugin install); otherwise use `tester`. If neither is listed, or this session has no Agent tool, follow If the Tester Is Unavailable below instead of dispatching.
3. The tester sees only your prompt, so send a self-contained delegation packet:
   - **Objective**: add or update tests for the target and run them.
   - **Inputs**: the target, the test files and test scripts listed above, and the CLAUDE.md excerpt.
   - **Scope**: create or edit test files only (for example `*.test.*`, `*.spec.*`, files under `tests/` or `__tests__/`, `*_test.go`, `test_*.py`); never application code, configuration, or manifests.
   - **Constraints**: use the project's existing test framework and conventions; do not install dependencies or change manifests (if a required tool is missing, report Status ERROR with the command the user would run). Cover the main behavior plus edge cases: empty and boundary inputs, invalid input, error paths, and regressions for the recent change. Actually run the suites; every number in the report must come from command output. Measure coverage only when the project already has a coverage tool configured (for example `pytest --cov`, `go test -cover`, or the test script's coverage flag); otherwise write "not measured" and name the untested areas.
   - **Expected Artifact**: TestReport, Status PASS, FAIL, or ERROR.
   - **Cycle**: n/a.
4. Validate the returned artifact. It must start with `<!-- agex:artifact type=TestReport version=1 -->`, then the `## TestReport: <short title>` line and the `**Producer:** tester · **Status:** ...` line, followed by these sections in order:
   - `### Test Suites Executed` (exact commands)
   - `### Pass/Fail Summary`, a table with the columns `Suite | Passed | Failed | Skipped`
   - `### Tests Added or Updated`
   - `### Edge Cases Covered`
   - `### Failure Traces` (per failure: test id, expected, actual, trace excerpt, suspected location `path:line`)
   - `### Coverage` (a measurement, or "not measured")
   - `### Recommendation for Coder`

   A report with numbers but no executed commands is malformed. If the artifact is missing, empty, or malformed, re-dispatch the tester once with simpler, narrower instructions that name the gaps; if the second attempt also fails, show what you received and list the gaps.
5. Present the TestReport in full, exactly as returned, then a short summary: the Status, pass/fail totals, coverage (or "not measured"), and whether failures point to the tests or to application code.
6. If the tests reveal bugs in application code, do not fix them here and do not dispatch the coder or debugger. Offer `/agex` (`/agex:agex` in a plugin install) with the TestReport's Failure Traces as input; it routes the fix to the debugger or coder and re-runs the tests under AGEX's circuit breakers (at most 3 coder-tester cycles).
7. If the Status is ERROR, report the environment problem (missing dependency, broken configuration) with the tester's suggested fix, and do not install anything without the user's approval.

## If the Tester Is Unavailable

Follow this section only when neither `agex:tester` nor `tester` is available as an Agent type, or this session has no Agent tool.

1. Say so in one line, suggest `/agex-status` to diagnose it, and give the install commands: `curl -fsSL https://raw.githubusercontent.com/saksham-eng560/agex/main/install.sh | bash` (Windows: `irm https://raw.githubusercontent.com/saksham-eng560/agex/main/install.ps1 | iex`), or as a plugin, `claude plugin marketplace add saksham-eng560/agex` then `claude plugin install agex@agex-marketplace`.
2. Do the tester's job yourself, in this conversation, as the delegation packet in step 3 describes it, under the tester's constraints: create or edit test files only, never application code, configuration, manifests, or lockfiles; install nothing; never weaken assertions, skip tests, or delete failing tests; actually run the suites and copy every number from command output; report application bugs as Failure Traces instead of fixing them.
3. Produce the same TestReport, with the envelope and sections required in step 4, and set its Producer field to `tester (inline fallback)`. Check it against step 4 yourself, then present it and follow up as in steps 5 to 7.
4. NEVER substitute a different agent (such as a built-in general-purpose, Explore, or Plan agent, or another plugin's agent), and NEVER hand the work off by messaging other Claude sessions, starting background or remote tasks, scheduling wakeups or cron jobs, or launching Claude from a shell. The fallback always runs inline, in this conversation.
