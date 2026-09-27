# Customizing AGEX

AGEX is plain Markdown. Every agent is one file in `.claude/agents/` and every slash command is one file in `.claude/commands/`, so you can add agents, route work to them, change models and tools, add commands, turn session logging on or off, and tune the circuit breakers without writing any code. This guide covers each of those, and ends with how to contribute an agent back to the project.

- [Where the AGEX files live](#where-the-agex-files-live)
- [Adding a custom agent](#adding-a-custom-agent)
- [Making the orchestrator route to your agent](#making-the-orchestrator-route-to-your-agent)
- [Changing models per agent](#changing-models-per-agent)
- [Restricting or granting tools](#restricting-or-granting-tools)
- [Adding a custom command](#adding-a-custom-command)
- [Enabling session-log hooks for symlink installs](#enabling-session-log-hooks-for-symlink-installs)
- [Disabling logging](#disabling-logging)
- [Tuning the circuit breakers](#tuning-the-circuit-breakers)
- [Contributing custom agents upstream](#contributing-custom-agents-upstream)

## Where the AGEX files live

Where you make a change depends on how you installed AGEX.

| Install method | AGEX agents and commands | Editing them |
|---|---|---|
| `install.sh` / `install.ps1` | The clone in `~/.agex/.claude/agents/` and `~/.agex/.claude/commands/`, symlinked into `~/.claude/agents/` and `~/.claude/commands/` (copied instead when Windows does not permit symbolic links) | Edit the files in `~/.agex`. Changes apply to every project from the next session; with copies, re-run `install.ps1` first |
| Plugin | Claude Code's plugin cache under `~/.claude/plugins/` | Do not edit in place: every plugin update replaces those files. Fork the repository instead (see below) |
| Copied into one project | `<project>/.claude/agents/` and `<project>/.claude/commands/` | Edit them in the project and commit them with it |

Keep your own agents and commands out of `~/.agex`. Put them in `<project>/.claude/agents/` and `<project>/.claude/commands/` to share them with your team through git, or in `~/.claude/agents/` and `~/.claude/commands/` to use them in every project on your machine. Those locations work the same way for every install method.

**Keeping edits to AGEX's own files.** `~/.agex` is an ordinary git clone, and `git pull` refuses to overwrite uncommitted local edits. Commit your changes on a branch and rebase it onto each release:

```bash
git -C ~/.agex switch -c local-customizations
git -C ~/.agex commit -am "Customize AGEX routing and models"
git -C ~/.agex pull --rebase origin main   # later, to take upstream updates
```

To share customizations across a team, fork the repository on GitHub and set `AGEX_REPO` to your fork's clone URL when you run the installer. The installer reads `AGEX_REPO` only when it clones, so on a machine that already has `~/.agex`, either point that clone at the fork (`git -C ~/.agex remote set-url origin <fork URL>`) or pass `--dir <new path>` so the fork is cloned into a separate checkout and the links switch to it. Plugin users with a fork remove the upstream marketplace (`claude plugin marketplace remove agex-marketplace`), then run `claude plugin marketplace add` with the fork's `owner/repo` and install `agex@agex-marketplace` from it.

## Adding a custom agent

This walkthrough builds `a11y-auditor`, a read-only agent that audits UI code for accessibility problems. Swap in your own domain as you go; the structure stays the same.

### 1. Copy the template

The template is [templates/custom-agent.md](../templates/custom-agent.md). With an installer-based setup it is already on disk:

```bash
mkdir -p .claude/agents
cp ~/.agex/templates/custom-agent.md .claude/agents/a11y-auditor.md
```

With the plugin, download it instead:

```bash
mkdir -p .claude/agents
curl -fsSL https://raw.githubusercontent.com/saksham-eng560/agex/main/templates/custom-agent.md -o .claude/agents/a11y-auditor.md
```

Use `~/.claude/agents/` instead of `.claude/agents/` if you want the agent in every project. The file name must match the agent's `name`.

### 2. Fill in the frontmatter

```yaml
---
name: a11y-auditor
description: "Read-only accessibility auditor. Use to check web UI components and pages against WCAG 2.2 AA (semantic markup, keyboard access, focus order, color contrast, ARIA usage) before or after UI changes. Produces an A11yAuditReport. Never modifies files."
tools: Read, Grep, Glob, Bash
disallowedTools: Write, Edit
model: sonnet
color: yellow
---
```

| Field | Rules |
|---|---|
| `name` | Lowercase kebab-case, identical to the file name without `.md`. Do not reuse an AGEX agent name (`orchestrator`, `researcher`, `architect`, `coder`, `reviewer`, `tester`, `debugger`, `documenter`, `devops`, `refactor`, `security`, `planner`) |
| `description` | One line in double quotes. Start with the role, then say when to use it. The orchestrator and Claude Code choose agents from this text, so name concrete task types rather than qualities. End read-only agents with "Never modifies files." |
| `tools` | Comma-separated allowlist. Always set it: without it the agent inherits every tool in the session, including MCP tools |
| `disallowedTools` | Optional denylist, applied after `tools`. Omit the line when the agent edits files |
| `model` | `opus`, `sonnet`, `haiku`, `inherit`, or a full model ID. See [Changing models per agent](#changing-models-per-agent) |
| `color` | One of `red`, `blue`, `green`, `yellow`, `purple`, `orange`, `pink`, `cyan` |

AGEX keeps the fields in exactly this order. The template's guidance lives in HTML comments below the frontmatter, because an HTML comment inside the frontmatter would break the YAML and stop the agent from loading.

### 3. Choose tools by least privilege

Start from the smallest set that can do the job, and add a tool only when a step in the agent's procedure needs it.

| Agent kind | `tools` | `disallowedTools` | AGEX agents built this way |
|---|---|---|---|
| Read-only analyst | `Read, Grep, Glob` | none | architect, planner |
| Read-only, runs inspection commands | `Read, Grep, Glob, Bash` | `Write, Edit` | reviewer, security |
| Read-only, needs the web | add `WebSearch, WebFetch` to a read-only row | `Write, Edit` | researcher |
| Edits files | `Read, Write, Edit, Bash, Grep, Glob` | none | coder, tester, debugger, refactor, devops |
| Edits docs only | `Read, Write, Edit, Grep, Glob` | none | documenter |
| Coordinates other agents | add `Agent` | none | orchestrator |

Be honest with yourself about what each row guarantees. `disallowedTools: Write, Edit` stops the agent from calling those tools. A shell, however, can still change files, so an agent that keeps `Bash` is read-only only because its prompt says so. If that is not enough for your case, drop `Bash` (the `Read, Grep, Glob` row) or add session-wide deny rules, described under [Restricting or granting tools](#restricting-or-granting-tools).

### 4. Write the system prompt

Everything below the frontmatter is the agent's system prompt. AGEX agents share one structure, and the template follows it:

| Section | What it contains |
|---|---|
| `# <Role Title> — AGEX <Agent Name>` | Two to four sentences in the second person ("You are..."): who the agent is, the one outcome it owns, and what it values when trade-offs appear |
| `## Your Place in the AGEX Pipeline` | Who dispatches it, which artifact it receives, and who consumes its output |
| `## Operating Procedure` | Numbered, concrete steps, with real commands and file patterns |
| `## Hard Constraints` | At least four bullets that start with **NEVER**, plus MUST rules as needed |
| `## Output Format` | The artifact template inside a markdown code fence |
| `## Quality Bar` / `## Escalation` | Optional: when to report success, and when to stop early |

Keep the body between 300 and 800 words. Shorter prompts leave the agent guessing, and longer ones cost tokens on every dispatch without adding much. Delete the template's guidance comments first, then measure:

```bash
sed '1,/^---$/d' .claude/agents/a11y-auditor.md | wc -w
```

Write the prompt so it works on its own. The agent runs in a fresh context with only its prompt, the delegation packet, and your repository, so it cannot rely on AGEX's documentation or on the conversation that dispatched it.

#### Writing NEVER constraints

Each constraint should describe an action you could spot in a transcript. Vague virtues cannot be checked; specific prohibitions can.

| Weak | Strong |
|---|---|
| Be careful with files. | **NEVER** modify files. Bash is for read-only inspection only: no redirects to files, no package installs, no git state changes. |
| Be accurate. | **NEVER** report a contrast failure without the two colors and the computed ratio. |
| Stay focused. | **NEVER** audit files outside the scope in your delegation packet. |
| Protect secrets. | **NEVER** reproduce secrets or tokens; show at most the first 4 characters followed by `****`. |

Keep the template's universal bullets (no invented results, no out-of-scope changes, no secrets, no remote or irreversible operations) and add the ones specific to your domain.

#### Defining the artifact

Every AGEX artifact uses the same envelope, which is how the orchestrator recognizes and validates it:

1. The marker line: `<!-- agex:artifact type=<Type> version=1 -->`.
2. A title line: `## <Type>: <short title>`.
3. A Producer, Status, and Confidence line, with the Status taken from a fixed enum.
4. `###` sections in a fixed order.

Choose a new PascalCase type name (not one of the twelve built-in types listed in [Handoff Protocol](HANDOFF-PROTOCOL.md)) and two to four uppercase status values. The Output Format section of `a11y-auditor` could read:

````markdown
## Output Format

Return exactly one artifact in this format:

```markdown
<!-- agex:artifact type=A11yAuditReport version=1 -->
## A11yAuditReport: <short title>
**Producer:** a11y-auditor · **Status:** PASS | FINDINGS | BLOCKED · **Confidence:** HIGH | MEDIUM | LOW

### Scope
<components and pages audited, and the standard applied>

### Findings
| ID | Severity | WCAG Criterion | Location | Problem | Remediation |
|---|---|---|---|---|---|

### Checks Performed
- [ ] Semantic landmarks and heading order
- [ ] Keyboard access and visible focus
- [ ] Color contrast
- [ ] Names, roles, and states for interactive elements

### Summary
<finding counts per severity and the overall verdict>
```

PASS means no findings of MEDIUM severity or higher; FINDINGS means at least one; BLOCKED means the scope could not be audited.
````

### 5. Check that it loads

Run Claude Code's validator from the project root. It parses the frontmatter of every agent and command under `.claude/` and reports problems that would stop a file from loading:

```bash
claude plugin validate --strict .
```

Then start a new Claude Code session and run `/agents`; `a11y-auditor` should appear under your project or user agents. Call it directly once before you route work to it:

```text
Use the a11y-auditor agent to audit src/components/LoginForm.tsx
```

Check that the reply starts with the marker line and that every section is present.

## Making the orchestrator route to your agent

The orchestrator dispatches agents through Claude Code's Agent tool, which lists every installed agent together with its description. Which agent it picks for a task, though, comes from its routing table. A new agent is therefore available immediately, but it is dispatched reliably only once the routing tells the orchestrator when to use it.

Naming works without changes. The orchestrator uses the scoped name `agex:<name>` when the Agent tool lists it (plugin installs) and the bare name otherwise. Your own agents are never scoped, so they are always dispatched by their bare name, such as `a11y-auditor`.

### Option 1: a routing note in your project's CLAUDE.md

This option edits no AGEX file, so updates never conflict with it. Add a section like this to the project's `CLAUDE.md`:

```markdown
## AGEX routing

- Accessibility audits, and any change under src/components/: dispatch the `a11y-auditor` agent.
  It returns an A11yAuditReport with status PASS | FINDINGS | BLOCKED.
- Treat FINDINGS like CHANGES_REQUESTED: send the findings to the coder, then re-run
  a11y-auditor. The usual 3-cycle limit applies.
```

It works because `/agex` runs in your main conversation, which loads `CLAUDE.md` automatically, and because the orchestrator agent reads the project's `CLAUDE.md` files before it plans a run.

### Option 2: edit the routing tables

To make the route part of AGEX itself (for every project, or in a fork), edit both orchestration prompts and keep them consistent. Each has a **Route by task type** table and an artifact table in its **Validate** step.

1. `.claude/commands/agex.md`, which drives your main conversation when you type `/agex`:
   - routing row: `| Accessibility audit | a11y-auditor | a11y-auditor → coder (if fixes requested) → reviewer → a11y-auditor re-check |`
   - artifact row: `| A11yAuditReport | a11y-auditor | PASS, FINDINGS, BLOCKED |`
2. `.claude/agents/orchestrator.md`, which runs when the orchestrator agent is dispatched or started with `claude --agent orchestrator`: add the same route and artifact, matching the column layout of its tables.

Registering the artifact type and its status values lets the orchestrator validate your agent's output the same way it validates the built-in artifacts. The orchestrator's system prompt is sent on every run, so add one precise row rather than paragraphs. In the AGEX repository itself its body must stay between 600 and 800 words.

## Changing models per agent

Each agent's `model` field decides which model runs it:

| Value | Effect |
|---|---|
| `opus` | The most capable model family, and the most expensive per token |
| `sonnet` | Strong at coding, at a lower cost than Opus |
| `haiku` | The fastest and cheapest family, suited to structured, well-scoped work |
| `inherit` | The same model as whatever dispatched the agent |
| A full model ID (a `claude-` model name) | Pins an exact model instead of the alias's current default |

AGEX's defaults, and the reasoning behind them:

| Agents | Default | Why |
|---|---|---|
| orchestrator | `opus` | Classification, decomposition, and synthesis decide how much every other dispatch costs, so the strongest reasoning pays for itself here |
| researcher, architect, coder, reviewer, tester, debugger, devops, refactor, security | `sonnet` | Code-heavy work that needs strong judgment on every dispatch |
| planner, documenter | `haiku` | Structured output from context the agent is given; speed and cost matter more than depth |

Every dispatch is a separate model conversation, and feedback loops multiply them, so the choice for frequently dispatched agents (coder, tester, reviewer) matters most for cost. Common adjustments:

- **Lower cost:** set the orchestrator to `sonnet`. This works well for MEDIUM tasks with clear acceptance criteria, though it is weaker at decomposing large, ambiguous requests.
- **Higher assurance:** set `reviewer` and `security` to `opus` for security-sensitive code. They run once or twice per work unit, so the extra cost is bounded.
- **Follow the session:** set `inherit` on agents that should use whatever you picked with `/model`.

When you run `/agex`, orchestration happens in your main conversation, so the orchestrator's `model: opus` does not apply there: the main conversation uses your session model. The orchestrator's model setting applies when it runs as a subagent, or as the session agent through `claude --agent orchestrator`.

## Restricting or granting tools

`tools` is an allowlist and `disallowedTools` is a denylist applied after it. Both are comma-separated tool names. The tools AGEX agents use are `Read`, `Write`, `Edit`, `Grep`, `Glob`, `Bash`, `WebSearch`, `WebFetch`, and `Agent`. MCP tools are named `mcp__<server>__<tool>` and must be listed explicitly, because an agent with a `tools` list gets only the tools on it.

Examples:

- **No web access.** For offline or air-gapped work, remove `WebSearch, WebFetch` from the researcher: `tools: Read, Grep, Glob, Bash`.
- **Stricter reviewer.** `tools: Read, Grep, Glob` makes the reviewer unable to change anything, at the price of no longer running tests or `git diff`: it relies on what the delegation packet gives it.
- **Access to an issue tracker.** Add the specific MCP tools the agent needs (for example, a read-only issue lookup) to its `tools` line, rather than removing the `tools` line altogether.

For command-level guardrails, use Claude Code permission rules. They apply to the whole session, including every subagent. Add them to `.claude/settings.json` in a project or to `~/.claude/settings.json`:

```json
{
  "permissions": {
    "deny": [
      "Bash(git push *)",
      "Bash(npm publish *)",
      "Bash(rm -rf *)"
    ]
  }
}
```

Do not deny `git status`, `git ls-files`, `git diff`, `git log`, `grep`, `head`, `tail`, `ls`, `echo`, or `wc`. AGEX's slash commands use them to collect context before the prompt is sent, and a denied program aborts the whole command. See the [FAQ](FAQ.md) entry on "Shell command failed".

Plugin agents ignore the `hooks`, `mcpServers`, and `permissionMode` frontmatter fields. AGEX's agents do not use them. If your own agent needs them, install it as a project or user agent (in `.claude/agents/` or `~/.claude/agents/`), not through a plugin.

## Adding a custom command

A command is a Markdown prompt with optional shell injections that collect context before the model sees it. Start from [templates/custom-command.md](../templates/custom-command.md):

```bash
mkdir -p .claude/commands
cp ~/.agex/templates/custom-command.md .claude/commands/a11y.md
```

The file name is the command name, so this file becomes `/a11y`. Do not start the name with `agex`, because those names belong to AGEX's own commands.

### Frontmatter

| Field | Purpose |
|---|---|
| `description` | One quoted line, shown in the slash-command menu |
| `argument-hint` | What the user types after the command name. Omit it for commands without arguments |
| `allowed-tools` | Space-separated tool patterns that are pre-approved while the command runs, for example `Bash(git status *) Bash(head *)`. Every program an injection uses must be listed |

AGEX commands set no `model` field; they run on the session's model.

### Arguments

`$ARGUMENTS` is replaced with everything the user typed after the command name. It may be empty, so every command that needs a task must say what to do in that case, typically "If no task was given, ask the user what to do and stop". Never place `$ARGUMENTS` inside a shell injection: user text must never become shell input.

### Shell injection safety rules

A line that starts with `!` followed by a command in backticks is a shell injection. Claude Code runs it before the model sees the prompt and pastes its output in place. **If an injection exits with a non-zero status, or calls a program that `allowed-tools` and your permission rules do not allow, Claude Code aborts the entire command.** Every injection must therefore:

1. **Be strictly read-only.** It runs without a confirmation prompt.
2. **End in a guaranteed-success fallback:** `... 2>/dev/null || echo "(fallback message)"`. A pipeline that ends in `head` always exits 0, so it needs no `echo`.
3. **Use only these programs, each listed in `allowed-tools`:**

   | Program | Pattern |
   |---|---|
   | `git status` | `Bash(git status *)` |
   | `git ls-files` | `Bash(git ls-files *)` |
   | `git diff` | `Bash(git diff *)` |
   | `git log` | `Bash(git log *)` |
   | `grep` | `Bash(grep *)` |
   | `head` | `Bash(head *)` |
   | `tail` | `Bash(tail *)` |
   | `ls` | `Bash(ls *)` |
   | `echo` | `Bash(echo *)` |
   | `wc` | `Bash(wc *)` |

   List only the patterns the command actually uses.
4. **Never use** `find` (it can delete files and run programs through `-delete` and `-exec`), `cat`, `sh -c`, `xargs`, redirects into files, or anything that prints secret files such as `.env`. List project files with `git ls-files --cached --others --exclude-standard`, which respects `.gitignore` and skips `node_modules`, and read the start of a file with `head -N`.
5. **Never use `git diff HEAD~1`.** It fails in a repository with only one commit. For the last commit, use `git log -1 --stat -p 2>/dev/null | head -200 || echo "(no commits yet)"`.
6. **Start at the beginning of a line** (or after whitespace), or the injection is not recognized.

| Unsafe | Safe replacement |
|---|---|
| `` !`cat CLAUDE.md` `` | `` !`head -60 CLAUDE.md 2>/dev/null \|\| echo "(no CLAUDE.md)"` `` |
| `` !`find . -name "*.test.ts"` `` | `` !`git ls-files --cached --others --exclude-standard 2>/dev/null \| grep -F ".test." \| head -40` `` |
| `` !`git diff HEAD~1` `` | `` !`git log -1 --stat -p 2>/dev/null \| head -200 \|\| echo "(no commits yet)"` `` |
| `` !`git status` `` | `` !`git status --short 2>/dev/null \|\| echo "(not a git repository)"` `` |

### Choosing the agent

Tell the model which agent to use, applying the AGEX naming rule for AGEX's agents: dispatch `agex:<name>` if the Agent tool lists it, otherwise the bare `<name>`. Your own agents always use their bare name. A complete command that runs the `a11y-auditor` agent on the current changes:

```markdown
---
description: "Audit changed UI files for accessibility with the a11y-auditor agent"
argument-hint: "[optional path or component to focus on]"
allowed-tools: Bash(git status *) Bash(git diff *) Bash(head *) Bash(echo *)
---

# Accessibility Audit

## Focus

$ARGUMENTS

If no focus was given above, audit every UI file changed in the working tree.

## Changed files

!`git status --short 2>/dev/null || echo "(not a git repository)"`

## Diff (first 300 lines)

!`git diff 2>/dev/null | head -300`

## Instructions

Dispatch the `a11y-auditor` agent with the focus and the changed files above as its inputs, limited to UI files. Present its A11yAuditReport unchanged, then summarize the findings by severity and ask whether the coder should fix them.
```

## Enabling session-log hooks for symlink installs

Plugin installs, and Claude Code sessions inside the AGEX repository itself, log automatically. Installer-based setups get agents and commands only, because an installer should not edit your `settings.json`. To turn logging on, add these hooks to `~/.claude/settings.json`:

```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "sh \"$HOME/.agex/hooks/scripts/agex-log.sh\" session-start 2>/dev/null || true",
            "timeout": 10
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Write|Edit|MultiEdit",
        "hooks": [
          {
            "type": "command",
            "command": "sh \"$HOME/.agex/hooks/scripts/agex-log.sh\" file-modified 2>/dev/null || true",
            "timeout": 10
          }
        ]
      }
    ]
  }
}
```

- If the file already has a `hooks` object, merge these entries into it instead of replacing it.
- If you installed with a custom `AGEX_HOME` or `--dir`, change `$HOME/.agex` to that path.
- `|| true` guarantees that a logging problem can never interrupt your session; the script itself also always exits 0.

From the next session on, every project you open gets a `.agex/session.log` with one line per event, such as `[2026-09-27T10:15:02Z] SESSION_START source=startup` or `[2026-09-27T10:16:40Z] FILE_MODIFIED tool=Edit path=src/users/validate.ts`. The script logs event names and file paths only, never file contents. It creates `.agex/.gitignore` so the directory never shows up in `git status`, and it rotates the log to `session.log.1` once it passes 1 MiB. The orchestrator adds its own DISPATCH, ARTIFACT, CYCLE, ESCALATION, and RUN_COMPLETE lines whenever `.agex/` exists, and `/agex-status` shows the tail of the log.

## Disabling logging

Set `AGEX_DISABLE_LOG=1` to make the hook script exit before it writes anything. Either export it in your shell profile:

```bash
export AGEX_DISABLE_LOG=1
```

or set it for Claude Code in `~/.claude/settings.json` (or a project's `.claude/settings.json`):

```json
{
  "env": {
    "AGEX_DISABLE_LOG": "1"
  }
}
```

The variable stops hook logging only. The orchestrator writes its own events only when a `.agex/` directory already exists, so delete `.agex/` from a project as well to stop logging there completely. With the variable set, the hooks no longer recreate it.

## Tuning the circuit breakers

The circuit breakers are instructions in two prompts, not settings in a program. The orchestrator follows whichever prompt is running: `.claude/agents/orchestrator.md` when the orchestrator agent runs, `.claude/commands/agex.md` when you use `/agex`. Change the same number in both files, or the two entry points will behave differently.

| Breaker | Default |
|---|---|
| Coder ⇄ tester loop | 3 cycles per work unit |
| Coder ⇄ reviewer loop | 3 cycles per work unit |
| No-progress rule | Escalate after 2 consecutive cycles with the same failure signature |
| Sub-agent failure retry | 1 retry with simpler, narrower instructions |
| Dispatch budget | Soft cap of 15 dispatches per run, then ask the user |

To find every line that states a limit (add the `.claude` path of a project copy, or of your fork, as needed):

```bash
grep -nE "[0-9]+ cycles|dispatches|consecutive|retry" ~/.agex/.claude/agents/orchestrator.md ~/.agex/.claude/commands/agex.md
```

The coder, tester, and reviewer prompts also mention the cycle cap when they describe their place in the pipeline; `grep -rlE "[0-9]+ cycles" ~/.agex/.claude/agents` lists them. Update those sentences too, so that no agent works toward a limit that no longer applies.

Lowering the loop limit to 2 saves cost when your test suite is fast and failures are usually clear-cut. Raising it to 4 or 5 can help in large legacy codebases with slow feedback. A limit above 5 rarely helps, because repeated failures usually point to a design problem that the architect or you should resolve. Keep the no-progress rule and the BLOCKED stop in place: they end loops that more cycles would not fix. If you maintain a fork, update the same numbers in `CLAUDE.md` and the docs so they keep describing what the prompts do.

## Contributing custom agents upstream

An agent that would help most AGEX users is welcome upstream. Read [CONTRIBUTING](../CONTRIBUTING.md) first, then include all of the following in your pull request:

1. The agent file in `.claude/agents/`, following the structure and the 300 to 800 word limit described above, with a canonical one-line description.
2. Its path in the `agents` list of [.claude-plugin/plugin.json](../.claude-plugin/plugin.json), so plugin installs ship it.
3. A route in the orchestrator's routing table and in `.claude/commands/agex.md`, its artifact in the orchestrator's artifact table if the type is new, and the agent in the list that `.claude/commands/agex-status.md` reports.
4. The artifact schema in [Handoff Protocol](HANDOFF-PROTOCOL.md), and the agent's entry in [Agents](AGENTS.md).
5. Updated agent tables and counts in [README](../README.md), `CLAUDE.md`, and the plugin description in [.claude-plugin/marketplace.json](../.claude-plugin/marketplace.json), and an entry under Unreleased in [CHANGELOG](../CHANGELOG.md).
6. The agent's expected frontmatter values in `AGENT_ROSTER` in [scripts/validate.py](../scripts/validate.py), plus its artifact in `ARTIFACTS` if the type is new; the validator rejects an agent file it does not know.
7. A clean run of both validators:

   ```bash
   python3 scripts/validate.py
   claude plugin validate --strict .
   ```

[scripts/validate.py](../scripts/validate.py) checks required files, agent frontmatter against the roster, body word counts, required sections, NEVER constraints, artifact templates, command frontmatter and injection safety, the plugin and marketplace manifests, version consistency, the hook configurations, relative links, placeholders and email addresses, and emojis in agents and commands. CI runs it on every pull request, together with `claude plugin validate --strict .`, ShellCheck, installer smoke tests on Ubuntu, macOS, and Windows, and tests of the logging hook.
