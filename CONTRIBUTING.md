# Contributing to AGEX

Thank you for your interest in improving AGEX. AGEX is a multi-agent
orchestration framework for Claude Code, and nearly all of it is plain text:
agent prompts, slash commands, a handoff protocol, and a few small scripts.
That makes it easy to contribute, and it also means that a single unclear
sentence in a prompt can change how every user's agents behave. This guide
explains how to make changes that are correct, consistent, and easy to review.

By participating in this project you agree to follow the
[Code of Conduct](CODE_OF_CONDUCT.md).

## Table of Contents

- [Ways to Contribute](#ways-to-contribute)
- [Development Setup](#development-setup)
- [Repository Layout](#repository-layout)
- [Adding or Changing an Agent](#adding-or-changing-an-agent)
- [Adding or Changing a Slash Command](#adding-or-changing-a-slash-command)
- [Style Guide](#style-guide)
- [Commit Messages](#commit-messages)
- [Pull Request Process](#pull-request-process)
- [Release Process](#release-process)
- [License](#license)

## Ways to Contribute

- **Report bugs.** Use the
  [bug report form](https://github.com/saksham-eng560/agex/issues/new/choose)
  and include your AGEX version, Claude Code version (`claude --version`),
  install method, and the relevant part of `.agex/session.log`.
- **Improve agent prompts.** If an agent ignores a constraint, loops, or
  produces an artifact that does not match the protocol, a focused prompt fix
  with a description of the scenario you tested is one of the most valuable
  contributions you can make.
- **Suggest features.** Use the
  [feature request form](https://github.com/saksham-eng560/agex/issues/new/choose)
  for new agents, commands, orchestration behavior, or installer options.
  Please open an issue before starting large changes so we can agree on scope.
- **Improve documentation.** Fix unclear explanations, add examples to
  [docs/EXAMPLES.md](docs/EXAMPLES.md) or [examples/](examples/web-app-build/task.md),
  and answer questions that should live in [docs/FAQ.md](docs/FAQ.md).
- **Test the installers.** Running `install.sh` or `install.ps1` on a platform
  or shell we have not covered and reporting the result helps everyone.
- **Review pull requests.** Careful reviews of prompt changes are especially
  welcome, because prompt regressions are easy to miss.

Security vulnerabilities must never be reported in public issues. Follow
[SECURITY.md](SECURITY.md) instead.

## Development Setup

### Prerequisites

- Git
- Python 3.8 or later (the validator uses the standard library only)
- Claude Code v2.1 or later, to try your changes and to run the plugin validator
- Bash (3.2 or later) to test `install.sh`, a POSIX `sh` for the hook script,
  and Windows PowerShell 5.1 or PowerShell 7 to test `install.ps1`

### Clone and validate

Fork the repository and clone your fork, for example with the GitHub CLI:

```bash
gh repo fork saksham-eng560/agex --clone
cd agex
```

Run the repository validator. CI runs the same script on every pull request,
so a clean local run saves a review round trip:

```bash
python3 scripts/validate.py
```

It never modifies a file. It prints PASS or FAIL for ten groups of checks and
exits 1 on any error; warnings are printed for review but never fail it. The
groups are: required files; the twelve agents (frontmatter fields, order, and
values against the expected roster, body word counts, required headings, NEVER
constraints, and the Output Format artifact template); the eight commands
(frontmatter, `$ARGUMENTS`, the `agex:<name>` naming rule, and the safety of
every `!` injection, including those in `templates/custom-command.md`); the
plugin manifest; the marketplace; version consistency across `plugin.json`,
`marketplace.json`, `CHANGELOG.md`, and the README badge; the two hook
configurations; relative Markdown links; placeholder text and email addresses;
and emojis in agents and commands. Pass `--quiet` to print errors only.

If you have Claude Code installed, also validate the plugin manifest, agents,
and commands the way Claude Code itself loads them:

```bash
claude plugin validate --strict .
```

### Try your changes in Claude Code

There are two ways to load a working copy:

1. **Inside the repository.** Run `claude` from the repository root. Claude Code
   loads the agents from `.claude/agents/` and the commands from
   `.claude/commands/` as project components (bare names such as `orchestrator`
   and `/agex`), and the project hooks in `.claude/settings.json` write to
   `.agex/session.log`.
2. **As a plugin, in another project.** From any test project, run
   `claude --plugin-dir /path/to/your/agex/checkout`. This loads your working
   copy as a plugin for that session only, so you see the namespaced names that
   plugin users get (`agex:orchestrator`, `/agex:agex`) and the plugin hooks in
   `hooks/agex-hooks.json`.

Use a small throwaway project for end-to-end runs so agents cannot modify
anything you care about.

### Test install.sh safely

Point `CLAUDE_HOME` at a temporary directory so the installer never touches
your real `~/.claude`. Run from your checkout, the installer links that working
copy (the checkout the script lives in wins over `AGEX_HOME`), and
`--no-update` keeps it from pulling:

```bash
export CLAUDE_HOME="$(mktemp -d)"
./install.sh --no-update
ls -l "$CLAUDE_HOME/agents" "$CLAUDE_HOME/commands"
head -5 "$CLAUDE_HOME/.agex-manifest"
./install.sh --no-update
./install.sh --uninstall
ls -la "$CLAUDE_HOME" "$CLAUDE_HOME/agents" "$CLAUDE_HOME/commands"
rm -rf "$CLAUDE_HOME" && unset CLAUDE_HOME
```

Check that the first listing shows 12 agent links and 8 command links, that the
second run reports every link as unchanged, and that after `--uninstall` the
links and `.agex-manifest` are gone. To exercise the backup path, create a file
such as `$CLAUDE_HOME/agents/planner.md` before installing: a plain run must
skip it with a warning, `--force` must move it to
`$CLAUDE_HOME/.agex-backup/<timestamp>/agents/`, and `--uninstall` must put it
back. Also run `./install.sh --help` and confirm that an unknown flag exits
with status 2. If you have [ShellCheck](https://www.shellcheck.net/) installed,
run `shellcheck --severity=warning install.sh hooks/scripts/agex-log.sh`, as CI does.

### Test install.ps1 safely

The same approach works in PowerShell:

```powershell
$env:CLAUDE_HOME = Join-Path ([System.IO.Path]::GetTempPath()) ("agex-test-" + [guid]::NewGuid())
.\install.ps1 -NoUpdate
Get-ChildItem "$env:CLAUDE_HOME\agents", "$env:CLAUDE_HOME\commands"
.\install.ps1 -Uninstall
Remove-Item -Recurse -Force $env:CLAUDE_HOME
Remove-Item Env:CLAUDE_HOME
```

Without Developer Mode or an elevated shell, the installer copies the files
instead of linking them; test both paths if you change the linking code.

### Test the hook script

The hook script reads the hook payload from stdin. Point `CLAUDE_PROJECT_DIR`
at a temporary directory to exercise it without touching a real project:

```bash
tmp="$(mktemp -d)"
printf '{"source":"startup"}' |
  CLAUDE_PROJECT_DIR="$tmp" sh hooks/scripts/agex-log.sh session-start
printf '{"tool_name":"Edit","tool_input":{"file_path":"%s/src/app.py"}}' "$tmp" |
  CLAUDE_PROJECT_DIR="$tmp" sh hooks/scripts/agex-log.sh file-modified
cat "$tmp/.agex/session.log"
```

You should see one `SESSION_START` line and one `FILE_MODIFIED` line with the
path `src/app.py`. The script must always exit 0 and must never log file
contents.

## Repository Layout

```text
agex/
├── .claude/
│   ├── agents/              12 AGEX agents, one Markdown file each
│   ├── commands/            8 slash commands (/agex and the /agex-* family)
│   └── settings.json        project hooks active while developing AGEX
├── .claude-plugin/
│   ├── plugin.json          plugin manifest: version, agents, commands, hooks
│   └── marketplace.json     single-plugin marketplace (agex-marketplace)
├── .github/                 issue forms, PR template, CI workflow,
│                            CODEOWNERS, Dependabot configuration
├── docs/                    architecture, agent catalog, quickstart,
│                            customization, handoff protocol, examples, FAQ
├── examples/                end-to-end walkthroughs, one task.md each
├── hooks/
│   ├── agex-hooks.json      plugin hooks (SessionStart, PostToolUse)
│   └── scripts/agex-log.sh  POSIX sh session logger
├── scripts/validate.py      repository validator used by CI and contributors
├── templates/               starting points for custom agents and commands
├── install.sh               macOS and Linux installer
├── install.ps1              Windows PowerShell installer
├── CLAUDE.md                project memory loaded by Claude Code in this repo
└── README.md, CHANGELOG.md, SECURITY.md, CONTRIBUTING.md,
    CODE_OF_CONDUCT.md, LICENSE
```

`.agex/` is created at runtime by the hooks and is git-ignored.

## Adding or Changing an Agent

Agents live in `.claude/agents/<name>.md`. Start new agents from
[templates/custom-agent.md](templates/custom-agent.md), and read
[docs/CUSTOMIZATION.md](docs/CUSTOMIZATION.md) for background on tools,
models, and routing. Every agent must satisfy this checklist.

### Frontmatter

- [ ] `name` is kebab-case and equals the filename stem.
- [ ] Fields appear in this order: `name`, `description`, `tools`,
      `disallowedTools` (only when needed), `model`, `color`.
- [ ] `description` is one line, a double-quoted string, starts with the role,
      and says when to use the agent. The orchestrator routes on this text.
- [ ] `tools` (and `disallowedTools`, if present) is a comma-separated string,
      for example `tools: Read, Grep, Glob`, and grants the least privilege the
      role needs. Read-only agents also list `disallowedTools: Write, Edit` when
      they keep `Bash`.
- [ ] `model` is an alias: `opus`, `sonnet`, or `haiku`.
- [ ] `color` is one of `red`, `blue`, `green`, `yellow`, `purple`, `orange`,
      `pink`, `cyan`.
- [ ] No `hooks`, `mcpServers`, or `permissionMode` fields. Claude Code ignores
      them for plugin subagents, so they would behave differently per install.

### Body

- [ ] The body (everything after the frontmatter) is **300 to 800 words**; the
      orchestrator is **600 to 800 words**. `python3 scripts/validate.py` is the
      authority; for a quick check run
      `sed '1,/^---$/d' .claude/agents/<name>.md | wc -w`.
- [ ] Required headings, in this order:
  1. `# <Role Title> — AGEX <Agent Name>`, followed by a 2 to 4 sentence persona
     and goal paragraph in the second person ("You are...").
  2. `## Your Place in the AGEX Pipeline`: who dispatches the agent, which
     artifact it receives, and who consumes its output.
  3. `## Operating Procedure`: numbered, concrete, actionable steps.
  4. `## Hard Constraints`: a bullet list with at least 4 bullets that start
     with `**NEVER**`, plus MUST rules as needed.
  5. `## Output Format`: the artifact template in a `markdown` code fence.
  6. Optional: `## Quality Bar` and `## Escalation`.
- [ ] The artifact template matches [docs/HANDOFF-PROTOCOL.md](docs/HANDOFF-PROTOCOL.md)
      exactly: the `<!-- agex:artifact type=<Type> version=1 -->` marker line,
      the `## <Type>: <short title>` title line, the
      `**Producer:** <agent> · **Status:** <enum> · **Confidence:** HIGH | MEDIUM | LOW`
      line, and every `###` section, table column, and status enum in the
      documented order.
- [ ] The agent is self-contained. Users install AGEX into other projects where
      `docs/` does not exist, so never tell an agent to read AGEX documentation
      files.
- [ ] The agent never invents results: every claim about tests, builds, or
      commands must come from a command it actually ran.
- [ ] Read-only agents state that `Bash` (where granted) is for read-only
      inspection only: no redirects to files, no installs, no git state changes.
- [ ] No emojis.

### Keep everything in sync

Adding, renaming, or removing an agent touches more than one file. Update all
of these in the same pull request:

- [ ] `.claude-plugin/plugin.json`: the `agents` list.
- [ ] `README.md`: the Agent Catalog table and the agent count badge.
- [ ] [docs/AGENTS.md](docs/AGENTS.md): the agent's full specification.
- [ ] [CLAUDE.md](CLAUDE.md): the agent list and routing rules.
- [ ] `.claude/agents/orchestrator.md` and `.claude/commands/agex.md`: the
      routing table, if the orchestrator should dispatch the new agent.
- [ ] `.claude/commands/agex-status.md`: the agent list it reports.
- [ ] `.claude-plugin/marketplace.json`: the agent count in the plugin
      description.
- [ ] [docs/HANDOFF-PROTOCOL.md](docs/HANDOFF-PROTOCOL.md): if you add or change
      an artifact type. A schema change affects every agent that consumes the
      artifact, so update the producer and all consumers together.
- [ ] `scripts/validate.py`: the expected roster (`AGENT_ROSTER`), and
      `ARTIFACTS` for a new artifact type. The validator rejects agent files it
      does not know.
- [ ] `CHANGELOG.md`: an entry under `## [Unreleased]`.

When you change an existing agent's `tools`, explain in the pull request why the
role needs the extra capability. Widening the tools of a read-only agent is a
security-relevant change and gets extra scrutiny.

## Adding or Changing a Slash Command

Commands live in `.claude/commands/<name>.md`. Start from
[templates/custom-command.md](templates/custom-command.md).

### Frontmatter

- `description`: a quoted, one-line string.
- `argument-hint`: required when the command takes arguments.
- `allowed-tools`: a space-separated list of patterns, for example
  `allowed-tools: Bash(git status *) Bash(head *) Bash(echo *)`.
- No `model` field.

### Shell injection safety rules

Lines of the form `` !`command` `` run **before** the model sees the prompt.
If an injected command exits non-zero, or is not covered by `allowed-tools` or
the user's permission rules, **Claude Code aborts the entire slash command**.
Every injection must therefore:

- be strictly read-only;
- end in a guaranteed-success fallback such as
  `2>/dev/null || echo "(fallback message)"`, or be a pipeline that ends with
  `head`, which exits 0;
- use only these programs: `git status`, `git ls-files`, `git diff`, `git log`,
  `grep`, `head`, `tail`, `ls`, `echo`, `wc`;
- list each program it uses in `allowed-tools`, using exactly these pattern
  forms, and list nothing it does not use: `Bash(git status *)`,
  `Bash(git ls-files *)`, `Bash(git diff *)`, `Bash(git log *)`, `Bash(grep *)`,
  `Bash(head *)`, `Bash(tail *)`, `Bash(ls *)`, `Bash(echo *)`, `Bash(wc *)`;
- start at the beginning of a line or after whitespace.

Never use:

- `find` (it can `-delete` and `-exec`), `cat`, `sh -c`, `xargs`, or redirects
  to files;
- anything that prints the contents of secret files such as `.env`;
- `git diff HEAD~1`, which fails in a repository with a single commit.

Use these patterns instead:

| Need | Safe injection |
|---|---|
| List project files (respects `.gitignore`, skips `node_modules`) | `` !`git ls-files --cached --others --exclude-standard 2>/dev/null \| head -100` `` |
| Show the start of a file | `` !`head -40 CLAUDE.md 2>/dev/null \|\| echo "(no CLAUDE.md)"` `` |
| Working tree status | `` !`git status --short 2>/dev/null \|\| echo "(not a git repository)"` `` |
| The last commit | `` !`git log -1 --stat -p 2>/dev/null \| head -200 \|\| echo "(no commits yet)"` `` |

### Body

- Use `$ARGUMENTS` for the user's input. A command that takes a task must handle
  empty arguments: "If no task was given, ask the user what to do and stop."
- Name the AGEX agent or agents to use and the artifact to present. Apply the
  naming rule: dispatch the scoped name `agex:<name>` if the Agent tool lists it
  (plugin install); otherwise use the bare name `<name>`.
- A focused command whose specialist is listed under neither name (or that
  runs without an Agent tool) says so and performs the task inline under that
  specialist's procedure and constraints, producing the same artifact with the
  Producer `<name> (inline fallback)`. It never substitutes a different agent
  and never hands the work to other sessions or to background, remote, or
  scheduled tasks. `/agex` has no inline fallback: it names the missing agent
  and stops.
- No emojis.

### Keep everything in sync

- [ ] `.claude-plugin/plugin.json`: the `commands` list.
- [ ] `README.md`: the Command Reference table and the command count badge.
- [ ] [CLAUDE.md](CLAUDE.md): the quick command reference.
- [ ] `.claude/commands/agex-status.md`: the command list it reports.
- [ ] `.claude-plugin/marketplace.json`: the command count in the plugin
      description.
- [ ] Any docs that list commands, such as [docs/QUICKSTART.md](docs/QUICKSTART.md).
- [ ] `scripts/validate.py`: the expected command list (`COMMANDS`, plus
      `COMMANDS_REQUIRING_ARGUMENTS` and `COMMAND_AGENTS` where they apply).
- [ ] `CHANGELOG.md`: an entry under `## [Unreleased]`.

Before opening the pull request, run the command in three places: a repository
with commits, a freshly initialized repository with no commits, and a directory
that is not a git repository. It must work in all three, which proves every
fallback fires correctly.

## Style Guide

### Markdown

- GitHub-flavored Markdown with exactly one `#` H1 per document.
- Use relative links between repository files, for example
  `[Handoff Protocol](docs/HANDOFF-PROTOCOL.md)` from the root and
  `[Agents](AGENTS.md)` inside `docs/`. Every relative link must resolve.
- Give every code fence a language (`bash`, `powershell`, `json`, `markdown`,
  `text`, `mermaid`).
- Emojis are allowed only in `README.md` headings and value propositions and in
  the `CHANGELOG.md` title line.
- Reuse the canonical architecture diagram from [CLAUDE.md](CLAUDE.md) verbatim
  instead of drawing a variant.

### Content rules

- No placeholders or stubs. Never commit unfinished-work markers, filler text,
  sample account names, or notes promising to add content later; every file
  ships complete. Angle-bracket fill-in fields such as `<name>` are allowed in
  `templates/` and in artifact templates, where they are the point.
- Never include an email address anywhere in the repository. Contact happens
  through GitHub.
- Be honest. Do not claim benchmarks, star counts, adoption, telemetry, or
  features that do not exist, and state known limitations where they matter.
- Write agent and command prompts in the second person and the imperative
  mood. Prefer specific, checkable instructions ("run the test command and
  quote its summary line") over general advice ("make sure tests pass").

### Code and configuration

- Formatting follows [.editorconfig](.editorconfig): UTF-8, LF line endings, a
  final newline, 2-space indentation, and 4 spaces for Python and PowerShell.
- `hooks/scripts/agex-log.sh` is POSIX `sh`, must always exit 0, and must never
  log file contents.
- `install.sh` must run on a fresh macOS system, which ships Bash 3.2: avoid
  associative arrays, `mapfile`, and `${var,,}`. Quote every variable expansion.
- Keep `install.ps1` ASCII-only; Windows PowerShell 5.1 reads files without a
  byte order mark in the system code page.
- `scripts/validate.py` uses the Python 3.8+ standard library only.
- JSON uses 2-space indentation and must pass `claude plugin validate --strict .`.

## Commit Messages

AGEX follows [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/):

```text
<type>(<optional scope>): <summary in the imperative mood>
```

Common types are `feat`, `fix`, `docs`, `refactor`, `test`, `ci`, `build`,
`perf`, and `chore`. Useful scopes include `agents`, `orchestrator`,
`commands`, `protocol`, `installer`, `hooks`, `plugin`, `docs`, and `ci`.

```text
fix(hooks): keep file paths with spaces on a single log line
feat(commands): accept a directory argument in /agex-test
docs(faq): explain plugin and symlink install namespaces
```

Mark breaking changes with `!` after the type or scope and a `BREAKING CHANGE:`
footer. Renaming or removing an agent, command, installer flag, or artifact
section or status value is a breaking change:

```text
feat(protocol)!: rename the ReviewVerdict Checks Performed section

BREAKING CHANGE: agents that parse ReviewVerdict must use the new heading.
```

## Pull Request Process

1. **Discuss large changes first.** Open an issue before adding an agent or
   command, changing an artifact schema, or changing installer behavior.
2. **Branch from `main`** with a descriptive name, for example
   `git switch -c fix/hook-path-spaces`.
3. **Keep each pull request focused** on one logical change. Separate unrelated
   fixes into separate pull requests.
4. **Run the checks locally:** `python3 scripts/validate.py`,
   `claude plugin validate --strict .`, and the installer tests above if you
   touched `install.sh` or `install.ps1`.
5. **Update the docs and `CHANGELOG.md`** under `## [Unreleased]`.
6. **Open the pull request** and complete the template, including how you
   tested. For prompt changes, describe the scenario you ran before and after
   the change and what improved.
7. **Make CI pass.** The CI workflow runs on every pull request and push to
   `main`. Its jobs run the validator, ShellCheck on `install.sh` and the hook
   script, `claude plugin validate --strict .`, an `install.sh` smoke test on
   Ubuntu and macOS (install, idempotent re-run, `--force` backup, uninstall,
   and restore), tests of the logging hook (including its `sed` fallback and
   `AGEX_DISABLE_LOG`), and an `install.ps1` smoke test on Windows.

### What reviewers look for

- **Correctness:** scripts work on every supported platform, and commands work
  inside and outside git repositories.
- **Least privilege:** no agent or command gains tools it does not need.
- **Prompt quality:** instructions are specific and testable, do not contradict
  other agents or the orchestration rules, and artifacts match the handoff
  protocol exactly.
- **Consistency:** names, counts, tables, and manifests agree across the
  repository.
- **Honesty:** documentation describes what AGEX actually does.

Maintainers aim to give a first review within a week. AGEX is maintained by
volunteers, so it can take longer; a polite ping on the pull request after a
week is welcome. Pull requests are squash-merged, and the pull request title
becomes the commit message, so it must follow Conventional Commits.

## Release Process

Releases are cut by maintainers. AGEX follows [Semantic Versioning](https://semver.org/):

- **Major:** breaking changes to artifact schemas, or renamed or removed
  agents, commands, or installer flags.
- **Minor:** new agents, commands, or backward-compatible features.
- **Patch:** bug fixes, prompt improvements that keep artifact schemas
  unchanged, and documentation fixes.

Steps:

1. In a release pull request, bump the version in:
   - `.claude-plugin/plugin.json` (`version`);
   - `.claude-plugin/marketplace.json` (`metadata.version` and the `version` of
     the `agex` entry in `plugins`);
   - `CHANGELOG.md`: move the `## [Unreleased]` entries into a new
     `## [X.Y.Z] - YYYY-MM-DD` section and update the comparison links;
   - `README.md`: the version badge.
2. Run `python3 scripts/validate.py` and `claude plugin validate --strict .`.
   `claude plugin tag --dry-run --force .` additionally confirms that
   `plugin.json` and the marketplace entry report the same version.
3. Merge the release pull request with the title `chore(release): vX.Y.Z`.
4. Tag the merge commit on an up-to-date `main` and publish the GitHub release
   with the matching changelog section as its notes:

   ```bash
   VERSION=1.1.0
   git switch main && git pull --ff-only
   git tag -a "v$VERSION" -m "AGEX v$VERSION"
   git push origin "v$VERSION"
   notes="$(mktemp)"
   awk -v v="$VERSION" 'index($0, "## [" v "]") == 1 {f=1; next} /^## \[/ || /^\[[^]]*\]: / {f=0} f' CHANGELOG.md > "$notes"
   gh release create "v$VERSION" --title "AGEX v$VERSION" --notes-file "$notes"
   ```

5. Verify the release: install the plugin from the marketplace and run the
   one-command installer against a temporary `CLAUDE_HOME`.

### Issue labels

The issue forms and Dependabot apply these labels, so keep them in the
repository's label list: `bug`, `triage`, `enhancement`, and `dependencies`.

## License

By contributing, you agree that your contributions are licensed under the
[MIT License](LICENSE) that covers this project.
