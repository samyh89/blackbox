#!/usr/bin/env bash
# blackbox-common.sh — shared helpers for the blackbox session-log scripts.
# Sourced by backup-session.sh and restore-session.sh. Not meant to be run alone.
#
# Deliberately harness-agnostic: nothing here knows or cares which coding agent
# is running. Harness-specific facts live in scripts/blackbox.conf, which the
# installing agent writes at bootstrap (see SKILL.md).
#
# No `set -e`: these scripts run as session hooks and must never kill a session.

set -uo pipefail

# --- Project root ---------------------------------------------------------
# Harnesses each export their own project-dir variable, so try the ones we know
# and fall back to the Git root, then the working directory. BLACKBOX_PROJECT_DIR
# is the universal override any harness or user can set.
bb_project_dir() {
  local d="${BLACKBOX_PROJECT_DIR:-${CLAUDE_PROJECT_DIR:-${CODEX_PROJECT_DIR:-${AGENT_PROJECT_DIR:-}}}}"
  [ -n "$d" ] && [ -d "$d" ] && { printf '%s' "$d"; return 0; }
  d="$(git rev-parse --show-toplevel 2>/dev/null)"
  [ -n "$d" ] && { printf '%s' "$d"; return 0; }
  printf '%s' "$PWD"
}

BB_PROJECT_DIR="$(bb_project_dir)"
BB_DEST="$BB_PROJECT_DIR/full-session-logs"
BB_CONF="$BB_PROJECT_DIR/scripts/blackbox.conf"

# --- Local config ---------------------------------------------------------
# blackbox.conf records where THIS machine's harness keeps transcripts. It is
# written at install time by the installing agent, is machine-specific, and is
# Git-ignored. Absent config is fine; autodetect below covers common harnesses.
BLACKBOX_AGENT="${BLACKBOX_AGENT:-unknown}"
BLACKBOX_TRANSCRIPT_DIR="${BLACKBOX_TRANSCRIPT_DIR:-}"
BLACKBOX_TRANSCRIPT_GLOB="${BLACKBOX_TRANSCRIPT_GLOB:-*.jsonl}"
BLACKBOX_MATCH_PROJECT="${BLACKBOX_MATCH_PROJECT:-auto}"
# on     = automatic capture is wired up (hook or wrapper) and allowed to fire.
# manual = the user opted out of automatic capture. Scripts stay installed and
#          usable, but nothing records unless a human asks for it explicitly
#          (`backup-session.sh --now`). Restore is unaffected either way.
BLACKBOX_CAPTURE="${BLACKBOX_CAPTURE:-on}"

bb_load_conf() {
  [ -f "$BB_CONF" ] || return 0
  # shellcheck disable=SC1090
  . "$BB_CONF" 2>/dev/null || bb_warn "could not read $BB_CONF; continuing with autodetect"
}

bb_warn() { printf 'blackbox: %s\n' "$*" >&2; }

# --- Transcript store discovery ------------------------------------------
# Returns candidate directories that may hold this project's transcripts.
# Configured directory wins; otherwise probe the stores we know about. Any
# harness not listed here is handled by blackbox.conf, not by editing this file.
bb_candidate_stores() {
  if [ -n "$BLACKBOX_TRANSCRIPT_DIR" ]; then
    printf '%s\n' "${BLACKBOX_TRANSCRIPT_DIR/#\~/$HOME}"
    return 0
  fi
  local slug
  slug="$(printf '%s' "$BB_PROJECT_DIR" | sed 's/[^a-zA-Z0-9]/-/g')"
  [ -d "$HOME/.claude/projects/$slug" ] && printf '%s\n' "$HOME/.claude/projects/$slug"
  [ -d "$HOME/.codex/sessions" ]        && printf '%s\n' "$HOME/.codex/sessions"
  [ -d "$HOME/.gemini/tmp" ]            && printf '%s\n' "$HOME/.gemini/tmp"
  return 0
}

# Does this transcript belong to the current project? Per-project stores are
# already scoped, so only filter when the store is shared across projects.
bb_belongs_to_project() {
  local file="$1" store="$2"
  case "$BLACKBOX_MATCH_PROJECT" in
    never)  return 0 ;;
    always) grep -qsF -- "$BB_PROJECT_DIR" "$file" && return 0 || return 1 ;;
  esac
  case "$store" in
    "$HOME/.claude/projects/"*) return 0 ;;  # already one dir per project
    *) grep -qsF -- "$BB_PROJECT_DIR" "$file" && return 0 || return 1 ;;
  esac
}

# Newest transcript for this project across all candidate stores.
bb_newest_transcript() {
  local store f
  while IFS= read -r store; do
    [ -n "$store" ] && [ -d "$store" ] || continue
    while IFS= read -r f; do
      [ -n "$f" ] && [ -f "$f" ] || continue
      bb_belongs_to_project "$f" "$store" && { printf '%s' "$f"; return 0; }
    done < <(find "$store" -type f -name "$BLACKBOX_TRANSCRIPT_GLOB" -printf '%T@ %p\n' 2>/dev/null \
             | sort -rn | cut -d' ' -f2-)
  done < <(bb_candidate_stores)
  return 1
}

# --- Manifest -------------------------------------------------------------
# full-session-logs/ is otherwise a pile of opaque UUIDs. MANIFEST.md makes the
# black box readable: which file, when, how big, and what the session opened with.
# It lives inside full-session-logs/ and is therefore Git-ignored like the rest,
# because first prompts can contain private detail.

bb_first_timestamp() { grep -om1 '"timestamp":"[^"]*"' "$1" 2>/dev/null | sed 's/.*:"//; s/"$//'; }
bb_last_timestamp()  { grep -o  '"timestamp":"[^"]*"' "$1" 2>/dev/null | tail -n1 | sed 's/.*:"//; s/"$//'; }

# Best-effort first user prompt. Transcript schemas differ per harness, so try a
# few shapes and degrade to "-" rather than guessing wrong.
bb_first_prompt() {
  local f="$1" line=""
  if command -v jq >/dev/null 2>&1; then
    line="$(jq -rs 'map(select(
                (.type? == "user") or (.role? == "user") or (.message?.role? == "user")
              ))
            | map(.message?.content? // .content? // .text? // empty)
            | map(if type == "array" then (map(.text? // empty) | join(" ")) else tostring end)
            | map(select(. != "" and (startswith("<") | not)))
            | first // empty' "$f" 2>/dev/null)"
  fi
  if [ -z "$line" ]; then
    # No jq: scan only lines that look like user turns, and skip machine-generated
    # payloads (system reminders, command wrappers, token counters) so the column
    # shows what the human actually typed.
    line="$(grep -E '"(role|type)"[[:space:]]*:[[:space:]]*"user"' "$f" 2>/dev/null \
      | head -n 40 \
      | grep -oE '"text"[[:space:]]*:[[:space:]]*"[^"]{12,}"' 2>/dev/null \
      | sed 's/.*:[[:space:]]*"//; s/"$//' \
      | grep -vE '^(<|\\u003c|\{|\[)' \
      | head -n1)"
  fi
  [ -z "$line" ] && { printf '%s' '-'; return 0; }
  printf '%s' "$line" \
    | tr '\n\r\t|' '    ' \
    | sed 's/\\n/ /g; s/  */ /g; s/^ //; s/ $//' \
    | cut -c1-100
}

bb_write_manifest() {
  local dest="${1:-$BB_DEST}"
  [ -d "$dest" ] || return 0
  local tmp="$dest/.MANIFEST.md.tmp" f n=0
  {
    echo "# Session Backup Manifest"
    echo
    echo "Index of the transcripts in \`full-session-logs/\`, newest first."
    echo "Regenerated automatically on every backup. Do not edit by hand."
    echo
    echo "Restore one with: \`bash scripts/restore-session.sh <id>\`"
    echo
    echo "| Session | First seen | Last seen | Size | Opening prompt |"
    echo "| --- | --- | --- | --- | --- |"
  } > "$tmp" 2>/dev/null || return 0

  while IFS= read -r f; do
    [ -n "$f" ] && [ -f "$f" ] || continue
    printf '| `%s` | %s | %s | %s | %s |\n' \
      "$(basename "$f")" \
      "$(bb_first_timestamp "$f" | cut -c1-19)" \
      "$(bb_last_timestamp  "$f" | cut -c1-19)" \
      "$(du -h "$f" 2>/dev/null | cut -f1)" \
      "$(bb_first_prompt "$f")" >> "$tmp"
    n=$((n + 1))
  done < <(find "$dest" -maxdepth 1 -type f -name '*.jsonl' -printf '%T@ %p\n' 2>/dev/null \
           | sort -rn | cut -d' ' -f2-)

  { echo; echo "$n session(s) backed up."; } >> "$tmp"
  mv -f "$tmp" "$dest/MANIFEST.md" 2>/dev/null || rm -f "$tmp" 2>/dev/null
  return 0
}
