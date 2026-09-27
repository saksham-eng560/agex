---
description: "Deploy AGEX security agent for vulnerability scanning"
argument-hint: "[optional scope: path or concern]"
allowed-tools: Bash(git ls-files *) Bash(grep *) Bash(head *) Bash(ls *) Bash(echo *)
---

# AGEX Security Audit

Audit the project with the AGEX security agent and present its SecurityAuditReport. This command is read-only, and secret values are never displayed.

## Audit Scope

$ARGUMENTS

## Project Inventory

### Source files (tracked and untracked, .gitignore respected, first 40)

```text
!`git ls-files --cached --others --exclude-standard 2>/dev/null | grep -E '\.(ts|tsx|js|jsx|mjs|cjs|py|go|rs|java|kt|rb|php|cs)$' | head -40`
```

### Dependency manifests present

```text
!`ls -1 package.json package-lock.json pnpm-lock.yaml yarn.lock requirements.txt pyproject.toml poetry.lock go.mod Cargo.toml Gemfile composer.json 2>/dev/null || echo "(end of list: any manifest not shown above is absent)"`
```

### package.json (first 40 lines)

```text
!`head -40 package.json 2>/dev/null || echo "(no package.json)"`
```

### Environment files in the project root (names only)

```text
!`ls -1a 2>/dev/null | grep -E '^\.env' || echo "(no .env files in project root)"`
```

### Environment files tracked by git

```text
!`git ls-files 2>/dev/null | grep -E '(^|/)\.env($|\.)' || echo "(no .env files tracked by git)"`
```

An empty Source files block means no matching source files were found or this is not a git repository; the security agent then inventories files with Glob. The manifest block names the manifests that exist; the end-of-list note appears whenever at least one of them is absent.

## Instructions

1. State the scope in one line. If the Audit Scope section above names a path or concern, focus the audit there, but always include the environment-file checks. If it is empty, audit the whole project.
2. Stay read-only for the whole command: do not modify files, do not fix findings, and do not install audit tools.
3. Dispatch the security agent with the Agent tool: use `agex:security` if the Agent tool lists it (plugin install); otherwise use `security`. If neither is listed, or this session has no Agent tool, follow If the Security Agent Is Unavailable below instead of dispatching.
4. The security agent sees only your prompt, so send a self-contained delegation packet:
   - **Objective**: a SecurityAuditReport for the scope.
   - **Inputs**: the scope, and the inventory above (source files, manifests, package.json excerpt, environment file names).
   - **Scope**: read-only inspection of the project.
   - **Constraints**: check hardcoded secrets (API keys, tokens, private keys, passwords, connection strings) in source, configuration, and tracked environment files; injection (SQL, command, path traversal, template); XSS; CSRF; SSRF; insecure deserialization; broken authentication and authorization; weak cryptography; vulnerable dependencies in manifests and lockfiles; and permission and configuration mistakes (CORS, debug modes, security headers, CI secrets). Classify each finding with an OWASP Top 10 2021 ID (for example `A03:2021-Injection`) or a CWE ID. Bash is for read-only inspection only; any audit command must leave files and lockfiles untouched (for example `npm audit` is allowed, `npm audit fix` is not). NEVER reproduce a secret: evidence shows at most the first 4 characters followed by `****`. Any `.env`-style file tracked by git is at least HIGH, except templates such as `.env.example`, `.env.sample`, or `.env.template` that contain no real values.
   - **Expected Artifact**: SecurityAuditReport, Status PASS, FINDINGS, or CRITICAL_FINDINGS.
   - **Cycle**: n/a.
5. Validate the returned artifact. It must start with `<!-- agex:artifact type=SecurityAuditReport version=1 -->`, then the `## SecurityAuditReport: <short title>` line and the `**Producer:** security · **Status:** ... · **Confidence:** ...` line, followed by these sections in order:
   - `### Scope`
   - `### Risk Matrix`, a table with the columns `ID | Severity | Category | Location | Finding | Evidence (redacted) | Remediation`; Severity is CRITICAL, HIGH, MEDIUM, or LOW
   - `### Secrets Scan`
   - `### Dependency Audit` (the exact audit command and result, or a statement that the review was manual)
   - `### Configuration Review`
   - `### Summary` (counts per severity and the overall risk)

   Check that the Status matches the Risk Matrix: CRITICAL_FINDINGS when any finding is CRITICAL, FINDINGS when other findings exist, PASS only when the matrix is empty. If the Environment files tracked by git block lists a non-template file and the report omits it or rates it below HIGH, point that out and treat it as HIGH in your bottom line. If the artifact is missing, empty, or malformed, re-dispatch once with simpler, narrower instructions that name the gaps; if the second attempt also fails, show what you received and list the gaps.
6. Before presenting, scan every Evidence cell and the Secrets Scan section: if anything looks like an unredacted secret value, redact it to the first 4 characters followed by `****`. Never print secret values, and never print the contents of environment files.
7. Present the SecurityAuditReport in full (redacted), then a bottom line: the overall risk, the count of findings per severity, and the top three remediation priorities.
8. Suggest next steps without taking them: `/agex` (`/agex:agex` in a plugin install) to fix findings, which routes security → coder → reviewer → security re-check. For any leaked credential, tell the user to rotate it first: deleting it from the latest commit does not remove it from git history.

## If the Security Agent Is Unavailable

Follow this section only when neither `agex:security` nor `security` is available as an Agent type, or this session has no Agent tool.

1. Say so in one line, suggest `/agex-status` to diagnose it, and give the install commands: `curl -fsSL https://raw.githubusercontent.com/saksham-eng560/agex/main/install.sh | bash` (Windows: `irm https://raw.githubusercontent.com/saksham-eng560/agex/main/install.ps1 | iex`), or as a plugin, `claude plugin marketplace add saksham-eng560/agex` then `claude plugin install agex@agex-marketplace`.
2. Do the security agent's job yourself, in this conversation, as the delegation packet in step 4 describes it, under its constraints: read-only; Bash only for inspection (no redirects to files, no installs, no `npm audit fix`, no git state changes); only audit tools that are already installed; search for secrets in files-with-matches mode first and read environment files by key name only; never print a secret value beyond its first 4 characters followed by `****`; never test discovered credentials or send traffic to live systems.
3. Produce the same SecurityAuditReport, with the envelope and sections required in step 5, and set its Producer field to `security (inline fallback)`. Check it against step 5 yourself, then redact and present it as in steps 6 to 8.
4. NEVER substitute a different agent (such as a built-in general-purpose, Explore, or Plan agent, or another plugin's agent), and NEVER hand the work off by messaging other Claude sessions, starting background or remote tasks, scheduling wakeups or cron jobs, or launching Claude from a shell. The fallback always runs inline, in this conversation.
