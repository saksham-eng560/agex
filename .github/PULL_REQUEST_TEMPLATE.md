## Summary

<!-- What does this pull request change, and why? Keep the title in Conventional Commits form, for example "fix(hooks): keep file paths with spaces on one log line". -->

## Type of Change

- [ ] Bug fix (non-breaking change that fixes an issue)
- [ ] New feature (non-breaking change that adds functionality)
- [ ] New or changed agent
- [ ] New or changed slash command
- [ ] Breaking change (renames or removes an agent, command, or installer flag, or changes an artifact schema)
- [ ] Installer or hook change
- [ ] Documentation only
- [ ] CI, tooling, or repository configuration

## Related Issue

<!-- Link the issue this pull request resolves, for example "Closes #42". Large changes should be discussed in an issue first. -->

## Checklist

- [ ] `python3 scripts/validate.py` passes
- [ ] `claude plugin validate --strict .` passes
- [ ] Every agent body I added or changed is 300 to 800 words (orchestrator 600 to 800)
- [ ] Docs, README tables and badges, `CLAUDE.md`, and `.claude-plugin/plugin.json` are updated for any added, renamed, or removed agent or command
- [ ] Artifact templates match `docs/HANDOFF-PROTOCOL.md` exactly (headings, field names, status enums)
- [ ] Slash-command `!` injections follow the read-only rules in [CONTRIBUTING.md](https://github.com/saksham-eng560/agex/blob/main/CONTRIBUTING.md#shell-injection-safety-rules)
- [ ] `CHANGELOG.md` is updated under `## [Unreleased]`
- [ ] If `install.sh` or `install.ps1` changed: install and uninstall were tested against a temporary `CLAUDE_HOME`
- [ ] No secrets, email addresses, placeholders, or emojis outside the places the style guide allows

## Testing Notes

<!-- How did you verify this change? List the commands you ran and their results. For prompt changes, describe the task you ran before and after the change, which agents were deployed, and what improved. -->
