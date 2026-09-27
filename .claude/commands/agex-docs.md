---
description: "Deploy AGEX documenter agent to write or update docs"
argument-hint: "<documentation task>"
allowed-tools: Bash(git ls-files *) Bash(grep *) Bash(head *)
---

# AGEX Docs

Write or update documentation with the AGEX documenter and present its DocUpdate. Existing documentation is preserved unless the user explicitly asks to replace it.

## Documentation Task

$ARGUMENTS

## Project Inventory

### Existing documentation files (first 30)

```text
!`git ls-files --cached --others --exclude-standard 2>/dev/null | grep -E '\.(md|mdx|rst)$' | head -30`
```

### Source files (first 40)

```text
!`git ls-files --cached --others --exclude-standard 2>/dev/null | grep -E '\.(ts|tsx|js|jsx|mjs|cjs|py|go|rs|java|kt|rb|php|cs)$' | head -40`
```

An empty block means no files of that kind were found or this is not a git repository; the documenter then inventories files with Glob. Both lists are truncated.

## Instructions

1. Choose the mode and state it in one line:
   - **Write mode**: the Documentation Task section above is filled in. The documenter carries out that task.
   - **Audit mode**: the Documentation Task section is empty. The documenter audits the documentation for gaps and proposes updates, but writes nothing.
2. Dispatch the documenter with the Agent tool: use `agex:documenter` if the Agent tool lists it (plugin install); otherwise use `documenter`. If neither is listed, or this session has no Agent tool, follow If the Documenter Is Unavailable below instead of dispatching.
3. The documenter sees only your prompt, so send a self-contained delegation packet:
   - **Objective**: write mode: the documentation task, verbatim. Audit mode: find documentation gaps (missing README sections such as installation, usage, and configuration; undocumented public functions, classes, or endpoints; examples that no longer match the code; missing changelog entries) and propose specific updates, ranked by impact, without writing any file.
   - **Inputs**: the task text (if any), the inventories above, and a pointer to CLAUDE.md for project conventions.
   - **Scope**: write mode: documentation files (Markdown, MDX, reStructuredText) and doc comments (JSDoc, TSDoc, docstrings) only; never change executable code or behavior. Audit mode: read-only.
   - **Constraints**: preserve existing content unless the user explicitly asked to replace it (say so in the packet when they did): extend and correct rather than rewrite, and keep the existing structure, headings, anchors, and tone. Write clear, concise, example-rich docs; every example must match the current code, so verify signatures, options, and commands against the source and never invent them. Follow the project's existing documentation style, and make sure every relative link resolves.
   - **Expected Artifact**: DocUpdate, Status COMPLETE or PARTIAL.
   - **Cycle**: n/a.
4. Validate the returned artifact. It must start with `<!-- agex:artifact type=DocUpdate version=1 -->`, then the `## DocUpdate: <short title>` line and the `**Producer:** documenter · **Status:** ... · **Confidence:** ...` line, followed by these sections in order:
   - `### Files Created or Updated`
   - `### Summary of Changes`
   - `### Examples Added`
   - `### Preserved Content`
   - `### Follow-ups`

   In write mode, confirm with Read that each listed file exists and contains the described change. In audit mode, Files Created or Updated must say "None (audit mode)", Summary of Changes must describe the proposed changes (marked as proposed), and Follow-ups must list them by priority; if the documenter wrote any file anyway, tell the user immediately. If the artifact is missing, empty, or malformed, re-dispatch once with simpler, narrower instructions that name the gaps; if the second attempt also fails, show what you received and list the gaps.
5. Present the DocUpdate in full, exactly as returned, then a short summary: the files touched (write mode) or the top gaps (audit mode).
6. In audit mode, ask the user which proposals to apply. When they choose, dispatch the documenter again in write mode for exactly those items.
7. Do not edit documentation yourself (except under If the Documenter Is Unavailable below); every docs change goes through the documenter. If the work reveals a code problem (for example, documented behavior that the code does not implement), report it and suggest `/agex` (`/agex:agex` in a plugin install) rather than changing code here.

## If the Documenter Is Unavailable

Follow this section only when neither `agex:documenter` nor `documenter` is available as an Agent type, or this session has no Agent tool.

1. Say so in one line, suggest `/agex-status` to diagnose it, and give the install commands: `curl -fsSL https://raw.githubusercontent.com/saksham-eng560/agex/main/install.sh | bash` (Windows: `irm https://raw.githubusercontent.com/saksham-eng560/agex/main/install.ps1 | iex`), or as a plugin, `claude plugin marketplace add saksham-eng560/agex` then `claude plugin install agex@agex-marketplace`.
2. Do the documenter's job yourself, in this conversation, as the delegation packet in step 3 describes it, under the documenter's constraints. In write mode, change only documentation files (Markdown, MDX, reStructuredText) and doc comments or docstrings; in source files, signatures, imports, and statements stay byte-for-byte identical. Preserve existing content, verify every symbol, command, and option against the source before documenting it, and never invent version numbers or release dates. In audit mode, write nothing.
3. Produce the same DocUpdate, with the envelope and sections required in step 4, and set its Producer field to `documenter (inline fallback)`. Check it against step 4 yourself, then present it as in steps 5 and 6. Wherever those steps say to dispatch the documenter again, do that work inline instead.
4. NEVER substitute a different agent (such as a built-in general-purpose, Explore, or Plan agent, or another plugin's agent), and NEVER hand the work off by messaging other Claude sessions, starting background or remote tasks, scheduling wakeups or cron jobs, or launching Claude from a shell. The fallback always runs inline, in this conversation.
