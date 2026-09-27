---
description: "<What this command does, in one line, starting with a verb>"
argument-hint: "<what the user types after the command name>"
allowed-tools: Bash(git status *) Bash(git log *) Bash(git ls-files *) Bash(grep *) Bash(head *) Bash(echo *)
---

<!--
AGEX CUSTOM COMMAND TEMPLATE

How to use this file
1. Copy it to one of these locations. The file name becomes the command name, so
   review-migrations.md is invoked as /review-migrations.
     .claude/commands/<command-name>.md    this project only; commit it to share with your team
     ~/.claude/commands/<command-name>.md  every project on your machine
   Do not start the name with "agex": those names belong to AGEX's own commands.
2. Replace every <angle-bracket> fill-in and delete the context sections you do not need.
3. Delete these guidance comments when you are done. They are sent to the model on every run.
4. Start a new Claude Code session, type /, and confirm the command is listed.

Frontmatter
- description: one line in double quotes, shown in the slash-command menu.
- argument-hint: shown after the command name while the user types. Delete the line if the
  command takes no arguments.
- allowed-tools: space-separated tool patterns that are pre-approved while the command runs.
  Every program used by a shell injection below MUST be listed, one pattern per program, and
  you should list only the ones the command actually uses. The complete set of allowed patterns:
    Bash(git status *)  Bash(git ls-files *)  Bash(git diff *)  Bash(git log *)
    Bash(grep *)  Bash(head *)  Bash(tail *)  Bash(ls *)  Bash(echo *)  Bash(wc *)
- There is no model field: like AGEX's commands, the command runs on the session's model.

Arguments
The line under "## Request" is replaced with whatever the user types after the command name.
The request can be empty, so keep the sentence that tells the model to ask and stop. If your
command works without arguments (for example, a review of the current diff), replace that
sentence with the default behavior instead.

Shell injections: read this before adding or changing one
A shell injection is a line that starts with an exclamation mark immediately followed by a
command in backticks, as in the Project Context section below. Claude Code runs every injection
BEFORE the model sees the prompt and pastes the output in its place. If any injection exits with
a non-zero status, or calls a program that allowed-tools and your permission rules do not allow,
Claude Code aborts the entire command and the user gets a shell command error instead of a
result. So every injection must follow all of these rules:
1. Strictly read-only. It runs without a confirmation prompt.
2. End in a guaranteed-success fallback: 2>/dev/null || echo "(what is missing)". A pipeline
   that ends in head always exits 0 and needs no echo; an empty section then means "no output".
3. Use only git status, git ls-files, git diff, git log, grep, head, tail, ls, echo, and wc, and
   list each program it uses in allowed-tools.
4. Never use find (its -delete and -exec options change files and run programs), cat, sh -c,
   xargs, redirects into files, or anything that prints secret files such as .env. List project
   files with git ls-files --cached --others --exclude-standard (it respects .gitignore and skips
   node_modules), and read the start of a file with head -N instead of cat.
5. Never use git diff HEAD~1: it fails in a repository that has only one commit. For the last
   commit use: git log -1 --stat -p 2>/dev/null | head -200 || echo "(no commits yet)"
6. Start the injection at the beginning of a line (or after whitespace), or it is not run.
7. Never put the argument placeholder inside an injection. What the user types is text for the
   model, never input for the shell.
8. Cap output with head -N. Everything an injection prints is sent to the model on every run.
If a user's settings deny one of these programs (for example a deny rule for Bash(git log *)),
the command aborts for that user; deny rules always win over allowed-tools.

Choosing the agent
Name the agent the command should use and apply the AGEX naming rule: the scoped name
agex:<name> exists only in plugin installs, so dispatch it when the Agent tool lists it and use
the bare name otherwise. Agents you wrote yourself are never scoped; always use their bare name.
-->

# <Command Title>

## Request

$ARGUMENTS

If the request above is empty, ask the user what they want this command to do and stop. Do not guess a task.

## Project Context

The sections below were collected by read-only shell commands before this prompt was sent. A message in parentheses, or an empty section, means that source was not available: treat it as missing context, not as an error.

### CLAUDE.md (first 60 lines)

!`head -60 CLAUDE.md 2>/dev/null || echo "(no CLAUDE.md in the project root)"`

### Git status

!`git status --short --branch 2>/dev/null || echo "(not a git repository)"`

### Recent commits

!`git log --oneline -10 2>/dev/null || echo "(no commits yet, or not a git repository)"`

### Project files (first 150, respecting .gitignore)

!`git ls-files --cached --others --exclude-standard 2>/dev/null | head -150`

### Test files (first 40)

!`git ls-files --cached --others --exclude-standard 2>/dev/null | grep -F -e ".test." -e ".spec." -e "tests/" | head -40`

## Instructions

1. Read the request and the project context above. Ask one clarifying question only if the request cannot be carried out safely as written.
2. Use the AGEX `<agent-name>` agent for this work. Dispatch `agex:<agent-name>` if the Agent tool lists it (plugin install); otherwise dispatch the bare name `<agent-name>`. If the Agent tool lists neither, or this session has no Agent tool, tell the user the agent is not available in this session, then do the work yourself under the same procedure and constraints and return the same artifact with the Producer `<agent-name> (inline fallback)`. Never substitute a different agent, and never hand the work to another session or to a background, remote, or scheduled task.
3. Give the agent a self-contained delegation packet, because it cannot see this conversation:
   - **Objective:** <the single outcome this command exists to produce>
   - **Inputs:** the request, plus the parts of the project context above that matter
   - **Scope:** <the files or directories the agent may read or change>
   - **Constraints:** <conventions, commands to run, and actions that are forbidden>
   - **Expected Artifact:** a <ArtifactType> with Status <STATUS_A> | <STATUS_B> | <STATUS_C>
   - **Cycle:** n/a
4. <Command-specific step, for example: if the artifact lists findings, offer to route them to the coder, and wait for the user's answer before changing any file>.
5. Check that the returned artifact starts with `<!-- agex:artifact type=<ArtifactType> version=1 -->` and contains every section of its format. If it is missing, empty, or malformed, retry once with narrower instructions; if it fails again, tell the user what happened and stop.
6. Present the <ArtifactType> to the user unchanged, then add a two-to-three sentence summary of its status and the next step you recommend.
