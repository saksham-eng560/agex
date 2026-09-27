# Security Policy

AGEX is a set of prompts, slash commands, hook scripts, and installers that run
inside Claude Code on your machine. Because agents can read your code and run
shell commands, we treat security reports seriously and appreciate responsible
disclosure.

## Supported Versions

Security fixes are released for the latest minor release of the current major
version. Update to the newest 1.x release before reporting, if you can.

| Version | Supported |
|---|---|
| 1.x | Yes |
| < 1.0 | No |

## Reporting a Vulnerability

**Do not open a public issue, pull request, or discussion for a security
problem.** Public reports put every AGEX user at risk before a fix exists.

Report privately through GitHub private vulnerability reporting:

**[https://github.com/saksham-eng560/agex/security/advisories/new](https://github.com/saksham-eng560/agex/security/advisories/new)**

Only you and the repository maintainers can see the report. If you cannot use
private vulnerability reporting, contact the maintainer
[@saksham-eng560](https://github.com/saksham-eng560) on GitHub and ask for a
private channel without sharing any vulnerability details publicly.

### What to Include

A good report lets us reproduce the problem without guessing. Please include:

- **Summary**: the vulnerability class (for example command injection, prompt
  injection, permission escalation, path traversal) and the affected file, such
  as `install.sh`, `hooks/scripts/agex-log.sh`, or `.claude/agents/reviewer.md`.
- **Versions**: the AGEX version or commit, the Claude Code version
  (`claude --version`), your operating system, and your install method (plugin,
  `install.sh`, `install.ps1`, or manual clone).
- **Reproduction steps**: exact commands, prompts, or repository contents that
  trigger the issue, starting from a clean install.
- **Impact**: what an attacker gains, such as running commands, writing files
  outside the project, reading secrets, or bypassing a confirmation step.
- **Proof of concept**: a minimal repository, file, or transcript excerpt.
  Redact any real secrets, tokens, or private code.
- **Suggested fix** (optional): a patch or mitigation idea.

## Response Targets

AGEX is maintained by volunteers. These are targets we work toward, not
contractual guarantees.

| Stage | Target |
|---|---|
| Acknowledgement of your report | Within 3 business days |
| Triage: confirmed or declined, with a severity rating | Within 7 business days |
| Fix or mitigation for CRITICAL severity | Within 7 days of triage |
| Fix or mitigation for HIGH severity | Within 30 days of triage |
| Fix or mitigation for MEDIUM severity | Within 90 days of triage |
| Fix for LOW severity | In a regular release |

After a fix is released we publish a GitHub Security Advisory that describes
the issue, the affected versions, and the upgrade path. We credit reporters who
want to be credited. Please keep the details private until the advisory is
published, or for 90 days after your report, whichever comes first; if we need
more time we will explain why and agree on a date with you.

## Scope

In scope:

- **Install scripts** (`install.sh`, `install.ps1`): command injection, unsafe
  handling of paths or environment overrides (`AGEX_HOME`, `AGEX_REPO`,
  `CLAUDE_HOME`), symlinks or copies written outside the target directories,
  mishandling of the install manifest (`.agex-manifest`) or `--force` backups
  (`.agex-backup/`), and `--uninstall` / `-Uninstall` removing files that AGEX
  did not create.
- **Hook scripts and hook configuration** (`hooks/scripts/agex-log.sh`,
  `hooks/agex-hooks.json`, `.claude/settings.json`): shell injection through
  crafted hook payloads or file paths, log injection, writes outside
  `<project>/.agex/`, or a hook that can block or fail a session.
- **Agent and command prompts** (`.claude/agents/*.md`, `.claude/commands/*.md`):
  - prompt injection, where content in a repository, web page, or tool output
    reliably makes an AGEX agent ignore its Hard Constraints;
  - permission escalation, such as a read-only agent modifying files through
    Bash, the devops agent running a remote or irreversible operation without
    human confirmation, or an agent granted tools beyond its documented role;
  - slash-command `!` injections that are not read-only, that can fail in a way
    that runs something unintended, or that print the contents of secret files
    into the conversation.
- **Plugin manifests** (`.claude-plugin/plugin.json`,
  `.claude-plugin/marketplace.json`): entries that load components from
  unexpected paths or sources.
- **Repository tooling** (`scripts/validate.py`, `.github/workflows/`): issues
  that could let a malicious pull request run code with repository privileges.

Out of scope:

- Vulnerabilities in Claude Code itself, in Claude models, or in Anthropic
  services. Report those to Anthropic through the security policy published in
  the Claude Code repository.
- Generic model jailbreaks that do not depend on AGEX prompts, commands, or
  scripts.
- Missed findings or false positives from the `security` or `reviewer` agents.
  Those are quality bugs; please open a regular bug report.
- Vulnerabilities in the projects you run AGEX on, or in their dependencies.
- Attacks that require an already compromised machine or user account.

## Security Model and Known Limitations

AGEX runs with the permissions of your Claude Code session. It adds no
sandbox, no daemon, and no telemetry. Understand these properties before you
run it on sensitive code:

1. **Read-only agents are enforced at the tool level for Write and Edit only.**
   `researcher`, `reviewer`, and `security` have `Write` and `Edit` in
   `disallowedTools`, and `architect` and `planner` are granted only `Read`,
   `Grep`, and `Glob`. However, `researcher`, `reviewer`, and `security` keep
   `Bash` so they can inspect the project (run tests, `git log`, dependency
   audits). Their prompts forbid redirects, installs, and git state changes,
   but that restriction is a prompt instruction, not a sandbox. Your Claude Code
   permission rules are the real enforcement boundary for Bash.
2. **Plugin subagents ignore `hooks`, `mcpServers`, and `permissionMode`
   frontmatter.** AGEX agents do not use these fields, so an AGEX agent cannot
   grant itself extra permissions through frontmatter, and you cannot rely on
   those fields to restrict an agent loaded from a plugin either.
3. **Hooks run local shell commands.** In plugin installs and inside the AGEX
   repository, Claude Code runs `hooks/scripts/agex-log.sh` at every session
   start and after every `Write`, `Edit`, or `MultiEdit` tool call. The script
   appends only event names, tool names, and file paths (never file contents)
   to `<project>/.agex/session.log`, creates `<project>/.agex/.gitignore` so the
   log is never committed, rotates the log at 1 MiB, and always exits 0. Read
   the script before enabling it, and set `AGEX_DISABLE_LOG=1` to turn logging
   off.
4. **Symlink installs do not include hooks.** `install.sh` and `install.ps1`
   link agents and commands only (`install.ps1` copies them when Windows does
   not permit symbolic links), and never edit your `settings.json`. Session logging is active in plugin installs
   and inside the AGEX repository; symlink users can add the hooks manually as
   described in [docs/CUSTOMIZATION.md](docs/CUSTOMIZATION.md).
5. **Piping a script to a shell runs remote code.** The one-line installers
   (`curl ... | bash` and `irm ... | iex`) execute whatever the `main` branch
   contains at that moment. If you prefer to review first:

   ```bash
   git clone https://github.com/saksham-eng560/agex.git ~/.agex
   less ~/.agex/install.sh
   cd ~/.agex && ./install.sh --no-update
   ```

   `--no-update` links exactly the commit you reviewed instead of pulling first.

6. **Slash-command injections are read-only by design.** The `` !`command` ``
   lines in `.claude/commands/` run before the model sees the prompt. They are
   limited to `git status`, `git ls-files`, `git diff`, `git log`, `grep`,
   `head`, `tail`, `ls`, `echo`, and `wc`, each scoped by the command's
   `allowed-tools`, and they never use `find`, `cat`, `xargs`, `sh -c`, or
   redirects to files. `/agex-secure` lists environment file names only, never
   their contents. The output of these injections (diffs, file listings, the
   first lines of files) becomes part of the conversation, just like any file
   Claude Code reads.
7. **Agents never receive secrets intentionally.** No AGEX prompt or command
   asks for credentials or reads `.env` contents, and the `security` agent
   redacts any secret it finds to its first 4 characters followed by `****`.
   Agents with `Read` can still open any file your permission rules allow, so
   deny access to secret files explicitly (see below).
8. **The devops agent requires human confirmation for remote operations.** It
   verifies changes locally and then stops with status
   `READY_FOR_CONFIRMATION`, listing every remote or irreversible action (pushes,
   tags, container pushes, deployments, infrastructure changes) with its exact
   command instead of running it. This is a prompt-level rule, so keep Claude
   Code's permission prompts enabled for those commands as a second barrier.
9. **Network access comes from Claude Code tools.** AGEX contains no network
   code of its own apart from the installers cloning or updating the repository
   from GitHub. The `researcher` agent can use Claude Code's `WebSearch` and
   `WebFetch` tools, so fetched web content can reach the conversation and is a
   potential prompt-injection source.

## Safe Usage Recommendations

- **Review every diff.** Treat AGEX output like a pull request from a new
  contributor: read `git diff` before you commit, and never let an agent push
  on your behalf without looking.
- **Use Claude Code permission rules.** Deny reads of secret files and require
  confirmation for remote operations, for example in `.claude/settings.json`
  or `~/.claude/settings.json`:

  ```json
  {
    "permissions": {
      "deny": [
        "Read(./.env)",
        "Read(./.env.*)",
        "Read(./secrets/**)"
      ],
      "ask": [
        "Bash(git push *)",
        "Bash(docker push *)",
        "Bash(kubectl *)",
        "Bash(terraform apply *)"
      ]
    }
  }
  ```

- **Run untrusted repositories in a sandbox.** AGEX agents read project files,
  and a malicious README, code comment, or test fixture can contain prompt
  injection. Open untrusted code in a container, virtual machine, or dev
  container with no production credentials, and do not combine it with
  `--dangerously-skip-permissions`.
- **Keep secrets out of the working tree.** Use environment variables or a
  secret manager, keep `.env` files git-ignored, and rotate any credential that
  an agent or log may have exposed.
- **Review updates before you take them.** Script installs track the `main`
  branch. Run `git -C ~/.agex fetch` and read the incoming changes with
  `git -C ~/.agex log -p HEAD..origin/main`, then update; pass `--no-update`
  (`-NoUpdate` on Windows) to re-run the installer without pulling.
- **Turn off logging when paths are sensitive.** Set `AGEX_DISABLE_LOG=1` in the
  environment that launches Claude Code.
