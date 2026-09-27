#!/bin/sh
# AGEX session logger, invoked by Claude Code hooks.
#
#   agex-log.sh session-start    # SessionStart hook
#   agex-log.sh file-modified    # PostToolUse hook (Write|Edit|MultiEdit)
#
# Claude Code sends the hook payload as JSON on stdin. This script appends one
# line per event to <project>/.agex/session.log, which /agex-status reads.
#
# Design rules:
#   - Always exit 0: logging must never block or fail a Claude Code session.
#   - Only file paths and event names are logged, never file contents.
#   - .agex/ ignores itself (it gets its own .gitignore), so it never shows up
#     in `git status` of the host project.
#   - Set AGEX_DISABLE_LOG=1 to turn logging off entirely.

[ "${AGEX_DISABLE_LOG:-0}" = "1" ] && exit 0

event="${1:-}"
input="$(cat 2>/dev/null || true)"

# json_get <jq-path> <dotted.key.path>
# Reads a string field from the hook JSON using jq, then python3, then sed.
json_get() {
  if command -v jq >/dev/null 2>&1; then
    if value="$(printf '%s' "$input" | jq -r "$1 // empty" 2>/dev/null)"; then
      printf '%s' "$value"
      return 0
    fi
  fi
  if command -v python3 >/dev/null 2>&1; then
    if value="$(printf '%s' "$input" | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
    for key in sys.argv[1].split("."):
        data = data.get(key) if isinstance(data, dict) else None
    sys.stdout.write(data if isinstance(data, str) else "")
except Exception:
    sys.exit(1)
' "$2" 2>/dev/null)"; then
      printf '%s' "$value"
      return 0
    fi
  fi
  key="${2##*.}"
  printf '%s' "$input" | tr -d '\r\n' |
    sed -n "s/.*\"$key\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p"
}

# Collapse control characters so one event is always exactly one log line.
clean() {
  printf '%s' "$1" | tr '\r\n\t' '   '
}

project_dir="${CLAUDE_PROJECT_DIR:-}"
[ -n "$project_dir" ] || project_dir="$(json_get .cwd cwd)"
[ -n "$project_dir" ] || project_dir="$(pwd)"

log_dir="$project_dir/.agex"
log_file="$log_dir/session.log"

mkdir -p "$log_dir" 2>/dev/null || exit 0
[ -f "$log_dir/.gitignore" ] || printf '*\n' > "$log_dir/.gitignore" 2>/dev/null

# Keep the log bounded: rotate once it passes 1 MiB.
if [ -f "$log_file" ]; then
  size="$(wc -c < "$log_file" 2>/dev/null | tr -d ' ')"
  if [ "${size:-0}" -gt 1048576 ] 2>/dev/null; then
    mv -f "$log_file" "$log_file.1" 2>/dev/null
  fi
fi

timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

case "$event" in
  session-start)
    source="$(clean "$(json_get .source source)")"
    line="[$timestamp] SESSION_START source=${source:-unknown}"
    ;;
  file-modified)
    tool="$(clean "$(json_get .tool_name tool_name)")"
    path="$(clean "$(json_get .tool_input.file_path tool_input.file_path)")"
    case "$path" in
      "$project_dir"/*) path="${path#"$project_dir"/}" ;;
    esac
    line="[$timestamp] FILE_MODIFIED tool=${tool:-unknown} path=${path:-unknown}"
    ;;
  *)
    exit 0
    ;;
esac

printf '%s\n' "$line" >> "$log_file" 2>/dev/null
exit 0
