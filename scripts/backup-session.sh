#!/usr/bin/env bash
# backup-session.sh — part of the "blackbox" skill.
# Copies the FULL agent session transcript into the project's full-session-logs/
# (a Git-ignored black-box backup), then refreshes MANIFEST.md.
#
# Harness-agnostic. It finds the transcript by trying, in order:
#   1. $BLACKBOX_TRANSCRIPT            — explicit override, works everywhere
#   2. JSON on stdin                   — for harnesses that pipe event JSON to hooks
#   3. scripts/blackbox.conf           — the store this machine's harness uses
#   4. autodetect of common stores     — best effort, filtered to this project
#
# Run it however your harness allows: a stop/exit hook, a shell trap, a wrapper,
# or by hand (`bash scripts/backup-session.sh --now`). See SKILL.md.
#
# If the user opted out of automatic capture (BLACKBOX_CAPTURE="manual" in
# blackbox.conf), automatic invocations do nothing. `--now` always captures.
#
# Never fails a session: always exits 0.

set -uo pipefail

BB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=blackbox-common.sh
. "$BB_DIR/blackbox-common.sh" || { echo "blackbox: missing blackbox-common.sh" >&2; exit 0; }

force_now=""
case "${1:-}" in
  --now|-n) force_now=1 ;;
  -h|--help)
    printf 'usage: backup-session.sh [--now]\n'
    printf '  --now   capture even when automatic capture is opted out\n'
    exit 0 ;;
esac

bb_load_conf

# Opt-out honoured here as well as at install time, so flipping the conf flag is
# enough to stop capture even if a hook is still registered somewhere.
if [ -z "$force_now" ] && [ "$BLACKBOX_CAPTURE" != "on" ]; then
  exit 0
fi

mkdir -p "$BB_DEST" 2>/dev/null

transcript=""

# --- 1. Explicit override -------------------------------------------------
if [ -n "${BLACKBOX_TRANSCRIPT:-}" ]; then
  transcript="$BLACKBOX_TRANSCRIPT"
fi

# --- 2. Event JSON on stdin ----------------------------------------------
# Harnesses name this field differently, so accept the common spellings. Every
# parse is `|| true`: malformed or absent JSON must fall through to the next
# strategy, never abort the script.
if [ -z "$transcript" ] && [ ! -t 0 ]; then
  # Bounded read. stdin may be an open pipe that nobody ever writes to or closes
  # (common when a hook inherits the parent's stdin), and a bare `cat` would hang
  # the session forever. `read -d ''` slurps everything; -t caps the wait.
  payload=""
  IFS= read -r -d '' -t "${BLACKBOX_STDIN_TIMEOUT:-2}" payload 2>/dev/null || true
  if [ -n "$payload" ]; then
    if command -v jq >/dev/null 2>&1; then
      transcript="$(printf '%s' "$payload" \
        | jq -r '.transcript_path // .transcriptPath // .session_file // .rollout_path // .log_path // empty' \
          2>/dev/null || true)"
    fi
    if [ -z "$transcript" ]; then
      transcript="$(printf '%s' "$payload" \
        | grep -oE '"(transcript_path|transcriptPath|session_file|rollout_path|log_path)"[[:space:]]*:[[:space:]]*"[^"]*"' \
          2>/dev/null | head -n1 | sed 's/.*:[[:space:]]*"//; s/"$//' || true)"
    fi
  fi
fi

# --- 3 & 4. Configured store, then autodetect ----------------------------
if [ -z "$transcript" ]; then
  transcript="$(bb_newest_transcript || true)"
fi

transcript="${transcript/#\~/$HOME}"

if [ -z "$transcript" ] || [ ! -f "$transcript" ]; then
  bb_warn "backup: no transcript found; nothing copied."
  bb_warn "        set BLACKBOX_TRANSCRIPT=/path/to/transcript, or record the store"
  bb_warn "        in scripts/blackbox.conf (see SKILL.md)."
  exit 0
fi

if ! cp -f "$transcript" "$BB_DEST/$(basename "$transcript")" 2>/dev/null; then
  bb_warn "backup: could not copy $(basename "$transcript")"
  exit 0
fi

bb_write_manifest "$BB_DEST"
bb_warn "backup: saved $(basename "$transcript") -> full-session-logs/"
exit 0
