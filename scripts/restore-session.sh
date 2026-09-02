#!/usr/bin/env bash
# restore-session.sh — part of the "blackbox" skill.
# Copies backed-up transcripts from full-session-logs/ BACK into the harness's
# transcript store, so a session the harness has pruned becomes resumable again.
#
# Backing up is only half a black box. Harnesses delete old transcripts on a
# retention timer (Claude Code defaults to 30 days), after which `claude -r` and
# equivalents show nothing even though the backup is sitting right there. This
# script closes that loop.
#
# Usage:
#   bash scripts/restore-session.sh --list           # what is in the black box
#   bash scripts/restore-session.sh <id>             # restore one (id or substring)
#   bash scripts/restore-session.sh --all            # restore everything
#   bash scripts/restore-session.sh <id> --to DIR    # restore to an explicit store
#   bash scripts/restore-session.sh <id> --force     # overwrite if already present
#
# Restored files get a fresh mtime so the harness's retention timer restarts
# instead of pruning them again immediately.

set -uo pipefail

BB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=blackbox-common.sh
. "$BB_DIR/blackbox-common.sh" || { echo "blackbox: missing blackbox-common.sh" >&2; exit 1; }

bb_load_conf

target=""
dest_dir=""
explicit_dest=""
do_all=0
force=0

while [ $# -gt 0 ]; do
  case "$1" in
    --list|-l) 
      if [ -f "$BB_DEST/MANIFEST.md" ]; then
        cat "$BB_DEST/MANIFEST.md"
      else
        bb_warn "no MANIFEST.md yet; run backup-session.sh first. Raw contents:"
        ls -la "$BB_DEST" 2>/dev/null
      fi
      exit 0 ;;
    --all|-a)   do_all=1; shift ;;
    --force|-f) force=1; shift ;;
    --to)       dest_dir="${2:-}"; explicit_dest=1; shift 2 ;;
    -h|--help)  sed -n '2,25p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*)         bb_warn "unknown option: $1"; exit 2 ;;
    *)          target="$1"; shift ;;
  esac
done

if [ -z "$target" ] && [ "$do_all" -eq 0 ]; then
  bb_warn "restore: name a session id, or pass --all. Use --list to see what is backed up."
  exit 2
fi

# --- Resolve destination store -------------------------------------------
if [ -z "$dest_dir" ]; then
  dest_dir="${BLACKBOX_TRANSCRIPT_DIR/#\~/$HOME}"
fi
if [ -z "$dest_dir" ]; then
  # No config: reuse the same autodetection the backup path uses, and take the
  # directory of whatever transcript it finds.
  found="$(bb_newest_transcript || true)"
  [ -n "$found" ] && dest_dir="$(dirname "$found")"
fi
if [ -z "$dest_dir" ]; then
  bb_warn "restore: could not work out where this harness stores transcripts."
  bb_warn "         Pass --to /path/to/store, or set BLACKBOX_TRANSCRIPT_DIR in"
  bb_warn "         scripts/blackbox.conf (see SKILL.md)."
  exit 1
fi

if ! mkdir -p "$dest_dir" 2>/dev/null; then
  bb_warn "restore: cannot create destination $dest_dir"
  exit 1
fi

# --- Select sources -------------------------------------------------------
sources=()
while IFS= read -r f; do
  [ -n "$f" ] && [ -f "$f" ] || continue
  if [ "$do_all" -eq 1 ] || [[ "$(basename "$f")" == *"$target"* ]]; then
    sources+=("$f")
  fi
done < <(find "$BB_DEST" -maxdepth 1 -type f -name '*.jsonl' 2>/dev/null | sort)

if [ "${#sources[@]}" -eq 0 ]; then
  bb_warn "restore: nothing in full-session-logs/ matches '${target:---all}'."
  exit 1
fi

restored=0
skipped=0
for src in "${sources[@]}"; do
  base="$(basename "$src")"

  # Put it back where the harness filed it. Codex nests transcripts under
  # sessions/YYYY/MM/DD/; a flat restore into the store root can still be found
  # by some harnesses, but it leaves the store inconsistent with its own layout.
  # An explicit --to always wins, and an unknown file restores flat as before.
  rel=""
  [ -z "$explicit_dest" ] && rel="$(bb_lookup_path "$base")"
  if [ -n "$rel" ]; then
    target_dir="$dest_dir/$rel"
    mkdir -p "$target_dir" 2>/dev/null || target_dir="$dest_dir"
  else
    target_dir="$dest_dir"
  fi

  # A transcript already present ANYWHERE under the store counts as present,
  # so we never create a second copy at a different depth.
  existing="$(find "$dest_dir" -type f -name "$base" -print -quit 2>/dev/null)"
  if [ -n "$existing" ] && [ "$force" -eq 0 ]; then
    bb_warn "skip $base (already in store; use --force to overwrite)"
    skipped=$((skipped + 1))
    continue
  fi
  [ -n "$existing" ] && [ "$force" -eq 1 ] && target_dir="$(dirname "$existing")"

  if cp -f "$src" "$target_dir/$base" 2>/dev/null; then
    touch "$target_dir/$base" 2>/dev/null   # restart the retention clock
    bb_warn "restored $base -> $target_dir"
    restored=$((restored + 1))
  else
    bb_warn "failed to restore $base"
  fi
done

bb_warn "restore: $restored restored, $skipped skipped."
[ "$restored" -gt 0 ] && bb_warn "resume your harness's session picker to see them."
exit 0
