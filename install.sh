#!/usr/bin/env bash
#
# AGEX installer for macOS and Linux.
#
# Links the AGEX agents and slash commands from a checkout of the repository
# into your Claude Code configuration (~/.claude/agents and ~/.claude/commands)
# so they are available in every project.
#
#   curl -fsSL https://raw.githubusercontent.com/saksham-eng560/agex/main/install.sh | bash
#   ./install.sh --help
#
# Apart from "set", every command lives in a function and the only top-level
# call is main on the last line, so a partially downloaded script (for example
# an interrupted curl | bash) defines functions but never runs any of them.
#
# Compatible with the Bash 3.2 that ships with macOS: no associative arrays,
# no mapfile, no ${var,,}, no readlink -f.

set -euo pipefail

agex_init_globals() {
  DEFAULT_REPO="https://github.com/saksham-eng560/agex.git"
  REPO_URL="https://github.com/saksham-eng560/agex"
  NL='
'
  UNINSTALL=0
  FORCE=0
  NO_UPDATE=0
  DIR_OPT=""
  DIR_OPT_SET=0

  AGEX_HOME_DIR=""
  AGEX_REPO_URL=""
  CLAUDE_DIR=""
  MANIFEST=""
  SRC=""
  MSRC=""
  MANIFEST_ENTRIES=""
  MANIFEST_FOUND=0
  INSTALLED=""
  AGEX_DESTS=""
  BACKUP_DIR=""

  N_LINKED=0
  N_UPDATED=0
  N_UNCHANGED=0
  N_SKIPPED=0
  N_BACKED_UP=0
  N_PRUNED=0
  N_AGENTS=0
  N_COMMANDS=0
  N_AGENTS_TOTAL=0
  N_COMMANDS_TOTAL=0
  N_COLLISIONS=0
  N_RESTORED=0
  N_KEPT=0
}

# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------

agex_setup_colors() {
  C_RESET="" C_BOLD="" C_DIM="" C_GREEN="" C_YELLOW="" C_BLUE="" C_PURPLE="" C_CYAN=""
  E_RESET="" E_RED="" E_YELLOW=""
  if [ -z "${NO_COLOR:-}" ] && [ "${TERM:-}" != "dumb" ]; then
    if [ -t 1 ]; then
      C_RESET=$'\033[0m'
      C_BOLD=$'\033[1m'
      C_DIM=$'\033[2m'
      C_GREEN=$'\033[32m'
      C_YELLOW=$'\033[33m'
      C_BLUE=$'\033[34m'
      C_PURPLE=$'\033[35m'
      C_CYAN=$'\033[36m'
    fi
    if [ -t 2 ]; then
      E_RESET=$'\033[0m'
      E_RED=$'\033[1;31m'
      E_YELLOW=$'\033[33m'
    fi
  fi
}

agex_step() {
  printf '\n%s==>%s %s%s%s\n' "${C_BLUE}${C_BOLD}" "$C_RESET" "$C_BOLD" "$*" "$C_RESET"
}

agex_info() {
  printf '    %s\n' "$*"
}

agex_ok() {
  printf '  %s+%s %s\n' "$C_GREEN" "$C_RESET" "$*"
}

agex_note() {
  printf '  %s-%s %s\n' "$C_DIM" "$C_RESET" "$*"
}

agex_warn() {
  printf '%swarning:%s %s\n' "$E_YELLOW" "$E_RESET" "$*" >&2
}

agex_die() {
  printf '%serror:%s %s\n' "$E_RED" "$E_RESET" "$*" >&2
  exit 1
}

agex_usage_error() {
  printf '%serror:%s %s\n' "$E_RED" "$E_RESET" "$*" >&2
  printf 'Run with --help for usage.\n' >&2
  exit 2
}

agex_banner() {
  printf '%s' "${C_PURPLE}${C_BOLD}"
  printf '%s\n' '    ___   ____________ _  __'
  printf '%s\n' '   /   | / ____/ ____/| |/ /'
  printf '%s\n' '  / /| |/ / __/ __/   |   /'
  printf '%s\n' ' / ___ / /_/ / /___  /   |'
  printf '%s\n' '/_/  |_\____/_____/ /_/|_|'
  printf '%s' "$C_RESET"
  printf '\n%sThe Master Agent Orchestrator for Claude Code%s\n' "$C_CYAN" "$C_RESET"
}

agex_usage() {
  cat <<'EOF'
AGEX installer for macOS and Linux

Links the AGEX agents and slash commands into your Claude Code configuration
($CLAUDE_HOME/agents and $CLAUDE_HOME/commands) so they work in every project.

Usage:
  ./install.sh [options]
  curl -fsSL https://raw.githubusercontent.com/saksham-eng560/agex/main/install.sh | bash
  curl -fsSL https://raw.githubusercontent.com/saksham-eng560/agex/main/install.sh | bash -s -- [options]

Options:
  --uninstall     Remove the AGEX links, restore files that --force backed up,
                  and leave the AGEX checkout in place
  --force         Move existing files that have the same names as AGEX files
                  to $CLAUDE_HOME/.agex-backup/<timestamp>/, then link AGEX
  --dir <path>    Use the AGEX checkout at <path> instead of ~/.agex
                  (it is cloned there if the directory does not exist)
  --no-update     Do not run git pull on an existing checkout
  -h, --help      Show this help and exit

Environment:
  AGEX_HOME       Checkout location (default: ~/.agex)
  AGEX_REPO       Repository to clone (default: https://github.com/saksham-eng560/agex.git)
  CLAUDE_HOME     Claude Code configuration directory (default: ~/.claude)
  NO_COLOR        Set to any non-empty value to disable colored output

Where the AGEX files come from, in order:
  1. --dir <path>, when given
  2. the directory that contains this script, when it is run from an AGEX checkout
  3. AGEX_HOME: updated with git pull --ff-only when it exists, cloned when it does not

Existing files are never overwritten: without --force they are skipped with a
warning. --uninstall removes only links that AGEX created and never deletes the
checkout. The plugin install is an alternative that namespaces every agent as
agex:<name>:
  claude plugin marketplace add saksham-eng560/agex
  claude plugin install agex@agex-marketplace

Examples:
  ./install.sh                          Install, or refresh an existing install
  ./install.sh --no-update              Refresh the links without pulling
  ./install.sh --force                  Replace same-named files (they are backed up)
  ./install.sh --dir ~/src/agex         Link a checkout somewhere else
  ./install.sh --uninstall              Remove AGEX from ~/.claude
  CLAUDE_HOME=/tmp/claude ./install.sh  Install into another configuration directory
EOF
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

agex_count_up() {
  # Increment a global counter by name (Bash 3.2 has no namerefs).
  eval "$1=\$(( $1 + 1 ))"
}

agex_expand_tilde() {
  case "$1" in
    \~) printf '%s\n' "$HOME" ;;
    \~/*) printf '%s/%s\n' "$HOME" "${1#\~/}" ;;
    *) printf '%s\n' "$1" ;;
  esac
}

agex_absolute() {
  # Absolute form of a path that may not exist yet (no symlink resolution).
  local p
  p="$(agex_expand_tilde "$1")"
  case "$p" in
    /*) ;;
    *) p="$PWD/$p" ;;
  esac
  while :; do
    case "$p" in
      */) [ "$p" = "/" ] && break; p="${p%/}" ;;
      *) break ;;
    esac
  done
  printf '%s\n' "$p"
}

agex_physical_dir() {
  # Physical absolute path of an existing directory.
  (cd "$1" 2>/dev/null && pwd -P)
}

agex_display() {
  # Show paths under $HOME with a leading ~ for readability.
  case "$1" in
    "$HOME") printf '%s\n' '~' ;;
    "$HOME"/*) printf '%s/%s\n' '~' "${1#"$HOME"/}" ;;
    *) printf '%s\n' "$1" ;;
  esac
}

agex_shell_quote() {
  local s="$1" q="'" out=""
  while :; do
    case "$s" in
      *"$q"*)
        out="$out${s%%"$q"*}'\\''"
        s="${s#*"$q"}"
        ;;
      *)
        out="$out$s"
        break
        ;;
    esac
  done
  printf "'%s'\n" "$out"
}

agex_cmd_path() {
  # A path ready to paste into a shell: ~/... when it is safe, quoted otherwise.
  local d
  d="$(agex_display "$1")"
  case "$d" in
    *[!A-Za-z0-9_./~+-]* | "") agex_shell_quote "$1" ;;
    *) printf '%s\n' "$d" ;;
  esac
}

agex_path_under() {
  # True when path $1 is strictly inside directory $2.
  [ -n "$2" ] || return 1
  case "$1" in
    "$2"/*) return 0 ;;
  esac
  return 1
}

agex_list_has() {
  # True when the newline-separated list $1 contains the line $2.
  case "$NL$1$NL" in
    *"$NL$2$NL"*) return 0 ;;
  esac
  return 1
}

agex_exists() {
  [ -e "$1" ] || [ -L "$1" ]
}

agex_dir_is_empty() {
  local entry
  for entry in "$1"/* "$1"/.[!.]* "$1"/..?*; do
    if agex_exists "$entry"; then
      return 1
    fi
  done
  return 0
}

agex_is_checkout() {
  [ -f "$1/.claude/agents/orchestrator.md" ] && [ -f "$1/.claude-plugin/plugin.json" ]
}

agex_frontmatter_name() {
  # Print the "name:" value from a Markdown file's YAML frontmatter.
  awk -v q="'" '
    { sub(/\r$/, "") }
    NR == 1 { if ($0 != "---") exit; next }
    $0 == "---" { exit }
    /^name[ \t]*:/ {
      v = $0
      sub(/^name[ \t]*:[ \t]*/, "", v)
      sub(/[ \t]+$/, "", v)
      first = substr(v, 1, 1)
      if (length(v) >= 2 && (first == "\"" || first == q) && substr(v, length(v), 1) == first) {
        v = substr(v, 2, length(v) - 2)
      }
      print v
      exit
    }
  ' "$1" 2>/dev/null || true
}

agex_plugin_version() {
  local file="$1/.claude-plugin/plugin.json"
  [ -f "$file" ] || return 0
  sed -n 's/^[[:space:]]*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$file" | sed -n '1p'
}

agex_git_head() {
  git -C "$1" rev-parse --short HEAD 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# Arguments and environment
# ---------------------------------------------------------------------------

agex_parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --uninstall) UNINSTALL=1 ;;
      --force) FORCE=1 ;;
      --no-update) NO_UPDATE=1 ;;
      --dir)
        [ "$#" -ge 2 ] || agex_usage_error "--dir needs a path, for example: --dir ~/src/agex"
        DIR_OPT="$2"
        DIR_OPT_SET=1
        shift
        ;;
      --dir=*)
        DIR_OPT="${1#--dir=}"
        DIR_OPT_SET=1
        ;;
      -h | --help)
        agex_usage
        exit 0
        ;;
      *) agex_usage_error "Unknown option: $1" ;;
    esac
    shift
  done
  if [ "$DIR_OPT_SET" -eq 1 ] && [ -z "$DIR_OPT" ]; then
    agex_usage_error "--dir needs a non-empty path"
  fi
}

agex_read_env() {
  [ -n "${HOME:-}" ] || agex_die "HOME is not set; set HOME or CLAUDE_HOME and AGEX_HOME explicitly."
  AGEX_HOME_DIR="$(agex_absolute "${AGEX_HOME:-$HOME/.agex}")"
  AGEX_REPO_URL="${AGEX_REPO:-$DEFAULT_REPO}"
  CLAUDE_DIR="$(agex_absolute "${CLAUDE_HOME:-$HOME/.claude}")"
  MANIFEST="$CLAUDE_DIR/.agex-manifest"
}

agex_check_platform() {
  local os
  os="$(uname -s 2>/dev/null || echo unknown)"
  case "$os" in
    MINGW* | MSYS* | CYGWIN*)
      agex_warn "This looks like a Windows shell ($os). Symbolic links made here may not work for Claude Code; on Windows, run install.ps1 in PowerShell instead."
      ;;
  esac
}

# ---------------------------------------------------------------------------
# Manifest
# ---------------------------------------------------------------------------

agex_load_manifest() {
  MSRC=""
  MANIFEST_ENTRIES=""
  MANIFEST_FOUND=0
  [ -f "$MANIFEST" ] || return 0
  MANIFEST_FOUND=1
  local line
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    case "$line" in
      "" | "#"*) ;;
      source=*) MSRC="${line#source=}" ;;
      /*) MANIFEST_ENTRIES="$MANIFEST_ENTRIES$line$NL" ;;
      *) ;;
    esac
  done <"$MANIFEST"
}

agex_write_manifest() {
  local tmp="$MANIFEST.tmp.$$"
  {
    printf '%s\n' "# AGEX install manifest"
    printf 'source=%s\n' "$SRC"
    printf '%s' "$INSTALLED"
  } >"$tmp" || agex_die "Could not write $tmp"
  mv -f "$tmp" "$MANIFEST" || agex_die "Could not write $MANIFEST"
}

# True when $1 is a symlink that AGEX created: it points into the current
# source checkout, or it is recorded in the manifest and points into the
# checkout the manifest was written for.
agex_is_agex_link() {
  local dest="$1" target
  [ -L "$dest" ] || return 1
  target="$(readlink "$dest")" || return 1
  if agex_path_under "$target" "$SRC/.claude"; then
    return 0
  fi
  if [ -n "$MSRC" ] && agex_list_has "$MANIFEST_ENTRIES" "$dest" && agex_path_under "$target" "$MSRC/.claude"; then
    return 0
  fi
  return 1
}

# ---------------------------------------------------------------------------
# Source checkout
# ---------------------------------------------------------------------------

agex_script_checkout() {
  # Print the checkout this script runs from, if it is run from a file in one.
  local src="${BASH_SOURCE[0]:-}" link dir
  if [ -z "$src" ] || [ ! -f "$src" ]; then
    return 1
  fi
  while [ -L "$src" ]; do
    link="$(readlink "$src")" || return 1
    case "$link" in
      /*) src="$link" ;;
      *) src="$(dirname "$src")/$link" ;;
    esac
  done
  dir="$(agex_physical_dir "$(dirname "$src")")" || return 1
  agex_is_checkout "$dir" || return 1
  printf '%s\n' "$dir"
}

agex_update_checkout() {
  local dir="$1" prefix before after
  if [ "$NO_UPDATE" -eq 1 ]; then
    agex_note "Not updating the checkout (--no-update)."
    return 0
  fi
  if ! command -v git >/dev/null 2>&1; then
    agex_warn "git is not installed, so the checkout was not updated. Continuing with the files as they are."
    return 0
  fi
  if ! prefix="$(git -C "$dir" rev-parse --show-prefix 2>/dev/null)"; then
    agex_note "$(agex_display "$dir") is not a git clone; using it as it is."
    return 0
  fi
  if [ -n "$prefix" ]; then
    agex_note "$(agex_display "$dir") is inside another git repository; not updating it."
    return 0
  fi
  before="$(agex_git_head "$dir")"
  if [ -n "$(git -C "$dir" status --porcelain --untracked-files=no 2>/dev/null || true)" ]; then
    agex_warn "$(agex_display "$dir") has uncommitted changes, so it was not updated. Continuing with the current version${before:+ ($before)}. Commit or stash your changes to take updates."
    return 0
  fi
  if ! git -C "$dir" rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1; then
    agex_warn "The current branch of $(agex_display "$dir") has no upstream branch, so it was not updated. Continuing with the current version${before:+ ($before)}."
    return 0
  fi
  agex_info "Updating $(agex_display "$dir") with git pull --ff-only"
  if git -C "$dir" pull --ff-only --quiet </dev/null; then
    after="$(agex_git_head "$dir")"
    if [ "$before" = "$after" ]; then
      agex_ok "Already up to date${after:+ ($after)}."
    else
      agex_ok "Updated ${before:-unknown} -> ${after:-unknown}."
    fi
  else
    agex_warn "git pull failed (offline, or the local branch has diverged). Continuing with the current version${before:+ ($before)}."
  fi
}

agex_clone_checkout() {
  local dir="$1" parent
  if ! command -v git >/dev/null 2>&1; then
    agex_die "git is required to download AGEX but was not found. Install git and run this installer again, or download the repository from $REPO_URL and run its install.sh."
  fi
  parent="$(dirname "$dir")"
  mkdir -p "$parent" || agex_die "Could not create $parent"
  agex_info "Cloning $AGEX_REPO_URL into $(agex_display "$dir")"
  if ! git clone --depth 1 --quiet -- "$AGEX_REPO_URL" "$dir" </dev/null; then
    agex_die "Could not clone $AGEX_REPO_URL. Check your network connection and the AGEX_REPO value, then run the installer again."
  fi
  agex_ok "Cloned $(agex_display "$dir")."
}

# Resolve (and, when needed, clone or update) the checkout at $1.
agex_use_checkout_dir() {
  local dir="$1" label="$2" phys
  if [ -d "$dir" ]; then
    phys="$(agex_physical_dir "$dir")" || agex_die "Cannot access $dir"
    if agex_is_checkout "$phys"; then
      SRC="$phys"
      agex_ok "Using the AGEX checkout at $(agex_display "$SRC") ($label)."
      agex_update_checkout "$SRC"
      return 0
    fi
    if ! agex_dir_is_empty "$phys"; then
      agex_die "$dir exists but is not an AGEX checkout (no .claude/agents/orchestrator.md or .claude-plugin/plugin.json). Nothing was changed. Move it aside, or choose another location with --dir <path> or AGEX_HOME."
    fi
    agex_clone_checkout "$phys"
    SRC="$phys"
  elif agex_exists "$dir"; then
    agex_die "$dir exists and is not a directory. Nothing was changed. Choose another location with --dir <path> or AGEX_HOME."
  else
    agex_clone_checkout "$dir"
    SRC="$(agex_physical_dir "$dir")" || agex_die "Cannot access $dir after cloning"
  fi
  if ! agex_is_checkout "$SRC"; then
    agex_die "The repository cloned into $SRC does not look like AGEX (no .claude/agents/orchestrator.md). Check AGEX_REPO ($AGEX_REPO_URL), remove $SRC, and try again."
  fi
}

agex_resolve_source() {
  local self
  if [ "$DIR_OPT_SET" -eq 1 ]; then
    agex_use_checkout_dir "$(agex_absolute "$DIR_OPT")" "from --dir"
    return 0
  fi
  if self="$(agex_script_checkout)"; then
    SRC="$self"
    agex_ok "Using the AGEX checkout at $(agex_display "$SRC") (where this script lives)."
    agex_update_checkout "$SRC"
    return 0
  fi
  agex_use_checkout_dir "$AGEX_HOME_DIR" "AGEX_HOME"
}

# Best-effort source lookup for --uninstall: never clones or updates.
agex_resolve_source_quietly() {
  local dir self
  SRC=""
  if [ "$DIR_OPT_SET" -eq 1 ]; then
    dir="$(agex_absolute "$DIR_OPT")"
  elif self="$(agex_script_checkout)"; then
    SRC="$self"
    return 0
  else
    dir="$AGEX_HOME_DIR"
  fi
  if [ -d "$dir" ]; then
    SRC="$(agex_physical_dir "$dir" || printf '%s' "$dir")"
  else
    SRC="$dir"
  fi
}

# ---------------------------------------------------------------------------
# Install
# ---------------------------------------------------------------------------

agex_backup_item() {
  local dest="$1" kind="$2" name="$3" stamp target
  if [ -z "$BACKUP_DIR" ]; then
    stamp="$(date -u +%Y%m%dT%H%M%SZ)"
    BACKUP_DIR="$CLAUDE_DIR/.agex-backup/$stamp"
    if agex_exists "$BACKUP_DIR"; then
      BACKUP_DIR="$BACKUP_DIR-$$"
    fi
  fi
  mkdir -p "$BACKUP_DIR/$kind" || agex_die "Could not create $BACKUP_DIR/$kind"
  target="$BACKUP_DIR/$kind/$name"
  mv "$dest" "$target" || agex_die "Could not move $dest to $target"
  agex_count_up N_BACKED_UP
  agex_note "Backed up $(agex_display "$dest") to $(agex_display "$target")"
}

agex_make_link() {
  local src="$1" dest="$2"
  ln -s "$src" "$dest" || agex_die "Could not create the link $dest"
  if [ ! -L "$dest" ]; then
    rm -f "$dest"
    agex_die "This system created a copy instead of a symbolic link at $dest. On Windows, run install.ps1 in PowerShell instead."
  fi
}

agex_link_one() {
  local src="$1" kind="$2" name dest target
  name="$(basename "$src")"
  dest="$CLAUDE_DIR/$kind/$name"
  AGEX_DESTS="$AGEX_DESTS$dest$NL"

  if [ -L "$dest" ]; then
    target="$(readlink "$dest" || true)"
    if [ "$target" = "$src" ]; then
      agex_count_up N_UNCHANGED
      INSTALLED="$INSTALLED$dest$NL"
      return 0
    fi
    if agex_is_agex_link "$dest"; then
      rm -f "$dest"
      agex_make_link "$src" "$dest"
      agex_count_up N_UPDATED
      agex_ok "Updated $kind/$name"
      INSTALLED="$INSTALLED$dest$NL"
      return 0
    fi
  fi

  if agex_exists "$dest"; then
    if [ "$FORCE" -eq 1 ]; then
      agex_backup_item "$dest" "$kind" "$name"
      agex_make_link "$src" "$dest"
      agex_count_up N_LINKED
      agex_ok "Linked $kind/$name (replaced the previous file)"
      INSTALLED="$INSTALLED$dest$NL"
      return 0
    fi
    agex_count_up N_SKIPPED
    agex_warn "Skipped $(agex_display "$dest"): a file that AGEX did not create is already there."
    return 0
  fi

  agex_make_link "$src" "$dest"
  agex_count_up N_LINKED
  agex_ok "Linked $kind/$name"
  INSTALLED="$INSTALLED$dest$NL"
}

agex_link_kind() {
  local kind="$1" f before_linked before_updated before_unchanged total=0 done_count
  before_linked="$N_LINKED"
  before_updated="$N_UPDATED"
  before_unchanged="$N_UNCHANGED"
  for f in "$SRC/.claude/$kind/"*.md; do
    [ -f "$f" ] || continue
    total=$((total + 1))
    agex_link_one "$f" "$kind"
  done
  done_count=$(((N_LINKED - before_linked) + (N_UPDATED - before_updated) + (N_UNCHANGED - before_unchanged)))
  if [ "$kind" = "agents" ]; then
    N_AGENTS="$done_count"
    N_AGENTS_TOTAL="$total"
  else
    N_COMMANDS="$done_count"
    N_COMMANDS_TOTAL="$total"
  fi
}

agex_prune_stale() {
  # Remove links from a previous install whose source file no longer exists
  # in the checkout (for example an agent removed in a newer release).
  local dest
  while IFS= read -r dest; do
    [ -n "$dest" ] || continue
    agex_list_has "$INSTALLED" "$dest" && continue
    agex_list_has "$AGEX_DESTS" "$dest" && continue
    if agex_path_under "$dest" "$CLAUDE_DIR/agents" || agex_path_under "$dest" "$CLAUDE_DIR/commands"; then
      if agex_is_agex_link "$dest"; then
        rm -f "$dest"
        agex_count_up N_PRUNED
        agex_note "Removed stale link $(agex_display "$dest")"
      fi
    fi
  done <<EOF
$MANIFEST_ENTRIES
EOF
}

agex_check_collisions() {
  local names="" f n stem
  for f in "$SRC/.claude/agents/"*.md; do
    [ -f "$f" ] || continue
    n="$(agex_frontmatter_name "$f")"
    if [ -z "$n" ]; then
      stem="$(basename "$f")"
      n="${stem%.md}"
    fi
    names="$names$n$NL"
  done
  for f in "$CLAUDE_DIR/agents/"*.md; do
    agex_list_has "$AGEX_DESTS" "$f" && continue
    [ -f "$f" ] || continue
    n="$(agex_frontmatter_name "$f")"
    [ -n "$n" ] || continue
    if agex_list_has "$names" "$n"; then
      agex_count_up N_COLLISIONS
      agex_warn "$(agex_display "$f") declares \"name: $n\", the same name as the AGEX $n agent. Two user agents with one name conflict and only one of them is used. Rename one of them, or use the plugin install, which scopes AGEX agents as agex:$n."
    fi
  done
}

agex_print_summary() {
  local version checkout_q uninstall_cmd docs skip_color=""
  version="$(agex_plugin_version "$SRC")"
  checkout_q="$(agex_cmd_path "$SRC")"
  uninstall_cmd="$(agex_cmd_path "$SRC/install.sh") --uninstall"
  if [ -f "$SRC/docs/CUSTOMIZATION.md" ]; then
    docs="$(agex_display "$SRC")/docs/CUSTOMIZATION.md"
  else
    docs="$REPO_URL/blob/main/docs/CUSTOMIZATION.md"
  fi

  if [ "$N_SKIPPED" -gt 0 ]; then
    printf '\n%s%s==> AGEX%s is installed, but %s file(s) were skipped%s\n' "$C_YELLOW" "$C_BOLD" "${version:+ $version}" "$N_SKIPPED" "$C_RESET"
  else
    printf '\n%s%s==> AGEX%s is installed%s\n' "$C_GREEN" "$C_BOLD" "${version:+ $version}" "$C_RESET"
  fi
  printf '    %-10s %s\n' "Checkout" "$(agex_display "$SRC")"
  printf '    %-10s %s (%s of %s AGEX agents)\n' "Agents" "$(agex_display "$CLAUDE_DIR/agents")" "$N_AGENTS" "$N_AGENTS_TOTAL"
  printf '    %-10s %s (%s of %s AGEX commands)\n' "Commands" "$(agex_display "$CLAUDE_DIR/commands")" "$N_COMMANDS" "$N_COMMANDS_TOTAL"
  if [ "$N_SKIPPED" -gt 0 ]; then
    skip_color="$C_YELLOW"
  fi
  printf '    %-10s %s%s linked%s, %s updated, %s unchanged, %s%s skipped%s, %s backed up' \
    "Links" "$C_GREEN" "$N_LINKED" "$C_RESET" "$N_UPDATED" "$N_UNCHANGED" \
    "$skip_color" "$N_SKIPPED" "$C_RESET" "$N_BACKED_UP"
  if [ "$N_PRUNED" -gt 0 ]; then
    printf ', %s stale removed' "$N_PRUNED"
  fi
  printf '\n'
  if [ "$N_BACKED_UP" -gt 0 ]; then
    printf '    %-10s %s\n' "Backups" "$(agex_display "$BACKUP_DIR") (restored by --uninstall)"
  fi

  if [ "$N_SKIPPED" -gt 0 ]; then
    printf '\n%sSkipped files were left untouched.%s Either:\n' "$C_YELLOW" "$C_RESET"
    printf '  - re-run with --force to move them to %s and link the AGEX versions, or\n' "$(agex_display "$CLAUDE_DIR/.agex-backup/<timestamp>/")"
    printf '  - install AGEX as a plugin instead; its agents are scoped as agex:<name> and never collide:\n'
    printf '      claude plugin marketplace add saksham-eng560/agex\n'
    printf '      claude plugin install agex@agex-marketplace\n'
  fi

  printf '\n%sNext steps%s\n' "$C_BOLD" "$C_RESET"
  printf '  Restart Claude Code (or start a new session) so it loads the new agents and commands.\n'
  printf '  Then, inside any project:\n\n'
  printf '    %s/agex Build a REST API with authentication%s   full multi-agent run\n' "$C_CYAN" "$C_RESET"
  printf '    %s/agex-plan Add OAuth login to the web app%s    plan only, nothing is executed\n' "$C_CYAN" "$C_RESET"
  printf '    %s/agex-review%s                                 review staged changes or the last commit\n' "$C_CYAN" "$C_RESET"
  printf '    %s/agex-secure%s                                 secrets and vulnerability audit\n' "$C_CYAN" "$C_RESET"
  printf '    %s/agex-status%s                                 agents, session log, project context\n' "$C_CYAN" "$C_RESET"
  printf '    %sclaude --agent orchestrator%s                  run a whole session as the orchestrator\n\n' "$C_CYAN" "$C_RESET"
  printf '  Update:     re-run this installer, or: git -C %s pull\n' "$checkout_q"
  printf '  Uninstall:  %s\n' "$uninstall_cmd"
  printf '  Logging:    session-log hooks are not installed by this script; see %s\n' "$docs"
}

agex_install() {
  agex_banner
  agex_check_platform

  agex_step "Locating AGEX"
  agex_resolve_source

  [ -f "$SRC/.claude/agents/orchestrator.md" ] || agex_die "$SRC has no .claude/agents/orchestrator.md"

  agex_step "Linking into $(agex_display "$CLAUDE_DIR")"
  mkdir -p "$CLAUDE_DIR/agents" "$CLAUDE_DIR/commands" || agex_die "Could not create $CLAUDE_DIR/agents and $CLAUDE_DIR/commands"
  CLAUDE_DIR="$(agex_physical_dir "$CLAUDE_DIR")" || agex_die "Cannot access the Claude Code directory"
  MANIFEST="$CLAUDE_DIR/.agex-manifest"

  if [ -z "${CLAUDE_HOME:-}" ] && [ -n "${CLAUDE_CONFIG_DIR:-}" ]; then
    agex_note "CLAUDE_CONFIG_DIR is set to ${CLAUDE_CONFIG_DIR}. If Claude Code reads its configuration from there, run the installer again with CLAUDE_HOME set to that directory."
  fi

  agex_load_manifest
  if [ "$MANIFEST_FOUND" -eq 1 ]; then
    if [ -n "$MSRC" ] && [ "$MSRC" != "$SRC" ]; then
      agex_note "AGEX is already installed from $(agex_display "$MSRC"); switching the links to $(agex_display "$SRC")."
    else
      agex_note "AGEX is already installed here; refreshing the existing links."
    fi
  fi

  agex_link_kind agents
  agex_link_kind commands
  if [ "$N_UNCHANGED" -gt 0 ]; then
    agex_note "$N_UNCHANGED link(s) were already up to date."
  fi
  agex_prune_stale
  agex_write_manifest

  agex_step "Checking for conflicts"
  agex_check_collisions
  if [ "$N_COLLISIONS" -eq 0 ]; then
    agex_ok "No other agents in $(agex_display "$CLAUDE_DIR/agents") use an AGEX agent name."
  fi
  if command -v claude >/dev/null 2>&1; then
    agex_ok "Found the Claude Code CLI at $(command -v claude)."
  else
    agex_warn "The claude command is not on your PATH. Install Claude Code v2.1 or later to use AGEX."
  fi

  agex_print_summary
}

# ---------------------------------------------------------------------------
# Uninstall
# ---------------------------------------------------------------------------

agex_restore_backups() {
  # Restore files that --force backed up, newest backup first, wherever the
  # original location is free again. Updates N_RESTORED and N_KEPT.
  local root="$CLAUDE_DIR/.agex-backup" dirs="" d kind f dest
  [ -d "$root" ] || return 0
  for d in "$root"/*; do
    [ -d "$d" ] || continue
    dirs="$d$NL$dirs"
  done
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    for kind in agents commands; do
      [ -d "$d/$kind" ] || continue
      for f in "$d/$kind"/*; do
        agex_exists "$f" || continue
        dest="$CLAUDE_DIR/$kind/$(basename "$f")"
        if agex_exists "$dest"; then
          agex_count_up N_KEPT
          agex_warn "Kept the backup $(agex_display "$f"): $(agex_display "$dest") is in use."
        elif mkdir -p "$CLAUDE_DIR/$kind" && mv "$f" "$dest"; then
          agex_count_up N_RESTORED
          agex_ok "Restored $(agex_display "$dest") from $(agex_display "$d")"
        else
          agex_count_up N_KEPT
          agex_warn "Could not restore $(agex_display "$f") to $(agex_display "$dest")."
        fi
      done
      rmdir "$d/$kind" 2>/dev/null || true
    done
    rmdir "$d" 2>/dev/null || true
  done <<EOF
$dirs
EOF
  rmdir "$root" 2>/dev/null || true
}

agex_uninstall() {
  local sources dest target removed=0 left=0 candidates="" f kind checkout home_phys src_ok s
  agex_banner
  agex_step "Uninstalling AGEX from $(agex_display "$CLAUDE_DIR")"

  if [ ! -d "$CLAUDE_DIR" ]; then
    agex_ok "$(agex_display "$CLAUDE_DIR") does not exist; nothing to uninstall."
    return 0
  fi
  CLAUDE_DIR="$(agex_physical_dir "$CLAUDE_DIR")" || agex_die "Cannot access the Claude Code directory"
  MANIFEST="$CLAUDE_DIR/.agex-manifest"

  agex_load_manifest
  agex_resolve_source_quietly
  if [ "$MANIFEST_FOUND" -eq 1 ]; then
    agex_note "Found the install manifest $(agex_display "$MANIFEST")${MSRC:+ (installed from $(agex_display "$MSRC"))}."
  else
    agex_note "No install manifest found; looking for links into $(agex_display "$SRC")."
  fi

  sources="$SRC$NL"
  if [ -n "$MSRC" ] && ! agex_list_has "$sources" "$MSRC"; then
    sources="$sources$MSRC$NL"
  fi

  # Manifest entries first, then any other link that points into a source.
  while IFS= read -r dest; do
    [ -n "$dest" ] || continue
    if agex_path_under "$dest" "$CLAUDE_DIR/agents" || agex_path_under "$dest" "$CLAUDE_DIR/commands"; then
      agex_list_has "$candidates" "$dest" || candidates="$candidates$dest$NL"
    fi
  done <<EOF
$MANIFEST_ENTRIES
EOF
  for kind in agents commands; do
    for f in "$CLAUDE_DIR/$kind"/*; do
      [ -L "$f" ] || continue
      agex_list_has "$candidates" "$f" && continue
      target="$(readlink "$f" || true)"
      while IFS= read -r s; do
        [ -n "$s" ] || continue
        if agex_path_under "$target" "$s/.claude"; then
          candidates="$candidates$f$NL"
          break
        fi
      done <<EOF
$sources
EOF
    done
  done

  while IFS= read -r dest; do
    [ -n "$dest" ] || continue
    if [ -L "$dest" ]; then
      target="$(readlink "$dest" || true)"
      src_ok=0
      while IFS= read -r s; do
        [ -n "$s" ] || continue
        if agex_path_under "$target" "$s/.claude"; then
          src_ok=1
          break
        fi
      done <<EOF
$sources
EOF
      if [ "$src_ok" -eq 1 ]; then
        rm -f "$dest"
        removed=$((removed + 1))
        agex_ok "Removed $(agex_display "$dest")"
      else
        left=$((left + 1))
        agex_warn "Left $(agex_display "$dest") in place: it now points to $target, not into an AGEX checkout."
      fi
    elif agex_exists "$dest"; then
      left=$((left + 1))
      agex_warn "Left $(agex_display "$dest") in place: it is not a symbolic link, so AGEX did not create it."
    fi
  done <<EOF
$candidates
EOF

  agex_restore_backups

  if [ "$MANIFEST_FOUND" -eq 1 ]; then
    rm -f "$MANIFEST"
  fi

  if [ "$MANIFEST_FOUND" -eq 0 ] && [ "$removed" -eq 0 ] && [ "$left" -eq 0 ] && [ "$N_RESTORED" -eq 0 ] && [ "$N_KEPT" -eq 0 ]; then
    agex_ok "Nothing to uninstall: no AGEX links were found in $(agex_display "$CLAUDE_DIR")."
    return 0
  fi

  printf '\n%s%s==> AGEX was uninstalled%s\n' "$C_GREEN" "$C_BOLD" "$C_RESET"
  printf '    %-10s %s\n' "Removed" "$removed link(s)"
  printf '    %-10s %s\n' "Restored" "$N_RESTORED backed-up file(s)"
  if [ "$left" -gt 0 ] || [ "$N_KEPT" -gt 0 ]; then
    printf '    %-10s %s\n' "Left" "$left file(s) AGEX did not create, $N_KEPT backup(s) whose original location is in use"
  fi

  checkout="${MSRC:-$SRC}"
  if [ -n "$checkout" ] && [ -d "$checkout" ] && agex_is_checkout "$checkout"; then
    home_phys="$(agex_physical_dir "$AGEX_HOME_DIR" || true)"
    if [ "$checkout" = "$home_phys" ]; then
      printf '\nThe AGEX checkout at %s was left in place. To delete it as well, run:\n' "$(agex_display "$checkout")"
      printf '    rm -rf %s\n' "$(agex_cmd_path "$checkout")"
    else
      printf '\nThe AGEX checkout at %s was left in place.\n' "$(agex_display "$checkout")"
    fi
  fi
  printf '\nRestart Claude Code (or start a new session) to stop loading the AGEX agents and commands.\n'
}

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

main() {
  if [ -z "${BASH_VERSION:-}" ]; then
    printf 'error: this installer needs bash. Run it with: bash install.sh\n' >&2
    exit 1
  fi
  agex_init_globals
  agex_setup_colors
  agex_parse_args "$@"
  agex_read_env
  shopt -s nullglob
  if [ "$UNINSTALL" -eq 1 ]; then
    agex_uninstall
  else
    agex_install
  fi
}

main "$@"
