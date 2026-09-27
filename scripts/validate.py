#!/usr/bin/env python3
"""Validate the AGEX repository against its build rules.

Usage:
    python3 scripts/validate.py              # full report
    python3 scripts/validate.py --quiet      # errors only
    python3 scripts/validate.py --root DIR   # validate another checkout

The validator uses only the Python 3.8+ standard library and never modifies a
file. It runs ten groups of checks, prints PASS or FAIL for each group followed
by the problems it found, and exits with status 1 when any error was found.
Warnings are printed for review but never change the exit status.

The expected agent roster, artifact schemas, and command list below mirror
CLAUDE.md. Adding, renaming, or removing an agent or command means updating
them here in the same change (see "Adding or renaming an agent or command" in
CLAUDE.md).
"""

from __future__ import annotations

import argparse
import json
import os
import posixpath
import re
import subprocess
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Callable, Dict, Iterable, List, Optional, Sequence, Set, Tuple, Union
from urllib.parse import unquote

# ---------------------------------------------------------------------------
# Expected repository contents
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class AgentSpec:
    """Expected frontmatter values and output artifact of one AGEX agent."""

    model: str
    color: str
    tools: Tuple[str, ...]
    disallowed_tools: Tuple[str, ...]
    artifact: str
    read_only: bool


_READ_ONLY_TOOLS = ("Read", "Grep", "Glob")
_WRITE_TOOLS = ("Read", "Write", "Edit", "Bash", "Grep", "Glob")
_INSPECT_TOOLS = ("Read", "Grep", "Glob", "Bash")
_DENY_EDITS = ("Write", "Edit")

AGENT_ROSTER: Dict[str, AgentSpec] = {
    "orchestrator": AgentSpec("opus", "purple", ("Agent", "Read", "Grep", "Glob", "Bash"), (), "AgexReport", False),
    "researcher": AgentSpec(
        "sonnet", "cyan", ("Read", "Grep", "Glob", "WebSearch", "WebFetch", "Bash"), _DENY_EDITS, "ResearchBrief", True
    ),
    "architect": AgentSpec("sonnet", "blue", _READ_ONLY_TOOLS, (), "TechnicalRFC", True),
    "coder": AgentSpec("sonnet", "green", _WRITE_TOOLS, (), "CodeDiff", False),
    "reviewer": AgentSpec("sonnet", "red", _INSPECT_TOOLS, _DENY_EDITS, "ReviewVerdict", True),
    "tester": AgentSpec("sonnet", "yellow", _WRITE_TOOLS, (), "TestReport", False),
    "debugger": AgentSpec("sonnet", "orange", _WRITE_TOOLS, (), "DebugReport", False),
    "documenter": AgentSpec("haiku", "pink", ("Read", "Write", "Edit", "Grep", "Glob"), (), "DocUpdate", False),
    "devops": AgentSpec("sonnet", "cyan", _WRITE_TOOLS, (), "DevOpsChange", False),
    "refactor": AgentSpec("sonnet", "green", _WRITE_TOOLS, (), "RefactorReport", False),
    "security": AgentSpec("sonnet", "red", _INSPECT_TOOLS, _DENY_EDITS, "SecurityAuditReport", True),
    "planner": AgentSpec("haiku", "blue", _READ_ONLY_TOOLS, (), "TaskPlan", True),
}

DEFAULT_BODY_WORDS = (300, 800)
BODY_WORDS_BY_AGENT: Dict[str, Tuple[int, int]] = {"orchestrator": (600, 800)}

AGENT_FIELD_ORDER = ("name", "description", "tools", "disallowedTools", "model", "color")
AGENT_REQUIRED_FIELDS = ("name", "description", "tools", "model")
# Claude Code ignores these for plugin subagents, so AGEX agents never use them.
AGENT_IGNORED_FIELDS = ("hooks", "mcpServers", "permissionMode")

KNOWN_TOOLS = frozenset(
    {
        "Agent", "Read", "Write", "Edit", "MultiEdit", "Bash", "Grep", "Glob",
        "WebSearch", "WebFetch", "NotebookEdit", "TodoWrite", "Skill",
    }
)
EDITING_TOOLS = frozenset({"Write", "Edit", "MultiEdit", "NotebookEdit"})
MODEL_ALIASES = frozenset({"opus", "sonnet", "haiku", "fable", "inherit"})
AGENT_COLORS = frozenset({"red", "blue", "green", "yellow", "purple", "orange", "pink", "cyan"})

AGENT_REQUIRED_SECTIONS = (
    "Your Place in the AGEX Pipeline",
    "Operating Procedure",
    "Hard Constraints",
    "Output Format",
)
MIN_NEVER_BULLETS = 4


@dataclass(frozen=True)
class ArtifactSpec:
    """Canonical schema of one handoff artifact (status enum and ### sections)."""

    statuses: Tuple[str, ...]
    sections: Tuple[str, ...]
    confidence_optional: bool = False


ARTIFACTS: Dict[str, ArtifactSpec] = {
    "TaskPlan": ArtifactSpec(
        ("READY", "NEEDS_INPUT"),
        ("Goal", "Assumptions", "Steps", "Execution Waves", "Risks & Mitigations", "Open Questions"),
    ),
    "ResearchBrief": ArtifactSpec(
        ("COMPLETE", "PARTIAL", "BLOCKED"),
        (
            "Problem Summary", "Affected Files", "External Documentation",
            "Dependencies", "Constraints & Risks", "Open Questions",
        ),
    ),
    "TechnicalRFC": ArtifactSpec(
        ("PROPOSED", "NEEDS_INPUT"),
        (
            "Context & Goals", "Non-Goals", "Component Architecture", "Data Flow",
            "Interface & Type Definitions", "Implementation Sequence", "Test Requirements",
            "Alternatives Considered & Risks",
        ),
    ),
    "CodeDiff": ArtifactSpec(
        ("IMPLEMENTED", "PARTIAL", "BLOCKED"),
        (
            "Summary", "Work Units Implemented", "Files Changed", "Verification",
            "Deviations from RFC", "Notes for Tester & Reviewer",
        ),
        confidence_optional=True,
    ),
    "TestReport": ArtifactSpec(
        ("PASS", "FAIL", "ERROR"),
        (
            "Test Suites Executed", "Pass/Fail Summary", "Tests Added or Updated", "Edge Cases Covered",
            "Failure Traces", "Coverage", "Recommendation for Coder",
        ),
        confidence_optional=True,
    ),
    "ReviewVerdict": ArtifactSpec(
        ("APPROVED", "CHANGES_REQUESTED", "BLOCKED"),
        ("Summary", "Issues", "Checks Performed", "What Is Good"),
    ),
    "DebugReport": ArtifactSpec(
        ("FIXED", "NOT_REPRODUCED", "NEEDS_ESCALATION"),
        (
            "Symptom", "Reproduction", "Isolation", "Root Cause",
            "Fix Applied", "Verification", "Regression Risk",
        ),
    ),
    "SecurityAuditReport": ArtifactSpec(
        ("PASS", "FINDINGS", "CRITICAL_FINDINGS"),
        ("Scope", "Risk Matrix", "Secrets Scan", "Dependency Audit", "Configuration Review", "Summary"),
    ),
    "RefactorReport": ArtifactSpec(
        ("COMPLETE", "PARTIAL", "ABORTED"),
        (
            "Smells Identified", "Refactorings Applied", "Test Baseline",
            "Test Result After", "Behavior Change", "Follow-ups",
        ),
    ),
    "DocUpdate": ArtifactSpec(
        ("COMPLETE", "PARTIAL"),
        ("Files Created or Updated", "Summary of Changes", "Examples Added", "Preserved Content", "Follow-ups"),
    ),
    "DevOpsChange": ArtifactSpec(
        ("READY_FOR_CONFIRMATION", "APPLIED_LOCALLY", "BLOCKED"),
        (
            "Summary", "Files Changed", "Local Verification", "Human Confirmation Required",
            "Rollback Plan", "Secrets & Environment Requirements",
        ),
    ),
    "AgexReport": ArtifactSpec(
        ("DONE", "PARTIAL", "ESCALATED"),
        (
            "Task", "Outcome", "Agents Deployed", "Changes",
            "Verification Evidence", "Open Issues & Escalations", "Next Steps",
        ),
    ),
}
CONFIDENCE_ENUM = ("HIGH", "MEDIUM", "LOW")

COMMANDS = (
    "agex", "agex-plan", "agex-status", "agex-research",
    "agex-review", "agex-test", "agex-secure", "agex-docs",
)
COMMANDS_REQUIRING_ARGUMENTS = ("agex", "agex-plan", "agex-research", "agex-docs", "agex-test")
COMMAND_AGENTS: Dict[str, str] = {
    "agex-plan": "planner",
    "agex-research": "researcher",
    "agex-review": "reviewer",
    "agex-test": "tester",
    "agex-secure": "security",
    "agex-docs": "documenter",
}
# Other files whose `!` injections run verbatim once a user copies them.
EXTRA_INJECTION_FILES = ("templates/custom-command.md",)

# The only programs a slash-command `!` injection may run.
INJECTION_PROGRAMS = (
    "git status", "git ls-files", "git diff", "git log",
    "grep", "head", "tail", "ls", "echo", "wc",
)
FORBIDDEN_PROGRAMS: Dict[str, str] = {
    "find": "'find' can -delete and -exec; list files with 'git ls-files --cached --others --exclude-standard'",
    "cat": "'cat' prints whole files; use 'head -N <file>'",
}
# Programs that exit 0 when they end a pipeline reading standard input.
PIPELINE_SINKS = ("head", "tail", "wc")

REQUIRED_FILES: Tuple[str, ...] = (
    tuple(f".claude/agents/{name}.md" for name in AGENT_ROSTER)
    + tuple(f".claude/commands/{name}.md" for name in COMMANDS)
    + (
        ".claude/settings.json",
        ".claude-plugin/plugin.json",
        ".claude-plugin/marketplace.json",
        "hooks/agex-hooks.json",
        "hooks/scripts/agex-log.sh",
        "scripts/validate.py",
        ".github/ISSUE_TEMPLATE/bug_report.yml",
        ".github/ISSUE_TEMPLATE/feature_request.yml",
        ".github/ISSUE_TEMPLATE/config.yml",
        ".github/PULL_REQUEST_TEMPLATE.md",
        ".github/workflows/ci.yml",
        ".github/CODEOWNERS",
        ".github/dependabot.yml",
        "CLAUDE.md",
        "README.md",
        "LICENSE",
        "CONTRIBUTING.md",
        "CODE_OF_CONDUCT.md",
        "SECURITY.md",
        "CHANGELOG.md",
        ".gitignore",
        ".gitattributes",
        ".editorconfig",
        "install.sh",
        "install.ps1",
    )
    + tuple(
        f"docs/{name}.md"
        for name in ("ARCHITECTURE", "AGENTS", "QUICKSTART", "CUSTOMIZATION", "HANDOFF-PROTOCOL", "EXAMPLES", "FAQ")
    )
    + tuple(
        f"examples/{name}/task.md"
        for name in ("web-app-build", "bug-fix", "code-review", "full-project", "security-audit")
    )
    + ("templates/custom-agent.md", "templates/custom-command.md")
)

HOOK_SCRIPT = "hooks/scripts/agex-log.sh"
PLUGIN_HOOKS_FILE = "hooks/agex-hooks.json"
PROJECT_SETTINGS_FILE = ".claude/settings.json"
THIS_FILE = "scripts/validate.py"

# Directories never scanned when the file list comes from walking the tree.
SKIPPED_DIRS = frozenset({".git", ".agex", "node_modules", "__pycache__", ".venv", "venv"})

# ---------------------------------------------------------------------------
# Patterns
# ---------------------------------------------------------------------------

SEMVER_RE = re.compile(
    r"^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$"
)
KEBAB_RE = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
EMAIL_RE = re.compile(r"[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}\b")
PLACEHOLDER_PATTERNS: Tuple[Tuple[str, "re.Pattern[str]"], ...] = (
    ("TODO:", re.compile(r"TODO:")),
    ("TBD", re.compile(r"\bTBD\b")),
    ("FIXME", re.compile(r"FIXME")),
    ("lorem ipsum", re.compile(r"lorem ipsum", re.IGNORECASE)),
    ("add content here", re.compile(r"add content here", re.IGNORECASE)),
    # A bare USERNAME placeholder; environment variables such as $env:USERNAME,
    # %USERNAME%, ${USERNAME} and identifiers such as USERNAME_TAKEN are fine.
    ("USERNAME", re.compile(r"(?<![\w$%:{])USERNAME(?![\w%}])")),
    ("your-username", re.compile(r"your-username", re.IGNORECASE)),
)
EMOJI_RANGES: Tuple[Tuple[int, int], ...] = (
    (0x1F000, 0x1FAFF),  # pictographs, emoticons, transport, supplemental symbols
    (0x2600, 0x27BF),  # miscellaneous symbols and dingbats
    (0x231A, 0x231B),
    (0x23E9, 0x23F3),
    (0x23F8, 0x23FA),
    (0x2B50, 0x2B50),
    (0x2B55, 0x2B55),
    (0xFE0F, 0xFE0F),  # emoji presentation selector
)

FRONTMATTER_KEY_RE = re.compile(r"^([A-Za-z_][\w-]*):(?:[ \t]+(.*))?$")
FENCE_OPEN_RE = re.compile(r"^[ \t]*(`{3,}|~{3,})(.*)$")
HEADING_RE = re.compile(r"^ {0,3}(#{1,6})[ \t]+(.+?)(?:[ \t]+#+)?[ \t]*$")
NEVER_BULLET_RE = re.compile(r"^\s*[-*+][ \t]+\*\*NEVER\*\*")
INJECTION_RE = re.compile(r"(?:(?<=\s)|^)!`([^`]+)`")
TOOL_PATTERN_RE = re.compile(r"([A-Za-z_][\w-]*)(?:\(([^)]*)\))?")
INLINE_LINK_RE = re.compile(r"\]\(\s*(<[^>\n]*>|[^)\s]+)")
REFERENCE_LINK_RE = re.compile(r"^ {0,3}\[[^\]]+\]:[ \t]*(<[^>]*>|\S+)")
HTML_LINK_RE = re.compile(r"""\b(?:href|src)\s*=\s*["']([^"']+)["']""", re.IGNORECASE)
HTML_ANCHOR_RE = re.compile(r"""\b(?:id|name)\s*=\s*["']([^"']+)["']""", re.IGNORECASE)
URL_SCHEME_RE = re.compile(r"^[A-Za-z][A-Za-z0-9+.-]*:")
HTML_COMMENT_RE = re.compile(r"<!--.*?-->", re.DOTALL)

# ---------------------------------------------------------------------------
# Results and repository access
# ---------------------------------------------------------------------------


@dataclass
class CheckResult:
    """Errors and warnings collected by one group of checks."""

    title: str
    errors: List[str] = field(default_factory=list)
    warnings: List[str] = field(default_factory=list)

    def error(self, message: str) -> None:
        """Record a problem that fails validation."""
        self.errors.append(message)

    def warn(self, message: str) -> None:
        """Record a problem worth reviewing that does not fail validation."""
        self.warnings.append(message)

    @property
    def passed(self) -> bool:
        """True when the group found no errors."""
        return not self.errors


class Repo:
    """Read-only view of the repository under validation, with cached reads."""

    def __init__(self, root: Path) -> None:
        self.root = root
        self._text: Dict[str, Optional[str]] = {}
        self._files: Optional[List[str]] = None

    def path(self, rel: str) -> Path:
        """Absolute path of a repository-relative POSIX path."""
        return self.root.joinpath(*rel.split("/"))

    def is_file(self, rel: str) -> bool:
        """True when the repository-relative path is an existing file."""
        return self.path(rel).is_file()

    def read_text(self, rel: str) -> Optional[str]:
        """Return a file as text with LF line endings, or None if missing or binary."""
        if rel not in self._text:
            self._text[rel] = self._load_text(self.path(rel))
        return self._text[rel]

    @staticmethod
    def _load_text(path: Path) -> Optional[str]:
        try:
            data = path.read_bytes()
        except OSError:
            return None
        if b"\0" in data:
            return None
        try:
            text = data.decode("utf-8")
        except UnicodeDecodeError:
            return None
        if text.startswith("\ufeff"):
            text = text[1:]
        return text.replace("\r\n", "\n").replace("\r", "\n")

    def load_json(self, rel: str, result: CheckResult) -> Optional[Any]:
        """Parse a JSON file, recording an error in `result` when it fails."""
        text = self.read_text(rel)
        if text is None:
            result.error(f"{rel}: file is missing or unreadable")
            return None
        try:
            return json.loads(text)
        except json.JSONDecodeError as exc:
            result.error(f"{rel}: invalid JSON ({exc.msg} at line {exc.lineno}, column {exc.colno})")
            return None

    def files(self) -> List[str]:
        """All repository files as sorted POSIX paths, honoring .gitignore when git is available."""
        if self._files is None:
            listed = self._git_files()
            self._files = listed if listed is not None else self._walk_files()
        return self._files

    def _git_files(self) -> Optional[List[str]]:
        if not (self.root / ".git").exists():
            return None
        try:
            proc = subprocess.run(
                ["git", "-C", str(self.root), "ls-files", "-z", "--cached", "--others", "--exclude-standard"],
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                check=False,
            )
        except OSError:
            return None
        if proc.returncode != 0:
            return None
        names = proc.stdout.decode("utf-8", errors="replace").split("\0")
        return sorted({name for name in names if name and self.is_file(name)})

    def _walk_files(self) -> List[str]:
        found: List[str] = []
        for current, dirs, files in os.walk(self.root):
            dirs[:] = sorted(d for d in dirs if d not in SKIPPED_DIRS)
            base = Path(current).relative_to(self.root)
            for name in files:
                found.append((base / name).as_posix())
        return sorted(found)

    def glob_names(self, directory: str, pattern: str = "*.md") -> List[str]:
        """File names in a repository directory that match a glob pattern."""
        folder = self.path(directory)
        if not folder.is_dir():
            return []
        return sorted(p.name for p in folder.glob(pattern) if p.is_file())


# ---------------------------------------------------------------------------
# Frontmatter
# ---------------------------------------------------------------------------

FieldValue = Union[str, List[str]]


@dataclass
class Frontmatter:
    """The simple YAML frontmatter used by agent and command files."""

    fields: Dict[str, FieldValue] = field(default_factory=dict)
    raw: Dict[str, str] = field(default_factory=dict)
    order: List[str] = field(default_factory=list)
    multiline: Set[str] = field(default_factory=set)
    list_form: Set[str] = field(default_factory=set)
    problems: List[str] = field(default_factory=list)
    body: str = ""
    body_first_line: int = 1


def unquote_scalar(value: str) -> str:
    """Strip one pair of surrounding YAML quotes, or a trailing comment from a plain scalar."""
    value = value.strip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
        inner = value[1:-1]
        if value[0] == '"':
            return inner.replace('\\"', '"').replace("\\\\", "\\")
        return inner.replace("''", "'")
    comment = re.search(r"\s#", value)
    return value[: comment.start()].rstrip() if comment else value


def parse_frontmatter(text: str) -> Optional[Frontmatter]:
    """Parse `key: value` frontmatter between the first two `---` lines.

    Supports plain and quoted scalars, block and flow lists
    (`key:` followed by `  - item` lines, or `key: [a, b]`), and records
    continuation lines so callers can reject multi-line values.
    Returns None when the text does not start with a frontmatter block.
    """
    lines = text.split("\n")
    if not lines or lines[0].strip() != "---":
        return None
    fm = Frontmatter()
    close = next((i for i in range(1, len(lines)) if lines[i].strip() == "---"), None)
    if close is None:
        fm.problems.append("frontmatter is not closed by a '---' line")
        return fm
    current: Optional[str] = None
    in_list = False
    for lineno, line in enumerate(lines[1:close], start=2):
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        if line[0] in " \t":
            if current is None:
                fm.problems.append(f"frontmatter line {lineno} is indented but belongs to no key")
                continue
            item = re.match(r"^-\s*(.*)$", stripped)
            if in_list and item:
                value = fm.fields[current]
                if isinstance(value, list):
                    value.append(unquote_scalar(item.group(1)))
                continue
            fm.multiline.add(current)
            previous = fm.fields.get(current, "")
            joined = " ".join(previous) if isinstance(previous, list) else previous
            fm.fields[current] = (joined + " " + stripped).strip()
            in_list = False
            continue
        match = FRONTMATTER_KEY_RE.match(line)
        if not match:
            fm.problems.append(f"frontmatter line {lineno} is not a 'key: value' pair: {stripped!r}")
            current = None
            continue
        key, value = match.group(1), (match.group(2) or "").strip()
        if key in fm.fields:
            fm.problems.append(f"duplicate frontmatter key '{key}'")
        fm.order.append(key)
        fm.raw[key] = value
        current = key
        in_list = False
        if not value:
            fm.fields[key] = []
            fm.list_form.add(key)
            in_list = True
        elif value in ("|", "|-", "|+", ">", ">-", ">+"):
            fm.fields[key] = ""
            fm.multiline.add(key)
        elif value.startswith("[") and value.endswith("]"):
            fm.fields[key] = [unquote_scalar(v) for v in value[1:-1].split(",") if v.strip()]
            fm.list_form.add(key)
        else:
            fm.fields[key] = unquote_scalar(value)
    fm.body = "\n".join(lines[close + 1 :])
    fm.body_first_line = close + 2
    return fm


def is_quoted(raw: str, quotes: str = "\"'") -> bool:
    """True when a raw frontmatter value is wrapped in one of the given quote characters."""
    return len(raw) >= 2 and raw[0] == raw[-1] and raw[0] in quotes


def scalar_field(fm: Frontmatter, key: str) -> Optional[str]:
    """A frontmatter value as a string, or None when it is missing, empty, or a list."""
    value = fm.fields.get(key)
    if isinstance(value, str) and value.strip():
        return value.strip()
    return None


# ---------------------------------------------------------------------------
# Markdown helpers
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class Fence:
    """A fenced code block: opening line index, closing line index, info string."""

    start: int
    end: int
    info: str

    @property
    def language(self) -> str:
        """The first word of the info string, lowercased."""
        return self.info.split()[0].lower() if self.info.split() else ""


def find_fences(lines: Sequence[str]) -> List[Fence]:
    """Locate fenced code blocks, honoring fence length and character (``` vs ~~~)."""
    fences: List[Fence] = []
    index = 0
    while index < len(lines):
        match = FENCE_OPEN_RE.match(lines[index])
        if match and not (match.group(1)[0] == "`" and "`" in match.group(2)):
            marker = match.group(1)
            closing = re.compile(r"^[ \t]*" + re.escape(marker[0]) + "{" + str(len(marker)) + r",}[ \t]*$")
            end = index + 1
            while end < len(lines) and not closing.match(lines[end]):
                end += 1
            fences.append(Fence(index, end, match.group(2).strip()))
            index = end + 1
        else:
            index += 1
    return fences


def fence_mask(lines: Sequence[str], fences: Optional[Sequence[Fence]] = None) -> List[bool]:
    """Per line, True when the line is part of a fenced code block (delimiters included)."""
    mask = [False] * len(lines)
    for fence in fences if fences is not None else find_fences(lines):
        for index in range(fence.start, min(fence.end, len(lines) - 1) + 1):
            mask[index] = True
    return mask


@dataclass(frozen=True)
class Heading:
    """An ATX heading outside code fences."""

    index: int
    level: int
    text: str


def find_headings(lines: Sequence[str], mask: Sequence[bool]) -> List[Heading]:
    """ATX headings that are not inside fenced code blocks."""
    found: List[Heading] = []
    for index, line in enumerate(lines):
        if mask[index]:
            continue
        match = HEADING_RE.match(line)
        if match:
            found.append(Heading(index, len(match.group(1)), match.group(2).strip()))
    return found


def strip_code_spans(line: str) -> str:
    """Replace inline code spans with a space so their contents are not parsed as links."""
    runs = [(m.start(), m.end()) for m in re.finditer(r"`+", line)]
    pieces: List[str] = []
    position = 0
    index = 0
    while index < len(runs):
        start, end = runs[index]
        size = end - start
        close = next((k for k in range(index + 1, len(runs)) if runs[k][1] - runs[k][0] == size), None)
        if close is None:
            index += 1
            continue
        pieces.append(line[position:start])
        pieces.append(" ")
        position = runs[close][1]
        index = close + 1
    pieces.append(line[position:])
    return "".join(pieces)


def github_slug(heading: str) -> str:
    """Approximate the anchor GitHub generates for a heading."""
    text = re.sub(r"!\[([^\]]*)\]\([^)]*\)", r"\1", heading)
    text = re.sub(r"\[([^\]]*)\]\([^)]*\)", r"\1", text)
    text = re.sub(r"<[^>]+>", "", text).replace("`", "")
    text = re.sub(r"[^\w\- ]", "", text.strip().lower())
    return text.replace(" ", "-")


def markdown_anchors(text: str) -> Set[str]:
    """All anchors a Markdown document defines: heading slugs plus explicit HTML ids."""
    lines = text.split("\n")
    mask = fence_mask(lines)
    anchors: Set[str] = set()
    seen: Dict[str, int] = {}
    for heading in find_headings(lines, mask):
        slug = github_slug(heading.text)
        count = seen.get(slug, 0)
        anchors.add(slug if count == 0 else f"{slug}-{count}")
        seen[slug] = count + 1
    for index, line in enumerate(lines):
        if not mask[index]:
            anchors.update(HTML_ANCHOR_RE.findall(line))
    return anchors


def prose_lines(text: str) -> List[Tuple[int, str]]:
    """(line number, text) pairs outside code fences, code spans, and HTML comments."""
    lines = text.split("\n")
    mask = fence_mask(lines)
    visible = "\n".join("" if mask[i] else strip_code_spans(line) for i, line in enumerate(lines))
    visible = HTML_COMMENT_RE.sub(lambda m: "\n" * m.group(0).count("\n"), visible)
    return list(enumerate(visible.split("\n"), start=1))


# ---------------------------------------------------------------------------
# Shell parsing for slash-command injections
# ---------------------------------------------------------------------------


@dataclass
class ShellSegment:
    """One simple command of a shell pipeline or list, with redirections removed."""

    words: List[str] = field(default_factory=list)
    raw_words: List[str] = field(default_factory=list)

    @property
    def text(self) -> str:
        """The command as written, words separated by single spaces."""
        return " ".join(self.raw_words)

    @property
    def program(self) -> str:
        """The program name, or 'git <subcommand>' for git."""
        if not self.words:
            return ""
        if self.words[0] == "git" and len(self.words) > 1:
            return f"git {self.words[1]}"
        return self.words[0]


@dataclass
class ShellParse:
    """A command line split into simple commands and the operators between them."""

    segments: List[ShellSegment] = field(default_factory=list)
    operators: List[str] = field(default_factory=list)
    problems: List[str] = field(default_factory=list)


def parse_shell(command: str) -> ShellParse:
    """Split a one-line shell command on |, ||, &&, ; and & outside quotes.

    Output redirections other than to /dev/null or to another file descriptor,
    command and process substitution, and background jobs are reported as
    problems. This is a deliberately small parser for the read-only one-liners
    that slash-command injections allow, not a full shell grammar.
    """
    parsed = ShellParse()
    segment = ShellSegment()
    word: List[str] = []
    raw: List[str] = []
    in_word = False
    i = 0
    n = len(command)

    def finish_word() -> None:
        nonlocal word, raw, in_word
        if in_word:
            segment.words.append("".join(word))
            segment.raw_words.append("".join(raw))
        word, raw, in_word = [], [], False

    def finish_segment(operator: Optional[str]) -> None:
        nonlocal segment
        finish_word()
        if not segment.words:
            parsed.problems.append(f"empty command next to '{operator or 'end of line'}'")
        parsed.segments.append(segment)
        if operator is not None:
            parsed.operators.append(operator)
        segment = ShellSegment()

    def read_target(start: int) -> Tuple[str, int]:
        position = start
        while position < n and command[position] in " \t":
            position += 1
        begin = position
        quote: Optional[str] = None
        while position < n:
            char = command[position]
            if quote:
                if char == quote:
                    quote = None
            elif char in "'\"":
                quote = char
            elif char in " \t|&;<>":
                break
            position += 1
        return command[begin:position].strip("'\""), position

    while i < n:
        char = command[i]
        if char == "'":
            end = command.find("'", i + 1)
            if end == -1:
                parsed.problems.append("unterminated single quote")
                end = n - 1
            word.append(command[i + 1 : end])
            raw.append(command[i : end + 1])
            in_word = True
            i = end + 1
            continue
        if char == '"':
            j = i + 1
            content: List[str] = []
            while j < n and command[j] != '"':
                if command[j] == "\\" and j + 1 < n:
                    content.append(command[j + 1])
                    j += 2
                    continue
                if command[j] == "$" and j + 1 < n and command[j + 1] == "(":
                    parsed.problems.append("command substitution '$(...)'")
                content.append(command[j])
                j += 1
            if j >= n:
                parsed.problems.append("unterminated double quote")
            word.append("".join(content))
            raw.append(command[i : j + 1])
            in_word = True
            i = j + 1
            continue
        if char == "\\" and i + 1 < n:
            word.append(command[i + 1])
            raw.append(command[i : i + 2])
            in_word = True
            i += 2
            continue
        if char in " \t\n":
            finish_word()
            i += 1
            continue
        if char == "$" and i + 1 < n and command[i + 1] == "(":
            parsed.problems.append("command substitution '$(...)'")
        if char in "<>" and i + 1 < n and command[i + 1] == "(":
            parsed.problems.append("process substitution")
        if char == "|":
            operator = "||" if command.startswith("||", i) else "|"
            finish_segment(operator)
            i += len(operator)
            continue
        if char == "&":
            if command.startswith("&&", i):
                finish_segment("&&")
                i += 2
                continue
            if command.startswith("&>", i):
                finish_word()
                target, i = read_target(i + (3 if command.startswith("&>>", i) else 2))
                if target != "/dev/null":
                    parsed.problems.append(f"output redirection to a file ('&>{target}')")
                continue
            parsed.problems.append("background operator '&'")
            finish_segment("&")
            i += 1
            continue
        if char == ";":
            finish_segment(";")
            i += 1
            continue
        if char == ">":
            if in_word and "".join(raw).isdigit():
                word, raw, in_word = [], [], False  # file descriptor such as the 2 in 2>
            else:
                finish_word()
            i += 1
            if i < n and command[i] == ">":
                i += 1
            if i < n and command[i] == "&":
                i += 1
                while i < n and (command[i].isdigit() or command[i] == "-"):
                    i += 1
                continue
            target, i = read_target(i)
            if target != "/dev/null":
                parsed.problems.append(f"output redirection to a file ('>{target}')")
            continue
        if char == "<":
            finish_word()
            if command.startswith("<<", i):
                parsed.problems.append("here-document or here-string")
                i += 2
                continue
            _, i = read_target(i + 1)
            continue
        word.append(char)
        raw.append(char)
        in_word = True
        i += 1
    finish_segment(None)
    return parsed


def ends_with_fallback(parsed: ShellParse) -> bool:
    """True when the command line cannot exit non-zero under the injection rules.

    Accepted endings: `... || echo "..."` (or `; echo`), a pipeline whose last
    command is head, tail, or wc, or a single echo command.
    """
    if not parsed.segments:
        return False
    last = parsed.segments[-1].program
    if not parsed.operators:
        return last == "echo"
    operator = parsed.operators[-1]
    if operator in ("||", ";") and last == "echo":
        return True
    return operator == "|" and last in PIPELINE_SINKS


@dataclass(frozen=True)
class BashPattern:
    """One `Bash(...)` entry of a command's allowed-tools."""

    spec: str
    prefix: str
    wildcard: bool

    @property
    def program(self) -> str:
        """The program the pattern authorizes, or 'git <subcommand>' for git."""
        words = self.prefix.split()
        if not words:
            return ""
        if words[0] == "git" and len(words) > 1:
            return f"git {words[1]}"
        return words[0]

    def covers(self, command: str) -> bool:
        """True when the pattern pre-authorizes the given simple command."""
        if self.wildcard:
            return command == self.prefix or command.startswith(self.prefix + " ")
        return command == self.prefix


def parse_bash_pattern(spec: str) -> BashPattern:
    """Interpret `git status *`, `git status:*`, or an exact command."""
    spec = spec.strip()
    for suffix in (" *", ":*", "*"):
        if spec.endswith(suffix):
            return BashPattern(spec, spec[: -len(suffix)].strip(), True)
    return BashPattern(spec, spec, False)


# ---------------------------------------------------------------------------
# Check 1: required files
# ---------------------------------------------------------------------------


def check_required_files(repo: Repo, result: CheckResult) -> None:
    """Every file in the AGEX file tree exists and is not empty."""
    for rel in REQUIRED_FILES:
        path = repo.path(rel)
        if not path.is_file():
            result.error(f"{rel}: required file is missing")
            continue
        text = repo.read_text(rel)
        if path.stat().st_size == 0 or (text is not None and not text.strip()):
            result.error(f"{rel}: required file is empty")


# ---------------------------------------------------------------------------
# Check 2: agents
# ---------------------------------------------------------------------------


def parse_tool_list(result: CheckResult, rel: str, key: str, fm: Frontmatter) -> Optional[List[str]]:
    """Parse a comma-separated (or YAML list) tool field into tool names."""
    if key not in fm.fields:
        return None
    value = fm.fields[key]
    if isinstance(value, list):
        items = value
        result.warn(
            f"{rel}: '{key}' uses YAML list syntax; AGEX uses a comma-separated string (e.g. 'Read, Grep, Glob')"
        )
    else:
        items = value.split(",")
    names: List[str] = []
    for item in (entry.strip() for entry in items):
        if not item:
            result.error(f"{rel}: '{key}' contains an empty entry")
            continue
        match = re.match(r"^([A-Za-z_]\w*)(\(.*\))?$", item)
        name = match.group(1) if match else item
        if not match or (name not in KNOWN_TOOLS and not name.startswith("mcp__")):
            result.error(f"{rel}: '{key}' lists unknown tool '{item}'")
        if name in names:
            result.error(f"{rel}: '{key}' lists '{name}' more than once")
        names.append(name)
    if not names:
        result.error(f"{rel}: '{key}' is empty")
    return names


def check_agent_frontmatter(
    result: CheckResult, rel: str, stem: str, fm: Frontmatter, spec: Optional[AgentSpec]
) -> None:
    """Field presence, values, order, and the roster match for one agent."""
    for problem in fm.problems:
        result.error(f"{rel}: {problem}")
    for key in AGENT_REQUIRED_FIELDS:
        if key not in fm.fields:
            result.error(f"{rel}: frontmatter is missing '{key}'")

    name = scalar_field(fm, "name")
    if "name" in fm.fields:
        if name is None:
            result.error(f"{rel}: 'name' is empty")
        elif name != stem:
            result.error(f"{rel}: name '{name}' does not match the filename stem '{stem}'")
        elif not KEBAB_RE.match(name):
            result.error(f"{rel}: name '{name}' is not kebab-case")

    if "description" in fm.fields:
        description = scalar_field(fm, "description")
        if description is None:
            result.error(f"{rel}: 'description' is empty")
        elif "description" in fm.multiline:
            result.error(f"{rel}: 'description' must be a single line")
        elif not is_quoted(fm.raw.get("description", ""), '"'):
            result.error(f"{rel}: 'description' must be a double-quoted string")

    tools = parse_tool_list(result, rel, "tools", fm)
    disallowed = parse_tool_list(result, rel, "disallowedTools", fm)

    model = scalar_field(fm, "model")
    if "model" in fm.fields:
        if model is None:
            result.error(f"{rel}: 'model' is empty")
        elif model not in MODEL_ALIASES and not model.startswith("claude-"):
            allowed = ", ".join(sorted(MODEL_ALIASES))
            result.error(f"{rel}: model '{model}' is not an alias ({allowed}) or a 'claude-' model id")

    color = scalar_field(fm, "color")
    if "color" not in fm.fields:
        result.warn(f"{rel}: frontmatter has no 'color'")
    elif color not in AGENT_COLORS:
        result.error(f"{rel}: color '{color}' is not one of {', '.join(sorted(AGENT_COLORS))}")

    ordered = [key for key in fm.order if key in AGENT_FIELD_ORDER]
    if ordered != sorted(ordered, key=AGENT_FIELD_ORDER.index):
        result.error(
            f"{rel}: frontmatter fields are out of order ({', '.join(ordered)}); "
            f"expected {', '.join(AGENT_FIELD_ORDER)}"
        )
    for key in fm.order:
        if key in AGENT_IGNORED_FIELDS:
            result.error(f"{rel}: '{key}' is ignored for plugin subagents; AGEX agents must not set it")
        elif key not in AGENT_FIELD_ORDER:
            result.warn(f"{rel}: unexpected frontmatter field '{key}'")

    if spec is None:
        return
    if tools is not None and set(tools) != set(spec.tools):
        result.error(f"{rel}: tools are '{', '.join(tools)}'; the roster requires '{', '.join(spec.tools)}'")
    if set(disallowed or ()) != set(spec.disallowed_tools):
        expected = ", ".join(spec.disallowed_tools) if spec.disallowed_tools else "no disallowedTools field"
        found = ", ".join(disallowed) if disallowed else "none"
        result.error(f"{rel}: disallowedTools are '{found}'; the roster requires {expected}")
    if model is not None and model != spec.model:
        result.error(f"{rel}: model is '{model}'; the roster requires '{spec.model}'")
    if color in AGENT_COLORS and color != spec.color:
        result.warn(f"{rel}: color is '{color}'; the roster uses '{spec.color}'")
    if spec.read_only and tools:
        editing = sorted(EDITING_TOOLS.intersection(tools))
        if editing:
            result.error(f"{rel}: read-only agent must not have {', '.join(editing)} in tools")


def section_lines(lines: Sequence[str], headings: Sequence[Heading], title: str) -> Optional[Tuple[int, int]]:
    """Line range [start, end) of the level-2 section with the given title."""
    for position, heading in enumerate(headings):
        if heading.level == 2 and heading.text == title:
            end = next((h.index for h in headings[position + 1 :] if h.level <= 2), len(lines))
            return heading.index + 1, end
    return None


def check_artifact_template(
    result: CheckResult, rel: str, agent: str, template: Sequence[str], artifact: str
) -> None:
    """The Output Format template matches the canonical artifact schema."""
    spec = ARTIFACTS[artifact]
    content = [line.rstrip() for line in template if line.strip()]
    marker = f"<!-- agex:artifact type={artifact} version=1 -->"
    if not content or content[0].strip() != marker:
        result.error(f"{rel}: the Output Format template must start with '{marker}'")
        return
    if len(content) < 3:
        result.error(f"{rel}: the {artifact} template is missing its title and Producer lines")
        return
    if not re.match(rf"^## {re.escape(artifact)}: \S", content[1]):
        result.error(f"{rel}: the template title must read '## {artifact}: <short title>'")
    producer = re.match(
        r"^\*\*Producer:\*\* (\S+) · \*\*Status:\*\* (.+?)(?: · \*\*Confidence:\*\* (.+))?$", content[2]
    )
    if not producer:
        result.error(
            f"{rel}: the template needs the line "
            f"'**Producer:** {agent} · **Status:** {' | '.join(spec.statuses)} · **Confidence:** HIGH | MEDIUM | LOW'"
        )
    else:
        if producer.group(1) != agent:
            result.error(f"{rel}: template Producer is '{producer.group(1)}'; expected '{agent}'")
        statuses = tuple(s.strip() for s in producer.group(2).split("|"))
        if statuses != spec.statuses:
            result.error(
                f"{rel}: {artifact} status enum is '{' | '.join(statuses)}'; expected '{' | '.join(spec.statuses)}'"
            )
        confidence = producer.group(3)
        if confidence is None and not spec.confidence_optional:
            result.error(f"{rel}: the {artifact} template must include '**Confidence:** HIGH | MEDIUM | LOW'")
        elif confidence is not None and tuple(c.strip() for c in confidence.split("|")) != CONFIDENCE_ENUM:
            result.error(f"{rel}: Confidence enum is '{confidence}'; expected 'HIGH | MEDIUM | LOW'")
    sections = tuple(line[4:].strip() for line in content if line.startswith("### "))
    if sections != spec.sections:
        result.error(
            f"{rel}: {artifact} sections are [{', '.join(sections)}]; expected [{', '.join(spec.sections)}]"
        )


def check_agent_body(result: CheckResult, rel: str, stem: str, fm: Frontmatter, spec: Optional[AgentSpec]) -> None:
    """Word count, heading structure, NEVER constraints, and the artifact template."""
    body = fm.body
    low, high = BODY_WORDS_BY_AGENT.get(stem, DEFAULT_BODY_WORDS)
    words = len(body.split())
    if not low <= words <= high:
        result.error(f"{rel}: body has {words} words; expected {low}-{high}")

    lines = body.split("\n")
    fences = find_fences(lines)
    mask = fence_mask(lines, fences)
    headings = find_headings(lines, mask)

    titles = [h for h in headings if h.level == 1]
    if len(titles) != 1:
        result.error(
            f"{rel}: body must have exactly one '# <Role Title> — AGEX <Agent Name>' heading (found {len(titles)})"
        )
    else:
        title = titles[0]
        match = re.match(r"^.+ — AGEX (.+)$", title.text)
        if not match:
            result.error(f"{rel}: title '{title.text}' must read '<Role Title> — AGEX <Agent Name>'")
        elif match.group(1).strip().lower().replace(" ", "-") != stem:
            result.warn(f"{rel}: title names 'AGEX {match.group(1).strip()}' but the agent is '{stem}'")
        if headings and headings[0] is not title:
            result.error(f"{rel}: the '# ... — AGEX ...' title must be the first heading")

    level_two = [h.text for h in headings if h.level == 2]
    positions: List[int] = []
    for section in AGENT_REQUIRED_SECTIONS:
        if section in level_two:
            positions.append(level_two.index(section))
        else:
            result.error(f"{rel}: missing required section '## {section}'")
    if positions != sorted(positions):
        result.error(f"{rel}: required sections must appear in this order: {', '.join(AGENT_REQUIRED_SECTIONS)}")

    if "NEVER" not in body:
        result.error(f"{rel}: body contains no NEVER constraint")
    constraints = section_lines(lines, headings, "Hard Constraints")
    if constraints is not None:
        start, end = constraints
        count = sum(1 for i in range(start, end) if not mask[i] and NEVER_BULLET_RE.match(lines[i]))
        if count < MIN_NEVER_BULLETS:
            result.error(
                f"{rel}: '## Hard Constraints' has {count} '**NEVER**' bullets; expected at least {MIN_NEVER_BULLETS}"
            )

    if spec is not None:
        marker = f"<!-- agex:artifact type={spec.artifact} version=1 -->"
        if marker not in body:
            result.error(f"{rel}: body does not contain the artifact marker '{marker}'")

    output = section_lines(lines, headings, "Output Format")
    if output is not None:
        start, end = output
        templates = [f for f in fences if start <= f.start < end and f.language in ("markdown", "md")]
        if not templates:
            result.error(f"{rel}: '## Output Format' has no ```markdown artifact template")
        elif spec is not None:
            fence = templates[0]
            check_artifact_template(result, rel, stem, lines[fence.start + 1 : fence.end], spec.artifact)
        elif not any("<!-- agex:artifact type=" in line for line in lines[templates[0].start : templates[0].end]):
            result.error(
                f"{rel}: the Output Format template has no '<!-- agex:artifact type=<Type> version=1 -->' marker"
            )

    if re.search(r"HANDOFF-PROTOCOL\.md|docs/AGENTS\.md", body):
        result.warn(f"{rel}: agents must be self-contained; do not point them at AGEX documentation files")


def check_agents(repo: Repo, result: CheckResult) -> None:
    """The 12 agent files: frontmatter, roster, body structure, and artifact template."""
    directory = ".claude/agents"
    stems = [name[:-3] for name in repo.glob_names(directory)]
    for missing in sorted(set(AGENT_ROSTER) - set(stems)):
        result.error(f"{directory}/{missing}.md: agent is missing")
    for extra in sorted(set(stems) - set(AGENT_ROSTER)):
        result.error(f"{directory}/{extra}.md: unexpected agent; add it to AGENT_ROSTER in {THIS_FILE} or remove it")
    for stem in stems:
        rel = f"{directory}/{stem}.md"
        text = repo.read_text(rel)
        if text is None:
            result.error(f"{rel}: file is unreadable or not UTF-8 text")
            continue
        fm = parse_frontmatter(text)
        if fm is None:
            result.error(f"{rel}: file must start with YAML frontmatter ('---')")
            continue
        spec = AGENT_ROSTER.get(stem)
        check_agent_frontmatter(result, rel, stem, fm, spec)
        check_agent_body(result, rel, stem, fm, spec)


# ---------------------------------------------------------------------------
# Check 3: commands
# ---------------------------------------------------------------------------


def bash_patterns(result: CheckResult, rel: str, value: Optional[FieldValue]) -> List[BashPattern]:
    """The Bash(...) patterns of an allowed-tools value, reporting unsafe ones."""
    if value is None:
        return []
    items = value if isinstance(value, list) else [value]
    patterns: List[BashPattern] = []
    for item in items:
        for match in TOOL_PATTERN_RE.finditer(item):
            name, spec = match.group(1), match.group(2)
            if name != "Bash":
                continue
            if spec is None or not spec.strip():
                result.error(f"{rel}: allowed-tools grants bare 'Bash', which pre-authorizes every shell command")
                continue
            pattern = parse_bash_pattern(spec)
            if pattern.program not in INJECTION_PROGRAMS:
                result.error(
                    f"{rel}: allowed-tools grants 'Bash({spec})', outside the injection allowlist "
                    f"({', '.join(INJECTION_PROGRAMS)})"
                )
            patterns.append(pattern)
    return patterns


def check_injections(
    result: CheckResult, rel: str, lines: Iterable[Tuple[int, str]], allowed: Optional[FieldValue]
) -> None:
    """Every `!` injection is read-only, allowlisted, pre-authorized, and cannot fail."""
    patterns = bash_patterns(result, rel, allowed)
    used: Set[str] = set()
    for number, line in lines:
        for match in INJECTION_RE.finditer(line):
            command = match.group(1)
            where = f"{rel}:{number}"
            parsed = parse_shell(command)
            for problem in parsed.problems:
                result.error(f"{where}: injection uses {problem}: {command}")
            if "HEAD~" in command:
                result.error(f"{where}: injection uses 'HEAD~', which fails in a repository with one commit: {command}")
            for segment in parsed.segments:
                program = segment.program
                if not program:
                    continue
                if segment.words[0] in FORBIDDEN_PROGRAMS:
                    result.error(f"{where}: injection runs {FORBIDDEN_PROGRAMS[segment.words[0]]}: {command}")
                    continue
                if program not in INJECTION_PROGRAMS:
                    result.error(
                        f"{where}: injection runs '{program}', which is not in the allowlist "
                        f"({', '.join(INJECTION_PROGRAMS)}): {command}"
                    )
                    continue
                covering = [p for p in patterns if p.covers(segment.text)]
                if not covering:
                    result.error(f"{where}: '{program}' is not covered by allowed-tools; add 'Bash({program} *)'")
                used.update(p.spec for p in covering)
            if not ends_with_fallback(parsed):
                result.error(
                    f"{where}: injection can exit non-zero and abort the command; end it with "
                    f"'2>/dev/null || echo \"(fallback)\"' or pipe it into head: {command}"
                )
    for pattern in patterns:
        if pattern.spec not in used:
            result.warn(f"{rel}: allowed-tools lists 'Bash({pattern.spec})' but no injection uses it")


def numbered_body_lines(fm: Frontmatter) -> List[Tuple[int, str]]:
    """Body lines paired with their line numbers in the original file."""
    return [(fm.body_first_line + i, line) for i, line in enumerate(fm.body.split("\n"))]


def check_command_file(repo: Repo, result: CheckResult, name: str) -> None:
    """Frontmatter, arguments, agent naming, and injection safety of one command."""
    rel = f".claude/commands/{name}.md"
    text = repo.read_text(rel)
    if text is None:
        result.error(f"{rel}: file is unreadable or not UTF-8 text")
        return
    fm = parse_frontmatter(text)
    if fm is None:
        result.error(f"{rel}: file must start with YAML frontmatter ('---')")
        return
    for problem in fm.problems:
        result.error(f"{rel}: {problem}")
    description = scalar_field(fm, "description")
    if description is None:
        result.error(f"{rel}: frontmatter needs a non-empty 'description'")
    elif "description" in fm.multiline:
        result.error(f"{rel}: 'description' must be a single line")
    elif not is_quoted(fm.raw.get("description", "")):
        result.error(f"{rel}: 'description' must be a quoted string")
    if "model" in fm.fields:
        result.error(f"{rel}: AGEX commands do not set 'model'")
    for key in fm.order:
        if key not in ("description", "argument-hint", "allowed-tools"):
            result.warn(f"{rel}: unexpected frontmatter field '{key}'")

    body = fm.body
    if name in COMMANDS_REQUIRING_ARGUMENTS and "$ARGUMENTS" not in body:
        result.error(f"{rel}: body must include $ARGUMENTS")
    if "$ARGUMENTS" in body and "argument-hint" not in fm.fields:
        result.warn(f"{rel}: uses $ARGUMENTS but has no 'argument-hint'")
    agent = COMMAND_AGENTS.get(name)
    if agent and f"agex:{agent}" not in body:
        result.warn(f"{rel}: does not mention the scoped name 'agex:{agent}' from the dispatch naming rule")

    check_injections(result, rel, numbered_body_lines(fm), fm.fields.get("allowed-tools"))


def check_commands(repo: Repo, result: CheckResult) -> None:
    """The 8 command files, plus injection safety of the command template."""
    directory = ".claude/commands"
    stems = [name[:-3] for name in repo.glob_names(directory)]
    for missing in sorted(set(COMMANDS) - set(stems)):
        result.error(f"{directory}/{missing}.md: command is missing")
    for extra in sorted(set(stems) - set(COMMANDS)):
        result.error(f"{directory}/{extra}.md: unexpected command; add it to COMMANDS in {THIS_FILE} or remove it")
    for stem in stems:
        check_command_file(repo, result, stem)
    for rel in EXTRA_INJECTION_FILES:
        text = repo.read_text(rel)
        fm = parse_frontmatter(text) if text is not None else None
        if fm is not None:
            check_injections(result, rel, numbered_body_lines(fm), fm.fields.get("allowed-tools"))


# ---------------------------------------------------------------------------
# Checks 4-6: plugin manifest, marketplace, versions
# ---------------------------------------------------------------------------


def manifest_path(result: CheckResult, rel: str, key: str, entry: Any) -> Optional[str]:
    """Normalize a './'-relative manifest path, reporting malformed entries."""
    if not isinstance(entry, str) or not entry.startswith("./"):
        result.error(f"{rel}: '{key}' entry {entry!r} must be a string starting with './'")
        return None
    normalized = posixpath.normpath(entry[2:])
    if normalized == ".." or normalized.startswith("../"):
        result.error(f"{rel}: '{key}' entry {entry!r} points outside the repository")
        return None
    return normalized


def check_plugin_manifest(repo: Repo, result: CheckResult) -> None:
    """.claude-plugin/plugin.json: identity, component lists, hooks file, no emails."""
    rel = ".claude-plugin/plugin.json"
    data = repo.load_json(rel, result)
    if data is None:
        return
    if not isinstance(data, dict):
        result.error(f"{rel}: top level must be a JSON object")
        return
    if data.get("name") != "agex":
        result.error(f"{rel}: name must be 'agex' (found {data.get('name')!r})")
    version = data.get("version")
    if not isinstance(version, str) or not SEMVER_RE.match(version):
        result.error(f"{rel}: version {version!r} is not a semantic version (X.Y.Z)")
    author = data.get("author")
    if not isinstance(author, dict) or not isinstance(author.get("name"), str) or not author["name"].strip():
        result.error(f"{rel}: author must be an object with a non-empty 'name'")

    for key, directory in (("agents", ".claude/agents"), ("commands", ".claude/commands")):
        entries = data.get(key)
        if not isinstance(entries, list):
            result.error(f"{rel}: '{key}' must be a list of './' paths")
            continue
        listed: List[str] = []
        for entry in entries:
            path = manifest_path(result, rel, key, entry)
            if path is None:
                continue
            if not repo.is_file(path):
                result.error(f"{rel}: '{key}' entry '{entry}' does not exist")
            if path in listed:
                result.error(f"{rel}: '{key}' lists '{entry}' more than once")
            listed.append(path)
        on_disk = {f"{directory}/{name}" for name in repo.glob_names(directory)}
        for path in sorted(on_disk - set(listed)):
            result.error(f"{rel}: '{key}' does not list './{path}'")
        for path in sorted(set(listed) - on_disk):
            result.error(f"{rel}: '{key}' lists './{path}', which is not a Markdown file in {directory}/")

    hooks = data.get("hooks")
    hook_entries = hooks if isinstance(hooks, list) else [hooks]
    if hooks is None:
        result.error(f"{rel}: 'hooks' must point to {PLUGIN_HOOKS_FILE}")
    for entry in hook_entries if hooks is not None else []:
        path = manifest_path(result, rel, "hooks", entry)
        if path is None:
            continue
        if not repo.is_file(path):
            result.error(f"{rel}: hooks file '{entry}' does not exist")
            continue
        config = repo.load_json(path, result)
        if config is not None and not (isinstance(config, dict) and isinstance(config.get("hooks"), dict)):
            result.error(f"{path}: must be a JSON object with a 'hooks' object")

    text = repo.read_text(rel) or ""
    for email in EMAIL_RE.findall(text):
        result.error(f"{rel}: contains an email address ({email}); use GitHub links only")


def check_marketplace(repo: Repo, result: CheckResult) -> None:
    """.claude-plugin/marketplace.json: owner and the single 'agex' plugin entry."""
    rel = ".claude-plugin/marketplace.json"
    data = repo.load_json(rel, result)
    if data is None:
        return
    if not isinstance(data, dict):
        result.error(f"{rel}: top level must be a JSON object")
        return
    if not isinstance(data.get("name"), str) or not data["name"].strip():
        result.error(f"{rel}: marketplace 'name' is missing")
    owner = data.get("owner")
    if not isinstance(owner, dict) or not isinstance(owner.get("name"), str) or not owner["name"].strip():
        result.error(f"{rel}: 'owner' must be an object with a non-empty 'name'")
    plugins = data.get("plugins")
    if not isinstance(plugins, list) or not plugins or not isinstance(plugins[0], dict):
        result.error(f"{rel}: 'plugins' must be a non-empty list of plugin objects")
        return
    entry = plugins[0]
    if entry.get("name") != "agex":
        result.error(f"{rel}: plugins[0].name must be 'agex' (found {entry.get('name')!r})")
    if entry.get("source") != "./":
        result.error(f"{rel}: plugins[0].source must be './' (found {entry.get('source')!r})")
    plugin = repo.load_json(".claude-plugin/plugin.json", CheckResult("scratch"))
    plugin_version = plugin.get("version") if isinstance(plugin, dict) else None
    if plugin_version is not None and entry.get("version") != plugin_version:
        result.error(
            f"{rel}: plugins[0].version {entry.get('version')!r} does not match plugin.json version {plugin_version!r}"
        )


def check_versions(repo: Repo, result: CheckResult) -> None:
    """plugin.json, marketplace metadata, CHANGELOG, and README agree on the version."""
    scratch = CheckResult("scratch")
    plugin = repo.load_json(".claude-plugin/plugin.json", scratch)
    marketplace = repo.load_json(".claude-plugin/marketplace.json", scratch)
    versions: Dict[str, Optional[str]] = {}
    versions["plugin.json version"] = plugin.get("version") if isinstance(plugin, dict) else None
    metadata = marketplace.get("metadata") if isinstance(marketplace, dict) else None
    versions["marketplace.json metadata.version"] = metadata.get("version") if isinstance(metadata, dict) else None

    changelog = repo.read_text("CHANGELOG.md") or ""
    released = [v for v in re.findall(r"^## \[([^\]]+)\]", changelog, re.MULTILINE) if v.lower() != "unreleased"]
    versions["CHANGELOG.md top release"] = released[0] if released else None

    for label, value in versions.items():
        if value is None:
            result.error(f"{label} is missing")
    known = {label: value for label, value in versions.items() if value is not None}
    if len(set(known.values())) > 1:
        result.error("versions disagree: " + ", ".join(f"{label} = {value}" for label, value in known.items()))

    reference = versions["plugin.json version"]
    if reference is None:
        return
    if released and not re.search(rf"^\[{re.escape(released[0])}\]:\s*\S+", changelog, re.MULTILINE):
        result.warn(f"CHANGELOG.md: no '[{released[0]}]: <url>' link reference at the bottom")
    readme = repo.read_text("README.md") or ""
    if not re.search(rf"(?<![A-Za-z0-9])v{re.escape(reference)}(?![0-9])", readme):
        result.error(f"README.md: does not mention v{reference} (update the version badge)")
    for badge in re.findall(r"badge/version-v([0-9A-Za-z.]+(?:--[0-9A-Za-z.]+)*)-", readme):
        if badge.replace("--", "-") != reference:
            result.error(f"README.md: version badge says v{badge}; plugin.json says {reference}")


# ---------------------------------------------------------------------------
# Check 7: hooks
# ---------------------------------------------------------------------------


def hook_commands(result: CheckResult, rel: str, config: Any) -> Optional[Dict[Tuple[str, str], List[str]]]:
    """Map (event, matcher) to hook commands, reporting malformed entries."""
    hooks = config.get("hooks") if isinstance(config, dict) else None
    if not isinstance(hooks, dict):
        result.error(f"{rel}: must contain a 'hooks' object")
        return None
    found: Dict[Tuple[str, str], List[str]] = {}
    for event, entries in hooks.items():
        if not isinstance(entries, list):
            result.error(f"{rel}: hooks.{event} must be a list")
            continue
        for index, entry in enumerate(entries):
            where = f"{rel}: hooks.{event}[{index}]"
            if not isinstance(entry, dict):
                result.error(f"{where} must be an object")
                continue
            matcher = entry.get("matcher", "")
            if not isinstance(matcher, str):
                result.error(f"{where}.matcher must be a string")
                continue
            handlers = entry.get("hooks")
            if not isinstance(handlers, list) or not handlers:
                result.error(f"{where}.hooks must be a non-empty list")
                continue
            for handler in handlers:
                if (
                    not isinstance(handler, dict)
                    or handler.get("type") != "command"
                    or not isinstance(handler.get("command"), str)
                ):
                    result.error(f"{where}: each hook needs type 'command' and a 'command' string")
                    continue
                found.setdefault((event, matcher), []).append(handler["command"])
    return found


def check_hooks(repo: Repo, result: CheckResult) -> None:
    """Both hook configurations parse, call the logging script, and register the same events."""
    registrations: Dict[str, Dict[Tuple[str, str], List[str]]] = {}
    root_variables = {PROJECT_SETTINGS_FILE: "CLAUDE_PROJECT_DIR", PLUGIN_HOOKS_FILE: "CLAUDE_PLUGIN_ROOT"}
    for rel, variable in root_variables.items():
        config = repo.load_json(rel, result)
        if config is None:
            continue
        found = hook_commands(result, rel, config)
        if found is None:
            continue
        if not found:
            result.error(f"{rel}: registers no hook commands")
        for (event, matcher), commands in sorted(found.items()):
            for command in commands:
                if HOOK_SCRIPT not in command:
                    result.error(f"{rel}: {event} hook does not call {HOOK_SCRIPT}: {command}")
                elif variable not in command:
                    result.error(f"{rel}: {event} hook must locate the script through ${variable}: {command}")
        registrations[rel] = found

    if len(registrations) == 2:
        project = set(registrations[PROJECT_SETTINGS_FILE])
        plugin = set(registrations[PLUGIN_HOOKS_FILE])
        for event, matcher in sorted(project ^ plugin):
            owner = PROJECT_SETTINGS_FILE if (event, matcher) in project else PLUGIN_HOOKS_FILE
            label = f"{event} (matcher '{matcher}')" if matcher else event
            result.error(f"hook registrations differ: only {owner} registers {label}")

    script = repo.read_text(HOOK_SCRIPT)
    if script is None:
        result.error(f"{HOOK_SCRIPT}: logging script is missing")
    elif not re.match(r"#!\s*(/bin/sh|/usr/bin/env sh)\s*$", script.split("\n", 1)[0]):
        result.warn(f"{HOOK_SCRIPT}: first line should be '#!/bin/sh' (the script must stay POSIX sh)")


# ---------------------------------------------------------------------------
# Check 8: Markdown links
# ---------------------------------------------------------------------------


def link_targets(text: str) -> List[Tuple[int, str]]:
    """(line, target) for inline, reference, and HTML links outside code."""
    targets: List[Tuple[int, str]] = []
    for number, line in prose_lines(text):
        for match in INLINE_LINK_RE.finditer(line):
            targets.append((number, match.group(1)))
        reference = REFERENCE_LINK_RE.match(line)
        if reference:
            targets.append((number, reference.group(1)))
        for target in HTML_LINK_RE.findall(line):
            targets.append((number, target))
    return targets


def check_markdown(repo: Repo, result: CheckResult) -> None:
    """Relative links in every Markdown file resolve; anchors and H1 counts are advisory."""
    anchor_cache: Dict[str, Set[str]] = {}

    def anchors_of(rel: str) -> Set[str]:
        if rel not in anchor_cache:
            anchor_cache[rel] = markdown_anchors(repo.read_text(rel) or "")
        return anchor_cache[rel]

    for rel in (f for f in repo.files() if f.lower().endswith(".md")):
        text = repo.read_text(rel)
        if text is None:
            continue
        lines = text.split("\n")
        h1_count = sum(1 for h in find_headings(lines, fence_mask(lines)) if h.level == 1)
        if h1_count != 1 and not rel.startswith((".github/", "templates/")):
            result.warn(f"{rel}: has {h1_count} H1 headings; documents should have exactly one")
        base = posixpath.dirname(rel)
        for number, raw_target in link_targets(text):
            target = raw_target.strip()
            if target.startswith("<") and target.endswith(">"):
                target = target[1:-1].strip()
                if "/" not in target and "." not in target:
                    continue  # an <angle-bracket> fill-in inside a template example
            if not target or target.startswith("//") or URL_SCHEME_RE.match(target):
                continue
            path_part, _, fragment = target.partition("#")
            path_part = unquote(path_part.split("?", 1)[0])
            where = f"{rel}:{number}"
            if not path_part:
                if fragment and fragment not in anchors_of(rel):
                    result.warn(f"{where}: anchor '#{fragment}' does not match a heading in this file")
                continue
            joined = path_part.lstrip("/") if path_part.startswith("/") else posixpath.join(base, path_part)
            resolved = posixpath.normpath(joined)
            if resolved == ".." or resolved.startswith("../"):
                result.error(f"{where}: link '{raw_target}' points outside the repository")
                continue
            if not repo.path(resolved).exists():
                result.error(f"{where}: broken link '{raw_target}' ({resolved} does not exist)")
                continue
            if fragment and resolved.lower().endswith(".md") and repo.is_file(resolved):
                if fragment not in anchors_of(resolved):
                    result.warn(f"{where}: anchor '#{fragment}' does not match a heading in {resolved}")


# ---------------------------------------------------------------------------
# Checks 9-10: placeholders, emails, emojis
# ---------------------------------------------------------------------------


def check_placeholders(repo: Repo, result: CheckResult) -> None:
    """No placeholder text in any text file, and no email addresses anywhere."""
    for rel in repo.files():
        if rel == THIS_FILE:
            continue
        text = repo.read_text(rel)
        if text is None:
            continue
        fill_in_allowed = rel.startswith("templates/")
        for number, line in enumerate(text.split("\n"), start=1):
            if not fill_in_allowed:
                for label, pattern in PLACEHOLDER_PATTERNS:
                    if pattern.search(line):
                        result.error(f"{rel}:{number}: placeholder text '{label}'")
            for match in EMAIL_RE.finditer(line):
                address = match.group(0)
                if address.lower().startswith("git@") and line[match.end() : match.end() + 1] == ":":
                    continue  # an SSH remote such as git@github.com:owner/repo.git
                result.error(f"{rel}:{number}: email address '{address}'; use GitHub links only")


def emoji_hits(text: str) -> List[Tuple[int, str]]:
    """(line, 'U+XXXX c') for every emoji-range character in the text."""
    hits: List[Tuple[int, str]] = []
    for number, line in enumerate(text.split("\n"), start=1):
        for char in line:
            code = ord(char)
            if any(low <= code <= high for low, high in EMOJI_RANGES):
                hits.append((number, f"U+{code:04X} {char}"))
    return hits


def check_emojis(repo: Repo, result: CheckResult) -> None:
    """No emojis in agent or command files (errors); CLAUDE.md and docs/ are advisory."""
    strict = [f".claude/agents/{n}" for n in repo.glob_names(".claude/agents")]
    strict += [f".claude/commands/{n}" for n in repo.glob_names(".claude/commands")]
    advisory = ["CLAUDE.md"] + [f"docs/{n}" for n in repo.glob_names("docs")]
    for group, report in ((strict, result.error), (advisory, result.warn)):
        for rel in group:
            text = repo.read_text(rel)
            if text is None:
                continue
            for number, hit in emoji_hits(text):
                report(f"{rel}:{number}: emoji {hit}")


# ---------------------------------------------------------------------------
# Runner
# ---------------------------------------------------------------------------

CHECKS: Tuple[Tuple[str, Callable[[Repo, CheckResult], None]], ...] = (
    ("Required files", check_required_files),
    ("Agents", check_agents),
    ("Commands", check_commands),
    ("Plugin manifest", check_plugin_manifest),
    ("Marketplace", check_marketplace),
    ("Version consistency", check_versions),
    ("Hooks", check_hooks),
    ("Markdown links", check_markdown),
    ("Placeholders and emails", check_placeholders),
    ("No emojis in agents and commands", check_emojis),
)


def run_checks(repo: Repo) -> List[CheckResult]:
    """Run every check group, turning an unexpected crash into an error of that group."""
    results: List[CheckResult] = []
    for title, check in CHECKS:
        result = CheckResult(title)
        try:
            check(repo, result)
        except Exception as exc:  # a validator bug must not hide the other groups
            result.error(f"internal error in check '{title}': {type(exc).__name__}: {exc}")
        results.append(result)
    return results


def plural(count: int, noun: str) -> str:
    """'1 error', '2 errors'."""
    return f"{count} {noun}{'' if count == 1 else 's'}"


def report(results: Sequence[CheckResult], quiet: bool) -> Tuple[int, int]:
    """Print the results and return (errors, warnings)."""
    errors = sum(len(r.errors) for r in results)
    warnings = sum(len(r.warnings) for r in results)
    for result in results:
        if quiet and result.passed:
            continue
        print(f"{'PASS' if result.passed else 'FAIL'}  {result.title}")
        for message in result.errors:
            print(f"      {message}")
        if not quiet:
            for message in result.warnings:
                print(f"      warning: {message}")
    if errors or not quiet:
        print(f"validate.py: {plural(errors, 'error')}, {plural(warnings, 'warning')}")
    return errors, warnings


def main(argv: Optional[Sequence[str]] = None) -> int:
    """Command-line entry point."""
    parser = argparse.ArgumentParser(
        description="Validate the AGEX repository: agents, commands, manifests, hooks, links, and content rules."
    )
    parser.add_argument("--quiet", "-q", action="store_true", help="print errors only")
    parser.add_argument(
        "--root",
        type=Path,
        default=Path(__file__).resolve().parent.parent,
        help="repository root to validate (default: the checkout containing this script)",
    )
    args = parser.parse_args(argv)
    for stream in (sys.stdout, sys.stderr):
        # Messages quote file content (emojis, dashes); never crash on a narrow console encoding.
        if hasattr(stream, "reconfigure"):
            stream.reconfigure(errors="backslashreplace")
    root = args.root.resolve()
    if not root.is_dir():
        print(f"validate.py: root '{root}' is not a directory", file=sys.stderr)
        return 2
    errors, _ = report(run_checks(Repo(root)), args.quiet)
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
