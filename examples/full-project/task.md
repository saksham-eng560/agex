# Example: Build a Streaming CSV-to-JSON Command-Line Tool

This walkthrough follows a COMPLEX `/agex` run that builds a complete tool from an almost empty Python package: a plan with execution waves, research, a design split into three work units, two coders working in parallel, one coder-tester cycle, one coder-reviewer cycle, and a README written by the documenter. It shows how a plan becomes parallel work, how tests derived from the design catch what a quick smoke test misses, and how the quality gate decides that the result is done.

## Scenario

You are starting `csvjson`, a small command-line tool. The repository contains only the skeleton:

| Path | Contents |
|---|---|
| `pyproject.toml` | `name = "csvjson"`, `requires-python = ">=3.11"`, no runtime dependencies, a `dev` extra with pytest, ruff, and mypy; `[tool.pytest.ini_options] testpaths = ["tests"]`; `[tool.mypy] strict = true`; a `src/` layout built with setuptools |
| `src/csvjson/__init__.py` | `__version__ = "0.1.0"` and nothing else |
| `tests/test_version.py` | One test that imports the package and checks `__version__` |
| `README.md` | A single line: `# csvjson` |
| `CLAUDE.md` | Conventions: standard library only at runtime; type hints everywhere and `mypy src` clean in strict mode; `ruff check .` clean; tests in `tests/` named `test_*.py`; user errors go to stderr as one line starting with `csvjson: error:`, never as a traceback. Commands: `python -m pytest`, `ruff check .`, `mypy src` |

The package is installed in a virtual environment with `python -m pip install -e ".[dev]"`, and you start Claude Code from a shell in which `.venv` is activated, so `python`, `ruff`, and `mypy` resolve to the project's environment for every agent.

You want a real tool: convert a CSV file or standard input to JSON, either as one JSON array or as JSON Lines, and handle multi-gigabyte exports from databases and spreadsheets without running out of memory.

## The Command

```text
/agex Build a CLI tool that converts CSV files to JSON with streaming support
```

With a plugin install the same command is `/agex:agex` (typing `/agex` autocompletes it).

## What AGEX Does

`/agex` turns your main conversation into the orchestrator, so every dispatch and any escalation appears in your conversation. Before the model reads the prompt, the command injects your task, the first lines of `CLAUDE.md`, `git status`, and the list of project files. The orchestrator then reads the full `CLAUDE.md` and `pyproject.toml` and puts the three verification commands into every delegation packet.

1. **Complexity classification: COMPLEX.** The task creates a new public interface (a command-line tool), three components (parsing, output, and the CLI itself), and more than five files including tests and documentation. The orchestrator announces the chain planner → researcher → architect → parallel coders → tester ⇄ coder → reviewer ⇄ coder → documenter. Because `.agex/` exists in the project, it also appends `DISPATCH`, `ARTIFACT`, and `CYCLE` events to `.agex/session.log`.
2. **planner → TaskPlan, READY.** Eight steps in seven waves. The request does not say whether the input always has a header row, so instead of stopping with NEEDS_INPUT the planner records the assumption. It places the reader and the writers in the same parallel group, keeps `pyproject.toml` in a single step, and schedules the documenter after the review so the README describes approved behavior.
3. **researcher → ResearchBrief, COMPLETE.** Facts from the Python documentation that shape the design, each with a link:
   - Files read by the `csv` module must be opened with `newline=""`; otherwise line breaks inside quoted fields are not interpreted correctly.
   - `csv.reader.line_num` counts source lines, not records, so it is the right number to put in error messages for records that span lines.
   - The default `csv.field_size_limit()` is 131,072 characters; a longer field raises `csv.Error`.
   - `csv.DictReader` does not reject ragged rows: extra fields go under the key `None` and missing ones become `None`, which `json.dumps` would turn into a `"null"` key. Silent data corruption.
   - `json.dump` serializes a whole object, so streaming a JSON array means writing the brackets and separators yourself and calling `json.dumps` once per record.
   - The `utf-8-sig` codec strips the byte order mark that spreadsheet exports often start with, and decodes files without one exactly like `utf-8`.
4. **architect → TechnicalRFC, PROPOSED.** Three work units. WU-1 (the streaming reader, `src/csvjson/reader.py`) and WU-2 (the JSON writers, `src/csvjson/writers.py`) share no files and depend on nothing, so both are `Parallel-safe: yes`. WU-3 (the CLI, `__main__.py`, and the console-script entry in `pyproject.toml`) imports both and runs after them.
5. **coder (WU-1) and coder (WU-2) in parallel → two CodeDiffs, both IMPLEMENTED.** The orchestrator sends both Agent calls in one message. Each packet names the coder's single file as its exclusive scope and marks the other file and `pyproject.toml` as out of scope. Both coders report `ruff check .` → All checks passed!, `mypy src` → Success, and the existing version test passing. Neither writes tests; that is the tester's job.
6. **coder (WU-3) → CodeDiff, IMPLEMENTED.** Adds `build_parser()` and `main()`, `python -m csvjson`, and `[project.scripts] csvjson = "csvjson.cli:main"`, re-installs the package so the `csvjson` script exists, and runs a smoke test: `printf 'id,name\n1,Ada\n' | csvjson -f ndjson` prints `{"id": "1", "name": "Ada"}`.
7. **tester → TestReport, FAIL (first test run; the coder-tester loop begins).** The tester writes unit tests for the reader and writers and CLI tests through both `main()` and a `python -m csvjson` subprocess: 34 tests, 32 passing. Both failures sit in one helper in `src/csvjson/cli.py`: standard input is read through `sys.stdin`, which ignores `--encoding`, so a byte order mark ends up in the first key; and files are opened without `newline=""`, so a line break inside a quoted field comes back altered. The RFC specified both details; the smoke test in step 6 could not reveal either, and the tests written from the RFC's Test Requirements did.
8. **coder (WU-3) → CodeDiff, IMPLEMENTED (coder-tester cycle 1 of 3).** The orchestrator logs `CYCLE loop=coder-tester n=1/3` and forwards the Failure Traces verbatim. The coder opens files with `newline=""` and wraps `sys.stdin.buffer` in `io.TextIOWrapper` with the same encoding and newline settings. Only WU-3's counter moves; WU-1 and WU-2 had no failures and keep their full budgets.
9. **tester → TestReport, PASS (closes coder-tester cycle 1).** 34 of 34 pass.
10. **reviewer → ReviewVerdict, CHANGES_REQUESTED (first review; the coder-reviewer loop begins).** Two MEDIUM issues and one LOW, all in the CLI. A conversion that fails halfway leaves a truncated, invalid output file behind (and has already destroyed any previous file at that path). Piping the output into a program that exits early, such as `head`, prints a `BrokenPipeError` traceback. The LOW item, accepting `\t` as a tab delimiter, is non-blocking.
11. **coder (WU-3) → CodeDiff, IMPLEMENTED (coder-reviewer cycle 1 of 3).** Output files are now written to a temporary file in the target directory and moved into place with `os.replace` only after the conversion succeeds; the temporary file is removed on any error. A closed output pipe is handled as the Python `signal` documentation recommends: standard output is pointed at `os.devnull` and the tool exits with status 1, without a traceback.
12. **tester → TestReport, PASS.** A review-driven fix is re-tested before the re-review. The tester adds three regression tests: a failed conversion leaves no output file and no temporary file, an existing output file survives a failed conversion unchanged, and a subprocess writing 200,000 rows into a pipe that closes after one line exits with status 1 and no traceback. 37 of 37 pass.
13. **reviewer → ReviewVerdict, APPROVED (closes coder-reviewer cycle 1).** R-1 and R-2 are resolved; R-3 stays listed as a non-blocking LOW item.
14. **documenter → DocUpdate, COMPLETE.** Expands `README.md` from its single title line into Installation, Usage, Options, Output Formats, Exit Codes, Streaming and Memory, and Limitations sections. The documenter has no shell, so it checks every example against the argument parser in `src/csvjson/cli.py` and says so, rather than claiming it ran them.
15. **Quality gate and AgexReport, DONE.** The latest TestReport is PASS, the latest ReviewVerdict is APPROVED, no security findings are open, and every acceptance criterion of WU-1 to WU-3 is checked. The run used 14 dispatches, one below the soft budget of 15.

## Illustrative Artifact Excerpts

The excerpts below are illustrative. They show the envelope, section order, and level of detail you should expect, abridged for length. They are not captured output from a recorded run.

### TaskPlan

```markdown
<!-- agex:artifact type=TaskPlan version=1 -->
## TaskPlan: Streaming CSV-to-JSON command-line tool
**Producer:** planner · **Status:** READY · **Confidence:** HIGH

### Goal
`csvjson` converts a CSV file or stdin to a JSON array or JSON Lines without loading the input into
memory, is installed as a console script, passes pytest, ruff, and mypy, and is documented in README.md.

### Assumptions
- Standard library only at runtime — CLAUDE.md:5
- Python 3.11 or later, with argparse for the CLI — pyproject.toml:4 (requires-python = ">=3.11")
- The first CSV row is always a header — not stated in the request; recorded here instead of asking

### Steps
| # | Step | Agent | Depends On | Parallel Group | Complexity (S/M/L) | Done When |
|---|---|---|---|---|---|---|
| 1 | Establish the csv, json, and packaging facts that constrain a streaming design | researcher | — | — | S | ResearchBrief COMPLETE with documentation links |
| 2 | Design modules, interfaces, the CLI contract, and work units | architect | 1 | — | M | TechnicalRFC PROPOSED with acceptance criteria per work unit |
| 3 | Implement the streaming reader | coder | 2 | A | M | `mypy src` and `ruff check .` clean |
| 4 | Implement the JSON array and JSON Lines writers | coder | 2 | A | S | `mypy src` and `ruff check .` clean |
| 5 | Implement the CLI and the console-script entry point | coder | 3, 4 | — | M | `csvjson --help` exits 0 |
| 6 | Write and run unit and CLI tests | tester | 5 | — | M | `python -m pytest` passes |
| 7 | Review the complete change | reviewer | 6 | — | M | ReviewVerdict APPROVED |
| 8 | Document installation, usage, options, and exit codes in README.md | documenter | 7 | — | S | Every CLI option appears in README.md |

### Execution Waves
- Wave 1: step 1 (sequential)
- Wave 2: step 2 (sequential)
- Wave 3: steps 3, 4 (parallel)
- Wave 4: step 5 (sequential)
- Wave 5: step 6 (sequential)
- Wave 6: step 7 (sequential)
- Wave 7: step 8 (sequential)

### Risks & Mitigations
- json.dump needs the whole list in memory — the writers emit brackets and separators themselves
- Parallel coders editing pyproject.toml — only step 5 touches it
- Feedback cycles exhausting the budget — 8 planned dispatches leave 7 for cycles within the soft cap of 15

### Open Questions
- None
```

### TechnicalRFC (abridged)

```markdown
<!-- agex:artifact type=TechnicalRFC version=1 -->
## TechnicalRFC: csvjson streaming converter
**Producer:** architect · **Status:** PROPOSED · **Confidence:** HIGH

### Context & Goals
Add a `csvjson` command to the package in src/csvjson/ that converts CSV to a JSON array or JSON Lines
using only the standard library (CLAUDE.md:5). Memory use must not grow with the number of rows: records
flow one at a time from csv.reader to the output stream.

### Non-Goals
- Type inference: every value is emitted as a JSON string.
- Compressed input, URLs, and spreadsheet formats other than CSV.

### Component Architecture
- reader (src/csvjson/reader.py, new) — wraps csv.reader; header checks, field-count checks, CsvFormatError
- writers (src/csvjson/writers.py, new) — incremental JSON array and JSON Lines writers over any iterable
- cli (src/csvjson/cli.py and src/csvjson/__main__.py, new) — argparse interface, stream setup, exit codes
- packaging (pyproject.toml) — [project.scripts] csvjson = "csvjson.cli:main"

### Data Flow
~~~mermaid
flowchart LR
    Src[file or stdin] --> Open["cli: open with newline='' and --encoding"]
    Open --> Reader[reader.iter_records]
    Reader --> Writer["writers: write_json_array or write_ndjson"]
    Writer --> Dst[file or stdout]
~~~

### Interface & Type Definitions
~~~python
class CsvFormatError(ValueError):
    line: int  # source line on which the bad record ends (csv.reader.line_num)

def iter_records(stream: TextIO, *, delimiter: str = ",") -> Iterator[dict[str, str]]: ...
def write_json_array(records: Iterable[Mapping[str, str]], out: TextIO) -> int: ...
def write_ndjson(records: Iterable[Mapping[str, str]], out: TextIO) -> int: ...
def build_parser() -> argparse.ArgumentParser: ...
def main(argv: Sequence[str] | None = None) -> int: ...  # 0 success, 1 data or I/O error, 2 usage error
~~~
CLI: csvjson [INPUT] [-o OUTPUT] [-f {array,ndjson}] [-d DELIMITER] [--encoding ENCODING] [--version]
INPUT defaults to "-" (stdin); OUTPUT defaults to stdout; --encoding defaults to utf-8-sig.

### Implementation Sequence
#### WU-1: Streaming reader
- **Files:** src/csvjson/reader.py
- **Change:** CsvFormatError and iter_records(): the first row is the header; blank lines are skipped;
  empty or duplicate header names, rows with a different field count, and any csv.Error (including the
  field size limit) raise CsvFormatError carrying reader.line_num
- **Depends On:** none
- **Acceptance Criteria:** records are yielded lazily; a row with an extra field on source line 3 raises
  CsvFormatError with line == 3; mypy and ruff clean
- **Parallel-safe:** yes

#### WU-2: JSON writers
- **Files:** src/csvjson/writers.py
- **Change:** write_json_array writes "[\n", records separated by ",\n", then "\n]\n" ("[]\n" for no
  records); write_ndjson writes one json.dumps(record, ensure_ascii=False) per line; both return the count
- **Depends On:** none
- **Acceptance Criteria:** array output parses with json.loads, NDJSON parses line by line; records are
  written before the input iterator is exhausted; no list of records is ever built
- **Parallel-safe:** yes

#### WU-3: CLI and entry points
- **Files:** src/csvjson/cli.py, src/csvjson/__main__.py, pyproject.toml
- **Change:** build_parser() and main(); files opened with newline="" and --encoding, stdin wrapped with
  the same settings; errors printed as one "csvjson: error:" line; console script registered
- **Depends On:** WU-1, WU-2
- **Acceptance Criteria:** file and stdin input give identical output; a UTF-8 byte order mark never reaches
  the first key; line breaks inside quoted fields are preserved byte for byte; exit codes 0, 1, and 2
- **Parallel-safe:** no

### Test Requirements
- Unit tests per module; CLI tests through main(argv) with tmp_path and through `python -m csvjson`
  in a subprocess for stdin.
- Inputs: byte order mark, CRLF inside quotes, delimiter and doubled quotes inside quotes, header only,
  empty file, ragged row, duplicate header, a field longer than 131,072 characters.
- A generator that raises after three records proves that both writers stream.

### Alternatives Considered & Risks
- csv.DictReader — rejected: ragged rows become a None key or None values instead of an error.
- pandas read_csv and to_json — rejected: a runtime dependency (CLAUDE.md:5) that loads the whole
  file unless chunked.
- Risk: the csv field size limit — reported as CsvFormatError and documented as a limitation.
```

### TestReport, first test run

```markdown
<!-- agex:artifact type=TestReport version=1 -->
## TestReport: Unit and CLI tests for csvjson
**Producer:** tester · **Status:** FAIL · **Confidence:** HIGH

### Test Suites Executed
- `python -m pytest -q` (exit code 1)

### Pass/Fail Summary
| Suite | Passed | Failed | Skipped |
|---|---|---|---|
| tests/test_version.py | 1 | 0 | 0 |
| tests/test_reader.py | 11 | 0 | 0 |
| tests/test_writers.py | 8 | 0 | 0 |
| tests/test_cli.py | 12 | 2 | 0 |

### Tests Added or Updated
- `tests/test_reader.py` — header handling, blank lines, quoting, ragged rows and duplicate headers raising
  CsvFormatError with the right line, the field size limit
- `tests/test_writers.py` — both formats parse back with json.loads; empty input gives []; non-ASCII text
  is kept; records are written before the input is exhausted
- `tests/test_cli.py` — file and stdin input, -o, both formats, --delimiter, exit codes 0, 1, and 2

### Edge Cases Covered
- Empty file, header-only file, and a missing newline at the end of the file
- Quoted fields containing the delimiter, doubled quotes, and CRLF line breaks
- A UTF-8 byte order mark at the start of the input, read from a file and from stdin
- A generator that raises after three records: all three are already in the output
- An extra field on line 3: exit code 1 and "line 3" in the message

### Failure Traces
1. `tests/test_cli.py::test_bom_is_stripped_when_reading_stdin`
   - Expected: first key "id" when a UTF-8 file with a byte order mark is piped through stdin
   - Actual: first key "\ufeffid"; the same file passed as a path gives "id"
   - Trace excerpt: E AssertionError: assert ['\ufeffid', 'name'] == ['id', 'name']
     E At index 0 diff: '\ufeffid' != 'id' (tests/test_cli.py:63)
   - Suspected location: `src/csvjson/cli.py:47` (stdin is used as sys.stdin, which ignores --encoding
     and the newline setting; the file branch at line 49 honors --encoding)
2. `tests/test_cli.py::test_crlf_inside_quoted_field_is_preserved`
   - Expected: note == "line one\r\nline two"
   - Actual: "line one\nline two"
   - Trace excerpt: E AssertionError: assert 'line one\nline two' == 'line one\r\nline two'
     (tests/test_cli.py:81)
   - Suspected location: `src/csvjson/cli.py:49` (open(path, encoding=args.encoding) without newline="",
     so universal-newline translation rewrites the CRLF before csv.reader sees it)

### Coverage
not measured (pytest-cov is not installed; the tester does not add dependencies)

### Recommendation for Coder
- Open files with `open(path, encoding=args.encoding, newline="")` and read stdin through
  `io.TextIOWrapper(sys.stdin.buffer, encoding=args.encoding, newline="")`, as the RFC's Data Flow specifies.
```

### ReviewVerdict, first review

```markdown
<!-- agex:artifact type=ReviewVerdict version=1 -->
## ReviewVerdict: csvjson reader, writers, and CLI
**Producer:** reviewer · **Status:** CHANGES_REQUESTED · **Confidence:** HIGH

### Summary
Reviewed WU-1 to WU-3 after the coder-tester fix, plus all test files. Streaming holds end to end: no list
of records is built anywhere and both writers emit each record as it arrives. Two MEDIUM error-handling
issues in the CLI break common real-world use and must be fixed; one LOW item is non-blocking.

### Issues
| ID | Severity | Category | Location | Problem | Remediation |
|---|---|---|---|---|---|
| R-1 | MEDIUM | error-handling | `src/csvjson/cli.py:58` | `-o out.json` is opened with mode "w" before conversion starts. A CsvFormatError at row 40,000 exits 1 but leaves a truncated, invalid out.json, and a previous good out.json is already gone | Write to `tempfile.NamedTemporaryFile("w", encoding="utf-8", dir=out.parent, prefix=f".{out.name}.", suffix=".tmp", delete=False)`, `os.replace()` it onto the target only after the writer returns, and unlink it in a `finally` block on any error |
| R-2 | MEDIUM | error-handling | `src/csvjson/cli.py:71` | When the program reading stdout exits early (for example `head -n 5`), the next write raises BrokenPipeError: the user sees a traceback plus an "Exception ignored" message at interpreter exit, which violates CLAUDE.md:9 | Catch BrokenPipeError in main(), point stdout at os.devnull with `os.dup2(os.open(os.devnull, os.O_WRONLY), sys.stdout.fileno())` so the flush at exit cannot fail again, and return 1, as the Python signal module documentation recommends; add a subprocess test |
| R-3 | LOW | edge-case | `src/csvjson/cli.py:33` | `--delimiter '\t'` is two characters (a backslash and a t) and is rejected, so tab-separated input needs `$'\t'` in bash | Non-blocking: accept `\t` and `tab` as aliases for a tab character |

### Checks Performed
- [x] Logic and off-by-one
- [x] Null/undefined handling
- [x] Concurrency and shared state
- [x] Error handling
- [x] Security (OWASP Top 10)
- [x] Performance
- [x] Edge cases
- [x] Test adequacy
- [x] Project conventions

### What Is Good
- Both writers consume their input lazily, and test_writers.py proves it with a generator that fails midway.
- csv.reader with explicit field-count checks turns ragged rows into errors with line numbers instead of silently padded records.
- `mypy src` passes in strict mode with no ignores.
```

### DocUpdate (abridged)

```markdown
<!-- agex:artifact type=DocUpdate version=1 -->
## DocUpdate: README for csvjson
**Producer:** documenter · **Status:** COMPLETE · **Confidence:** HIGH

### Files Created or Updated
- README.md — updated — Installation, Usage, Options, Output Formats, Exit Codes, Streaming and Memory, Limitations

### Summary of Changes
Command-line users can now install csvjson, convert files and pipes in both output formats, and interpret
its error messages and exit codes. The Streaming and Memory section explains that stdout output may already
contain earlier records when a later row is malformed, while -o output is all or nothing.

### Examples Added
- README.md — a file to a JSON array, stdin to JSON Lines, a semicolon-delimited file — checked against
  build_parser() at src/csvjson/cli.py:24; not executed (the documenter has no shell)
- README.md — the error message for a ragged row — checked against src/csvjson/reader.py:41

### Preserved Content
- The existing title line "# csvjson" is unchanged; nothing was removed.

### Follow-ups
- Add a CHANGELOG.md when the first release is tagged.
```

### AgexReport (final)

```markdown
<!-- agex:artifact type=AgexReport version=1 -->
## AgexReport: csvjson, a streaming CSV-to-JSON command-line tool
**Producer:** orchestrator · **Status:** DONE · **Confidence:** HIGH

### Task
Build a CLI tool that converts CSV files to JSON with streaming support. COMPLEX: a new command-line
interface, three components, and more than five files.

### Outcome
`csvjson` (also `python -m csvjson`) converts a CSV file or stdin to a JSON array or JSON Lines in constant
memory, reports malformed rows with their line number, never leaves a partial output file, and exits
quietly when its output pipe closes. 37 tests pass and the README documents every option.

### Agents Deployed
| # | Agent | Artifact | Status | Cycle |
|---|---|---|---|---|
| 1 | planner | TaskPlan | READY | n/a |
| 2 | researcher | ResearchBrief | COMPLETE | n/a |
| 3 | architect | TechnicalRFC | PROPOSED | n/a |
| 4 | coder (WU-1) | CodeDiff | IMPLEMENTED | n/a |
| 5 | coder (WU-2) | CodeDiff | IMPLEMENTED | n/a |
| 6 | coder (WU-3) | CodeDiff | IMPLEMENTED | n/a |
| 7 | tester | TestReport | FAIL | n/a |
| 8 | coder (WU-3) | CodeDiff | IMPLEMENTED | coder-tester 1/3 for WU-3 |
| 9 | tester | TestReport | PASS | coder-tester 1/3 for WU-3 |
| 10 | reviewer | ReviewVerdict | CHANGES_REQUESTED | n/a |
| 11 | coder (WU-3) | CodeDiff | IMPLEMENTED | coder-reviewer 1/3 for WU-3 |
| 12 | tester | TestReport | PASS | coder-reviewer 1/3 for WU-3 |
| 13 | reviewer | ReviewVerdict | APPROVED | coder-reviewer 1/3 for WU-3 |
| 14 | documenter | DocUpdate | COMPLETE | n/a |

### Changes
- Added: src/csvjson/{reader,writers,cli,__main__}.py, tests/{test_reader,test_writers,test_cli}.py
- Modified: pyproject.toml ([project.scripts] csvjson = "csvjson.cli:main"), README.md

### Verification Evidence
- `ruff check .` → All checks passed!
- `mypy src` → Success: no issues found in 5 source files
- `python -m pytest -q` → 37 passed
- ReviewVerdict (coder-reviewer cycle 1): APPROVED; no security findings raised
- Every acceptance criterion of WU-1, WU-2, and WU-3 checked

### Open Issues & Escalations
- R-3 (LOW, non-blocking): accept `\t` and `tab` as --delimiter aliases.
- No escalations.

### Next Steps
1. Review the diff with `git diff` and commit; AGEX never commits.
2. Convert a large real export once and compare the record count with the source.
3. Optional: `/agex Set up GitHub Actions CI that runs ruff, mypy, and pytest on Python 3.11 and 3.12`.
```

### Session log (excerpt)

```text
[2026-09-27T14:02:11Z] SESSION_START source=startup
[2026-09-27T14:03:05Z] DISPATCH agent=planner
[2026-09-27T14:03:52Z] ARTIFACT type=TaskPlan status=READY
[2026-09-27T14:09:40Z] DISPATCH agent=coder unit=WU-1
[2026-09-27T14:09:40Z] DISPATCH agent=coder unit=WU-2
[2026-09-27T14:11:02Z] FILE_MODIFIED tool=Write path=src/csvjson/reader.py
[2026-09-27T14:11:09Z] FILE_MODIFIED tool=Write path=src/csvjson/writers.py
[2026-09-27T14:21:33Z] ARTIFACT type=TestReport status=FAIL
[2026-09-27T14:21:35Z] CYCLE loop=coder-tester n=1/3
[2026-09-27T14:21:35Z] DISPATCH agent=coder unit=WU-3
[2026-09-27T14:31:48Z] ARTIFACT type=ReviewVerdict status=CHANGES_REQUESTED
[2026-09-27T14:31:50Z] CYCLE loop=coder-reviewer n=1/3
[2026-09-27T14:52:07Z] RUN_COMPLETE status=DONE
```

## Expected Outcome

When the run finishes, your working tree contains uncommitted changes and nothing has been pushed:

- **New source:** `src/csvjson/reader.py`, `src/csvjson/writers.py`, `src/csvjson/cli.py`, and `src/csvjson/__main__.py`.
- **Modified:** `pyproject.toml` gains `[project.scripts] csvjson = "csvjson.cli:main"`; `README.md` grows from one line into a complete usage guide.
- **Tests:** `tests/test_reader.py`, `tests/test_writers.py`, and `tests/test_cli.py`; 37 tests in total, including the version test and the regression tests from both feedback loops.
- **No new dependencies:** the runtime uses only the standard library, as `CLAUDE.md` requires.

Verify it yourself, with `.venv` activated. The coder already re-installed the package so that the `csvjson` script exists; repeating it is harmless:

```bash
python -m pip install -e ".[dev]"
ruff check . && mypy src && python -m pytest -q
printf 'id,name\n1,Ada\n2,Grace\n' | csvjson
printf 'id,name\n1,Ada\n2,Grace\n' | csvjson --format ndjson
printf 'id,name\n1,Ada\n2,Grace,extra\n' | csvjson --format ndjson; echo "exit code: $?"
```

The three conversions print:

```text
[
{"id": "1", "name": "Ada"},
{"id": "2", "name": "Grace"}
]
{"id": "1", "name": "Ada"}
{"id": "2", "name": "Grace"}
{"id": "1", "name": "Ada"}
csvjson: error: line 3: expected 2 fields, found 3
exit code: 1
```

The last command shows streaming at work: the first record was already written to stdout when line 3 turned out to be malformed. With `-o`, the output file is created only when the whole conversion succeeds.

To see constant memory use, generate a large file and convert it:

```bash
python -c "import csv, sys; w = csv.writer(sys.stdout); w.writerow(['id', 'value']); w.writerows([i, f'row {i}'] for i in range(2_000_000))" > big.csv
/usr/bin/time -l csvjson big.csv -o big.json
```

`/usr/bin/time -l` is the macOS form; on Linux use `/usr/bin/time -v`. The maximum resident set size should stay roughly the same whether the file has two thousand rows or two million.

## Variations and Tips

- **Preview first.** Run `/agex-plan Build a CLI tool that converts CSV files to JSON with streaming support` to see the TaskPlan and the expected number of dispatches before anything runs. The plan stays in the conversation, and a following `/agex` with the same task uses it as input.
- **State your stack and let conflicts surface.** `/agex Build a CLI tool that converts CSV files to JSON with streaming support, using typer` conflicts with the standard-library-only rule in `CLAUDE.md`. The planner reports that as an Open Question with status NEEDS_INPUT, and the orchestrator asks you before any code is written.
- **Grow the tool in slices.** Once the first version is committed, a follow-up such as `/agex Add an --infer-types flag to csvjson that converts integers, floats, true/false, and empty fields to JSON numbers, booleans, and null` is MEDIUM: one component, a few files, no planner, researcher, or architect, and far fewer dispatches.
- **Add CI as a separate run.** `/agex Set up GitHub Actions CI that runs ruff, mypy, and pytest on Python 3.11 and 3.12` routes to the devops agent, which verifies the workflow locally and stops for your explicit confirmation before anything is pushed.
- **Put your commands in `CLAUDE.md`.** The orchestrator copies the build, lint, and test commands it finds into every delegation packet, so specialists never have to guess how to verify their work.
- **Activate the environment before starting Claude Code.** Agents run commands in fresh shells that inherit the environment Claude Code was started from, so an activated virtual environment (or a tool such as `uv run` named in `CLAUDE.md`) keeps every agent on the project's interpreter and tools.

For the artifact formats used above, see the [Handoff Protocol](../../docs/HANDOFF-PROTOCOL.md); for the other walkthroughs, see the [Examples index](../../docs/EXAMPLES.md).
