---
description: "Deploy AGEX reviewer agent on recent changes"
argument-hint: "[optional: file, directory, or git ref to focus on]"
allowed-tools: Bash(git status *) Bash(git diff *) Bash(git log *) Bash(head *) Bash(echo *)
---

# AGEX Review

Review recent changes with the AGEX reviewer (plus the security agent when the change is security-sensitive) and present the ReviewVerdict. This command is read-only.

## Review Focus

$ARGUMENTS

## Repository State

### Working tree (git status --short, first 30 lines)

```text
!`git status --short 2>/dev/null | head -30`
```

### Staged changes: summary

```text
!`git diff --staged --stat 2>/dev/null | head -40`
```

### Staged changes: diff (first 400 lines)

```diff
!`git diff --staged 2>/dev/null | head -400`
```

### Unstaged changes: summary

```text
!`git diff --stat 2>/dev/null | head -40`
```

### Unstaged changes: diff (first 400 lines)

```diff
!`git diff 2>/dev/null | head -400`
```

### Recent commits

```text
!`git log --oneline -5 2>/dev/null || echo "(no commits yet, or not a git repository)"`
```

### Last commit (first 200 lines)

```diff
!`git log -1 --stat -p 2>/dev/null | head -200 || echo "(no commits yet)"`
```

An empty block means there is nothing in that category; if every block is empty and Recent commits reports no commits, this is either a repository without commits or not a git repository at all.

## Instructions

1. Choose the review target; the first match wins. State it in one line.
   1. The Review Focus above, if given: a file, a directory, or a git ref. For a path, review its current contents plus any staged or unstaged changes to it. For a ref (commit, branch, or range), the reviewer inspects it with read-only git commands such as `git show <ref>` or `git diff <ref>...HEAD`.
   2. Staged changes.
   3. Unstaged changes to tracked files, plus untracked files (marked `??` in the working tree listing). Untracked files never appear in a diff, so the reviewer reads them directly.
   4. The last commit.

   If no focus was given and there is nothing staged, unstaged, untracked, or committed, tell the user there is nothing to review, suggest passing a file or directory, and stop.
2. The diffs above are truncated at 400 lines (the last commit at 200) and serve only as orientation. The reviewer must read the full changed files, and the callers of changed functions, rather than rely on the excerpt.
3. Dispatch the reviewer with the Agent tool: use `agex:reviewer` if the Agent tool lists it (plugin install); otherwise use `reviewer`. If the target touches authentication or authorization, input handling (parsing, validation, SQL, HTML rendering, file paths, shell commands), cryptography, or secrets, also dispatch the security agent (`agex:security` if listed, otherwise `security`) in the same message, so both run in parallel on the same target. If the reviewer, or the security agent when it is needed, is listed under neither name (or this session has no Agent tool), follow If an Agent Is Unavailable below for that agent and dispatch the other as usual.
4. Each agent sees only your prompt, so send self-contained delegation packets:
   - **Objective**: reviewer: an adversarial review of the target; assume the implementation has hidden bugs and hunt for them. Security: a security audit scoped to the same target.
   - **Inputs**: the chosen target, the list of changed and untracked files from the summaries above, and the Review Focus text verbatim if given.
   - **Scope**: read-only; the changed files, their callers, and their tests. Read-only git commands (`git diff`, `git show`, `git log`) are allowed.
   - **Constraints**: check logic errors, race conditions, unhandled errors, security (OWASP Top 10), performance, missing edge cases, missing or weak tests, and project conventions from CLAUDE.md. Never modify files. Never reproduce secret values.
   - **Expected Artifact**: reviewer: ReviewVerdict, Status APPROVED, CHANGES_REQUESTED, or BLOCKED. Security: SecurityAuditReport, Status PASS, FINDINGS, or CRITICAL_FINDINGS.
   - **Cycle**: n/a.
5. Validate the ReviewVerdict. It must start with `<!-- agex:artifact type=ReviewVerdict version=1 -->`, then the `## ReviewVerdict: <short title>` line and the `**Producer:** reviewer · **Status:** ... · **Confidence:** ...` line, followed by these sections in order:
   - `### Summary`
   - `### Issues`, a table with the columns `ID | Severity | Category | Location | Problem | Remediation`; Severity is CRITICAL, HIGH, MEDIUM, or LOW; Category is one of logic, security, performance, concurrency, error-handling, edge-case, style, tests
   - `### Checks Performed` (checklist)
   - `### What Is Good` (at most 3 bullets)

   Apply the decision rule: any CRITICAL means BLOCKED; otherwise any HIGH or MEDIUM means CHANGES_REQUESTED; otherwise APPROVED, with LOW items listed as non-blocking. If the stated Status contradicts the Issues table, report both and use the rule's result. If an artifact is missing, empty, or malformed, re-dispatch that agent once with simpler, narrower instructions that name the gaps; if the second attempt also fails, show what you received and list the gaps.
6. Present the results:
   - The ReviewVerdict in full, exactly as returned: its STATUS, the issues table with severities, and the remediation for each issue.
   - If the security agent ran, its SecurityAuditReport in full.
   - A bottom line: the overall result is the stricter of the two (any CRITICAL anywhere means BLOCKED; otherwise any HIGH or MEDIUM means CHANGES_REQUESTED; otherwise APPROVED), with a count of issues per severity.
7. Stay read-only: do not fix, edit, stage, or commit anything, not even trivial issues. If the user asks for fixes afterwards, suggest `/agex` (`/agex:agex` in a plugin install) with this verdict as input; it routes the fixes to the coder and re-reviews them under AGEX's circuit breakers (at most 3 coder-reviewer cycles).
8. If a diff or file contains credentials, never repeat the value: show at most the first 4 characters followed by `****`, and report it as a finding.

## If an Agent Is Unavailable

Follow this section only for an agent that step 3 needs and that is available as an Agent type under neither `agex:<name>` nor `<name>`, or when this session has no Agent tool.

1. Say so in one line, naming the missing agent, suggest `/agex-status` to diagnose it, and give the install commands: `curl -fsSL https://raw.githubusercontent.com/saksham-eng560/agex/main/install.sh | bash` (Windows: `irm https://raw.githubusercontent.com/saksham-eng560/agex/main/install.ps1 | iex`), or as a plugin, `claude plugin marketplace add saksham-eng560/agex` then `claude plugin install agex@agex-marketplace`.
2. Do that agent's job yourself, in this conversation, as its delegation packet in step 4 describes it, under its constraints: read-only; Bash only for inspection (`git diff`, `git show`, `git log`, `git status`, `git blame`, and existing lint, typecheck, or test commands that do not write or fix files); no edits, fixes, installs, redirects to files, or git state changes; never reproduce a secret value beyond its first 4 characters followed by `****`. Confirm every issue by tracing the code path and give each a precise `path:line` and a concrete remediation.
3. Produce the same artifact with the same envelope and sections, and set its Producer field to `reviewer (inline fallback)` or `security (inline fallback)`. A ReviewVerdict must pass the checks in step 5. A SecurityAuditReport has these sections in order: `### Scope`, `### Risk Matrix` (columns `ID | Severity | Category | Location | Finding | Evidence (redacted) | Remediation`, each Category an OWASP Top 10 2021 ID or a CWE ID), `### Secrets Scan`, `### Dependency Audit`, `### Configuration Review`, `### Summary`, with Status PASS, FINDINGS, or CRITICAL_FINDINGS. Then present the results as in steps 6 to 8.
4. NEVER substitute a different agent (such as a built-in general-purpose, Explore, or Plan agent, or another plugin's agent), and NEVER hand the work off by messaging other Claude sessions, starting background or remote tasks, scheduling wakeups or cron jobs, or launching Claude from a shell. The fallback always runs inline, in this conversation.
