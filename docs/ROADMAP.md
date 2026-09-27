# AGEX v2.0 Roadmap: faster, provably reliable, more agents, better DX

> **Status:** planning. This roadmap lives on the `v2` branch, where v2.0 is being built. `main` stays on v1.0.0 until v2.0.0 ships, and each milestone below ends in a `v2.0.0-alpha.N` tag.

## Context

AGEX v1.0.0 (github.com/saksham-eng560/agex) shipped 12 agents, 8 commands, plugin + script installs, a validator, and green CI. The next step is **one big v2.0 release**. It targets all four of your priorities: faster/cheaper runs, provable reliability, more agents & commands (**dependency** + **release**), and a better developer experience. Evals run locally, plus in a manual, cost-capped CI job.

Three read-only investigations shaped this plan: Claude Code 2.1.283 capabilities checked against the docs and the local CLI, a gap audit of v1 with file:line evidence, and a survey of competing projects.

**What's wrong with v1 today:**
- **Rules depend on the model following instructions.** Only the Write/Edit denial is enforced by tools. Test-files-only, read-only Bash, cycle counting, the dispatch budget, and the artifact format are all just prompt text.
- **P0 bugs:**
  - The orchestrator subagent is told to ask the user, but it can't (`orchestrator.md:15` vs `:64`).
  - Nothing is saved to disk, so an interrupted run can't resume, and the orchestrator's context keeps growing.
  - The 15-dispatch cap is too small for COMPLEX tasks.
  - Parallel coders share one working tree and run tests mid-wave, which causes false failures.
  - SIMPLE code changes skip testing and review entirely.
- **Wasted work:**
  - Every agent re-detects the toolchain, and they disagree (`bun.lock` vs `bun.lockb`).
  - Tests run about 3 times per unit.
  - The planner and architect both break the work down.
  - The planner and researcher run one after another even though they're independent.
- **Drift:**
  - The protocol is copied into 13 files, and the copies already disagree.
  - Every agent is within 44 words of the 800-word cap.
  - `CLAUDE.md` @imports about 18k words into every contributor session.
- **No evidence it works:** there are no behavioral evals, and competitors are criticized for unverified quality and fake "success".

**Claude Code features v2 can use (confirmed):**
- **Plugin `workflows`**: JS orchestration that can't be skipped or reinterpreted.
- **Hooks that see which agent is calling.** PreToolUse includes `agent_type`, so hooks can enforce per-agent rules. SubagentStop can send an agent back to fix its artifact.
- **Agent settings**: `isolation: worktree` (the orchestrator must merge results back itself), `memory`, `maxTurns`, and `effort`.
- **Skills with supporting files**, which subagents can preload.
- **`userConfig`** options that users set per install.
- **`claude plugin eval`** for scoring quality.

## Core decisions

| # | Decision |
|---|---|
| A1 | **The main session runs the show.** `/agex` becomes a skill: it sets up the run, asks you questions directly, then launches the `/agex:run` workflow, or a prompt-driven fallback if workflows are turned off. `orchestrator.md` stays for headless use; there it writes `needs_input` to disk and stops, and `/agex-resume` continues. This fixes the P0 contradiction. |
| A2 | **Hooks save the run to disk.** SubagentStop writes each artifact to a file, PostToolUse on the Agent tool records cost, and SubagentStart injects the cached project profile. This works the same whether or not workflows are on, because workflow scripts can't touch files themselves. |
| A3 | **An append-only event log is the source of truth.** Each run's `ledger.jsonl` gets one short line per event, and `state.json` is rebuilt from it under a lock. Parallel agents can't overwrite each other. |
| A4 | **One protocol file.** `protocol/protocol.json` holds the roster, tools, models per tier, write rules, the 14 artifact schemas, enums, circuit-breaker limits, routing, and prices. `scripts/gen_protocol.py` generates agent frontmatter, marked regions in agents and docs, shared skills, and constants for the workflow script. CI fails if generated output is stale. JSON keeps everything dependency-free. |
| A5 | **Hook logic is stdlib Python 3.8+ behind a small `sh` wrapper.** It reuses `validate.py`'s shell parser (`parse_shell`, line 700). If `python3` is missing, AGEX agents are blocked under `enforcement=strict`, so rules never switch off silently. |
| A6 | **Commands become skills with the same names** (`skills/agex-*/SKILL.md`). `.claude/commands` is dropped from the plugin manifest. |
| A7 | **All v2 work happens on a `v2` branch**, with a tag at each milestone (`v2.0.0-alpha.N`, full CI green). `main` stays v1 until v2.0.0 ships, because the marketplace installs straight from `main`. M0 bug fixes can optionally be cherry-picked to `main` as v1.0.1. |

## Key formats

- **Run folder** `.agex/runs/<YYYYMMDD-HHMMSS-hex6>/`:
  - `state.json`: `schema_version`, `status` (planning / awaiting_approval / running / needs_input / done / partial / escalated / budget_exhausted / aborted), `resume` cursor, `git.base_sha`, and `units[]` (files, owner, wave, `cycles{test,review,merge}`, failure signatures, worktree info, artifacts). It also holds `budget{usd_cap, usd_est, dispatch_cap, dispatches}`, `questions[]`, `decisions[]`, and `escalations[]`.
  - `ledger.jsonl`, `task.md`, `artifacts/<seq>-<unit>-<agent>-<Type>[-c<cycle>].md`, `report.md`.
  - `.agex/events.log` replaces `session.log`. Paths are relative to the project, and paths outside it are dropped.
- **`.agex/project.json`**, built once by `scripts/agex_profile.py`:
  - `package_manager` and `commands{install, test, test_file, lint, typecheck, build, format}`.
  - Globs for test, source, doc, CI, and manifest files, plus `version_files`, `audit_tools`, and `default_branch`.
  - `sources{path: sha256}` so a stale profile can be detected.
  - `conventions` of at most 120 words, the only part the researcher fills in.
- **Artifact v2 envelope**: a marker line `<!-- agex:artifact type=X version=2 run=… unit=… agent=… status=… -->`, followed by a fenced `agex-evidence` JSON block:
  - `evidence[]`: each entry has `tool_use_id`, `cmd`, `exit`, `stdout_sha256`, and `summary`.
  - `files[]` with `sha256_after`, and `claims[]`.

  SubagentStop checks each piece of evidence against the agent's transcript and the files on disk. A mismatch sends the agent back to fix it, at most twice; after that the artifact is saved as `verified:false` and its status is downgraded. v1 artifacts can still be read.
- **Enforcement matrix** (lives in `protocol.json`): PreToolUse applies it, and a git-diff check after each agent catches anything that slipped past a timed-out hook.

  | Agent | May write | Command rules |
  |---|---|---|
  | Read-only agents | `.agex/runs/**` only | Allowlisted read-only commands only |
  | tester | Test globs only | Test commands only |
  | documenter | Doc globs (not CHANGELOG) | Read-only |
  | devops | CI and infrastructure globs | Remote-apply and push commands blocked |
  | dependency | Manifests and lockfiles | Package installs allowed |
  | release | CHANGELOG and version files | Tag, push, and publish blocked |

  For every agent, secrets can't be read. A file claimed by another agent in the same run can't be written. Once the budget is used up, every tool call is blocked. In the fallback path, each dispatch brief must carry the header `AGEX run= unit= loop= cycle=` and stay at 3 cycles or fewer.
- **Cost ledger**: estimated cost = tokens × the `protocol.json` price table × a calibration factor fitted from eval runs. It's a lower-bound estimate and always labeled "estimated". The hard stop leaves the run `budget_exhausted`, and `/agex-resume <id> --budget N` continues it.
- **`userConfig`**:

  | Option | Default | Choices / meaning |
  |---|---|---|
  | `tier` | balanced | economy / balanced / max |
  | `budget_usd` | 5 | Hard cost cap per run |
  | `max_dispatches` | 40 | Replaces the fixed 15 |
  | `enforcement` | strict | strict / warn / off |
  | `fanout` | auto | auto / off |
  | `plan_approval` | complex | complex / always / never |
  | `log_level` | events | off / events / verbose |
  | `retain_runs_days` | 30 | How long runs are kept |

- **Token footprint budgets**, measured by `scripts/footprint.py` and checked in CI:

  | What | Budget |
  |---|---|
  | Always loaded | ≤1.5k tokens (descriptions ≤40 words) |
  | Per dispatch | ≤1.8k tokens (agent bodies 250–550 words plus preloaded skills) |
  | `/agex` skill | ≤1.6k tokens |
  | Contributor `CLAUDE.md` | ≤1.6k tokens (@imports removed) |

## Milestones (each ends in an alpha tag with green CI)

**M0: Foundations, spikes, baseline**
- **Spikes first, recorded in `docs/dev/SPIKES.md`:**
  - S1: can a workflow's `agent()` pick an AGEX agent type, model, and isolation, and what `agent_type` do hooks see? Fallback: a courier agent.
  - S2: does `${user_config.tier}` work inside `model:`?
  - S3: how are the working directory and fixtures set up for `plugin eval`?
  - S4: how exactly does a SubagentStop block behave?
  - S5: can a plugin install be pinned to a git ref?
- **CI and tooling:**
  - Pin actions by commit SHA and pin Claude Code to 2.1.283.
  - Add ruff (via `pyproject.toml`), unittest (`tests/test_validate.py`), PSScriptAnalyzer, and footprint jobs.
  - Move the shell parser and frontmatter parser into `scripts/agexlib/`.
- **Installers:** add `--ref <tag>` to `install.sh` and `install.ps1`.
- **Logger fixes:**
  - Add `|| true` to the logger hooks only, never to enforcement hooks.
  - Add `NotebookEdit` to the matcher.
  - Log paths relative to the project.
- **Content fixes:**
  - Fix `bun.lock` vs `bun.lockb` across agents.
  - Fix the docs' claims about which model the orchestrator uses.
  - `/agex-status` reads models from the agent files instead of hard-coded values.
  - Remove the `CLAUDE.md` @imports.
- **Baseline:** seed 3 eval cases and record the v1 results in `evals/results/v1.0.0.json`.
- **Accept when:**
  - `validate.py` test coverage is ≥80%.
  - ruff, PSScriptAnalyzer, and shellcheck report nothing.
  - Every action is SHA-pinned.
  - The v1 baseline is committed.

**M1: Single protocol file, artifact v2, skills, less duplication** *(alpha.1)*
- **Protocol:** create `protocol/protocol.json` and `scripts/gen_protocol.py`.
- **Shared skills:** `skills/agex-protocol/SKILL.md` (envelope, statuses, evidence rules; ≤450 words) and `skills/agex-toolchain/SKILL.md` (how to use `project.json`).
- **Agents:**
  - Rewrite all agents to 250–550 words with `skills: [agex-protocol, agex-toolchain]`, a `maxTurns`, and an `effort`.
  - The planner owns decomposition, file ownership, and waves (Haiku → Sonnet). The architect only writes interfaces for units flagged `needs_design`.
- **Who runs tests:**
  - The coder runs only targeted checks.
  - The tester owns the full suite.
  - The reviewer reads the tester's evidence and never re-runs tests.
  - The tester only runs the debugger's regression test instead of rewriting it.
- **Commands:** convert the 8 commands to `skills/agex*/`.
- **Validator:** check that generated regions are fresh, word caps, description length, v2 markers and evidence blocks, and skill injection safety.
- **Docs:** move `HANDOFF-PROTOCOL.md` to v2, with generated tables.
- **Accept when:**
  - `gen_protocol --check` passes, and a hand edit to a generated region makes CI fail.
  - Protocol text is copied into zero files outside generated regions.
  - The per-dispatch footprint is ≤1.8k tokens.

**M2: Run engine and persistence** *(alpha.2, needs M1)*
- **Scripts:**
  - `scripts/agex_run.py` with subcommands `init`, `event`, `state`, `claim`, `merge`, `cleanup`, `list`, `show`, `replay`, and `prune`.
  - `scripts/agex_profile.py`.
- **Hooks:** a `hooks/scripts/agex-hook.sh` wrapper plus `agex_hook.py`, registered for SubagentStart, SubagentStop, and PostToolUse on the Agent tool.
- **Skills:**
  - `skills/agex/SKILL.md` is the conductor. It classifies each run as fast, standard, or complex. The fast path always runs the tester plus a light reviewer, in parallel.
  - `skills/agex/fallback.md` is the prompt-driven engine used when workflows are off.
  - New skills `/agex-init`, `/agex-runs`, and `/agex-resume`; `/agex-status` is rebuilt on top of `state.json`.
- **Scheduling:** the planner and researcher now run in parallel.
- **Accept when:**
  - A killed session resumes without redoing any finished unit.
  - Every artifact is on disk.
  - The main session's context stays ≤8k tokens on a standard run.
  - Replay reproduces the run's timeline exactly.

**M3: Enforcement hooks** *(alpha.3, needs M2)*
- **PreToolUse rules** cover Write, Edit, MultiEdit, NotebookEdit, Bash, Read, and Agent according to the matrix. They also enforce the budget stop and file claims.
- **Checks after each agent:** SubagentStop verifies the evidence and compares the git diff against the agent's allowed globs.
- **Tests:** recorded hook payloads in `tests/hooks/fixtures/*.json` plus `tests/test_hooks.py`, and a speed test (p95 <150 ms; hook timeout 5 s).
- **Accept when:**
  - Every row of the matrix has an allow test and a deny test that pass on Linux, macOS, and Windows (Git Bash).
  - Faked evidence is blocked.
  - A 4th cycle is blocked.
  - Going over budget ends the run as `budget_exhausted`.
  - `warn` mode logs without blocking.

**M4: Workflows** *(alpha.4, needs M2+M3 and spike S1)*
- **`workflows/run.js`** runs these phases in order:
  1. Build the project profile.
  2. Research and planning in parallel.
  3. An approval gate.
  4. For each wave: coders in parallel, then merge, one tester run for the wave, and parallel reviews.
  5. Circuit breakers written as code: 3 cycles, a repeated-failure check, and one merge retry.
  6. Docs.
  7. The final report.

  Every `agent()` call returns structured output that matches a schema.
- **Worktree fan-out** happens only when `fanout=auto`, the git tree is clean, and a wave has more than one unit with separate files. It uses `isolation: worktree` with the base set to the current `HEAD`. Merges happen in unit order; on a conflict, the merge is aborted and that unit is redone serially.
- **Tests:** `tests/workflows/run.test.mjs` runs `run.js` in `node:vm` with a stubbed `agent()`.
- **Accept when:**
  - The simulation tests cover 100% of the breaker and branch paths.
  - COMPLEX runs take ≤75% of v1's wall-clock time.
  - There are no false test failures mid-wave.
  - The eval suite still passes with `CLAUDE_CODE_DISABLE_WORKFLOWS=1`.

**M5: New agents and commands** *(alpha.5, needs M1+M3; can run in parallel with M4)*
- **`.claude/agents/dependency.md`** produces a **DependencyReport**: current → target version with the semver class, breaking changes from changelog URLs, CVEs from the audit tools, and an upgrade / hold / pin decision with evidence.
- **`.claude/agents/release.md`** produces a **ReleasePlan**:
  - It proposes the next version from the commits since the last tag.
  - It edits the CHANGELOG, version files, and release notes.
  - It runs preflight checks.
  - It lists the exact tag and publish commands for a human to run. Hooks block the agent from running them itself.
- **New skills:**
  - `/agex-deps` (dependency → tester → reviewer, plus security when there are CVEs)
  - `/agex-release`
  - `/agex-fix` (debugger → tester)
  - `/agex-refactor`
  - `/agex-design`
  - `/agex-ci`
  - `/agex-doctor` (via `scripts/agex_doctor.py`): checks versions, whether hooks and workflows are live, config, profile freshness, orphaned worktrees and runs, and memory size; also self-scans AGEX by comparing installed file hashes.
- **Memory:** `memory: local` for the reviewer, debugger, and researcher.
- **Accept when:**
  - There are 14 agents and 18 skills, all generated.
  - Each new agent has ≥2 eval cases.
  - The always-loaded footprint is still ≤1.5k tokens.

**M6: Evals and CI** *(alpha.6, needs M4+M5)*
- **Cases:** about 14 in `evals/<case>/prompt.md` + `graders/`:
  - fast-path bug fix
  - tester writes only test files
  - reviewer stays read-only
  - devops never deploys
  - ambiguous task escalates
  - artifact v2 format
  - planted secret is found
  - resume
  - budget stop
  - dependency CVE
  - release notes
  - workflow-disabled fallback
- **Grading:** deterministic graders first, and an LLM judge (2 of 3 votes) only for prose. Every case also runs without the plugin as a baseline, and flaky cases go to `evals/QUARANTINE`.
- **CI:** `.github/workflows/evals.yml` is **manual only** (`workflow_dispatch`). Inputs are `cases` (default: the 4 smoke cases), `runs` (1–3), and `max_cost` (default $5, hard cap $20). It uses a protected `evals` environment holding `ANTHROPIC_API_KEY` and a 30-minute timeout, and uploads `results.json`.
- **Docs:** `docs/EVALS.md`.
- **Accept when:**
  - The full local suite scores ≥0.8 for ≤$15.
  - SIMPLE-task median cost is ≤60% of v1.
  - Test runs per unit are ≤1.3.
  - v2 beats both the v1 baseline and the no-plugin baseline.

**M7: Docs, migration, release** *(v2.0.0)*
- **Docs:** rewrite ARCHITECTURE, QUICKSTART, and CUSTOMIZATION (custom agents go in `protocol.json`), mostly generate AGENTS, and trim the FAQ.
- **New `docs/MIGRATION.md`.**
- **README:** add tables of eval scores and token footprint.
- **Release:** bump to 2.0.0 everywhere. **The CHANGELOG is prepared by AGEX's own `release` agent, and you tag and publish.**
- **Accept when:** links are clean, and QUICKSTART works on clean macOS, Linux, and Windows.

## Breaking changes (spelled out in `docs/MIGRATION.md`)

| Change | What users need to do |
|---|---|
| `/agex` now runs in your session and uses its model (not Opus) | Choose a model with `/model` if needed. |
| Commands are now skills (same names) | Plugin users: nothing. Script installs: `install.sh` migrates them, with a backup. |
| Artifacts use marker `version=2` | Custom agents need the evidence block to get a verified PASS. |
| `session.log` is replaced by `runs/` and `events.log` | Use `/agex-runs`. Old logs are left alone. |
| Hooks now block what v1 only discouraged | Set `enforcement=warn` while adjusting. |
| Planner uses Sonnet; the 15-dispatch cap is replaced by a cost budget | Use `tier=economy` or set `budget_usd`. |
| Agent files are generated | Put customizations in `protocol.json` or outside the generated regions. |
| Enforcement needs Python 3.8+ | `/agex-doctor` checks for it. |

v1 stays installable with `install.sh --ref v1.0.0`.

## Top risks and how the plan handles them

| Risk | Handling |
|---|---|
| A PreToolUse hook that times out lets the action through | Hooks are fast (<150 ms) with no network or git calls, and the post-agent diff check catches anything missed. |
| Spike S1 fails | Use a courier agent, and enforce via the brief header. |
| Workflows are turned off | A fallback engine with the same limits and its own eval cases. |
| Worktree merge conflicts | Fan out only on a clean tree with separate files; abort the merge and redo the unit serially. |
| SubagentStop keeps blocking in a loop | At most 2 blocks, then save as unverified. |
| Eval costs and flaky results | Deterministic graders, majority of 3 votes, a quarantine list, and two separate cost caps. |
| Solo workload | Spikes come first, and every milestone is tagged. If time runs short, drop worktree fan-out or memory, **but not evals or enforcement**. |

## Suggested order (solo, about 16–18 part-time weeks)

| Weeks | Work |
|---|---|
| 1–2 | M0, with the spikes on days 1–2 |
| 3–4 | M1: protocol and generator first, then rewrite agents two at a time |
| 5–7 | M2 |
| 8–9 | M3, writing the fixture tests before the hook code |
| 10–12 | M4, with the simulation tests alongside |
| 13–14 | M5, with the release agent first |
| 15–16 | M6 |
| 17–18 | M7 |

## Critical files

- `scripts/validate.py`: extract `agexlib`, add the generated/v2/footprint checks.
- `.claude/agents/orchestrator.md`: its logic moves into `skills/agex/SKILL.md` and `workflows/run.js`.
- `hooks/agex-hooks.json` and `hooks/scripts/`: they become the persistence and enforcement layer.
- `.claude-plugin/plugin.json`: add `userConfig` and `workflows`, drop `commands`, bump the version.
- `docs/HANDOFF-PROTOCOL.md`: the v2 envelope, with generated tables.
- `.github/workflows/ci.yml`: new jobs, plus a new `evals.yml`.
- New: `protocol/protocol.json`, `scripts/{gen_protocol,agex_run,agex_profile,agex_hook,agex_doctor,footprint}.py`, `workflows/run.js`, `skills/**`, `evals/**`, `tests/**`.

## Verification (end to end, for v2.0 done)

1. **Static checks:** `python3 scripts/gen_protocol.py --check`, `python3 scripts/validate.py`, `python3 -m unittest`, ruff, shellcheck, PSScriptAnalyzer, and `claude plugin validate --strict .` are all green on the pinned CLI in CI (Linux, macOS, Windows).
2. **Hook tests:** fixture tests pass for every enforcement row, and the hook p95 is under 150 ms.
3. **Workflow simulation:** `node --test tests/workflows/` passes.
4. **Local evals:** `claude plugin eval . --json results.json --threshold 0.8 --max-cost-usd 15` passes, both normally and with `CLAUDE_CODE_DISABLE_WORKFLOWS=1`. Results are compared to the v1 and no-plugin baselines.
5. **Manual smoke test:** in a sample repo, run `/agex-init`, then `/agex <small bug>` (fast path, tested and reviewed). Then run a COMPLEX task with fan-out, kill the session, and `/agex-resume` it. Then run `/agex-deps` and `/agex-release` (the tag command is blocked), and `/agex-doctor`.
6. **Footprint:** `scripts/footprint.py` reports within all budgets.
7. **Upgrade and rollback:** install.sh upgrades a v1 install cleanly, and `--ref v1.0.0` rolls it back.
