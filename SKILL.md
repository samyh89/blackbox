---
name: blackbox
description: Bootstraps a small, agent-agnostic project baseline - Git, README, universal agent instructions, changelog, decisions log, work logs - plus a session-log black box that captures each coding session's full transcript into a Git-ignored folder and can restore it into the agent's transcript store after the agent has pruned it. Use when creating or bootstrapping an important project folder, or when adding session-log capture and recovery to an existing one.
---

# blackbox - Project Logging Helper / Memory layer & logger.

Create the smallest useful baseline for an important project.

This skill is normally used once, when creating a new project folder. Keep the setup lightweight. Do not add frameworks, CI, Docker, databases, cloud config, architecture packs, task systems, or extra documentation unless the user explicitly asks.

## Baseline Layout

Create only this baseline:

```txt
README.md
AGENTS.md
CHANGELOG.md
DECISIONS.md
llms.txt
.gitignore
.env.example
logs/
full-session-logs/
scripts/backup-session.sh
scripts/restore-session.sh
scripts/blackbox-common.sh
scripts/bb                    (only for runtimes without lifecycle hooks)
scripts/blackbox.conf         (machine-local, Git-ignored)
```

`full-session-logs/` is a private black-box backup folder. Create it locally, but keep it ignored by Git. No exceptions — it can contain secrets, private data, and full conversation history.

The `scripts/` files make the black box actually record and actually recover. Always install them; whether they fire *automatically* is the user's choice — see [Session Log Backup](#session-log-backup-black-box).

## Steps

1. Create the project folder.
2. Create the baseline files and folders.
3. **Ask the user whether they want automatic full-session-log capture.** See
   [Ask first](#step-0-ask-the-user-first). Do not decide this for them.
4. Install the session-log black box by following the procedure in
   [Session Log Backup](#session-log-backup-black-box). This is a real
   install-and-verify step, not a file copy.
5. Initialize Git if the folder is not already a Git repository.
6. Run `git status`.
7. Make the first commit with message `chore: initialize project baseline`.
8. Ask if the user wants a private GitHub remote.
9. If yes, create or connect the private remote and push the default branch.
10. Report the project path, files created, first commit hash, GitHub remote status,
    the capture mode the user chose, proof that capture fired (or a plain statement
    that it is off by choice), and next step.

## File Contents

### README.md

```md
# <Project Name>

## Purpose

## How To Run

## How To Verify

## Agent Start

Read `AGENTS.md` before making changes.
```

### AGENTS.md

````md
# Agent Instructions

Read this file before editing the project.

## Before Editing

1. Read `AGENTS.md`.
2. Check `git status`.
3. Do not overwrite user work.
4. Do not access `full-session-logs/` unless the user explicitly asks.

## During Work

- Keep changes scoped to the user's request.
- Mandatory: update `CHANGELOG.md` for every user-facing behavior change, project structure change, dependency change, bug fix, or feature addition.
- Mandatory: update `DECISIONS.md` when you make or change an important technical, product, storage, dependency, hosting, security, or workflow decision.
- Mandatory: create a short work log in `logs/` before finishing any work session.
- Never commit secrets, tokens, credentials, `.env` files, private data, or full session logs.
- Run available verification before claiming success.
- Stop and ask before destructive actions.
- After finishing a meaningful chunk of work - a feature, a fix, a refactor, a
  changelog or decisions update, or the end of a session - ask the user whether to
  commit, and name what would go in. Do not commit without asking unless the user
  has given you standing permission to commit on your own judgement. If they give
  it, stop asking but still report what you committed.

## Before Finishing

1. Update `CHANGELOG.md` if required.
2. Update `DECISIONS.md` if required.
3. Create a work log in `logs/`.
4. Summarize changed files.
5. State what verification was run.
6. State any remaining risks or follow-up work.

## Work Log Format

Filename style:

`YYYY-MM-DD-HHMM-agent-short-task.md`

Example:

`2026-06-20-1430-codex-add-export-command.md`

Use this format:

```md
# Work Log: <title>

Date:
Agent:
Branch:

## What Changed

## Why

## Verification

## Notes
```

## Agent Tags

Use a clear agent label, such as:

- `codex`
- `claude-code`
- `hermes-agent`
- `gemini`
- `chatgpt`
- `human`
````

### CHANGELOG.md

```md
# Changelog

## Unreleased

### Added

### Changed

### Fixed

### Removed
```

### DECISIONS.md

```md
# Decisions

Record only meaningful decisions. Do not log tiny edits here.

## YYYY-MM-DD - <Title>

Decision:

Reason:

Agent:
```

### llms.txt

```txt
See AGENTS.md for system instructions and the logs/ directory for project history.
```

### .gitignore

```gitignore
# Environment and secrets
.env
.env.*
!.env.example

# AI session backups and private logs
full-session-logs/
*.zip

# blackbox machine-local config (contains local paths)
scripts/blackbox.conf

# Common local noise
.DS_Store
Thumbs.db
```

### .env.example

```env
# Copy this file to .env and fill values locally.
# Do not commit real secrets.
```

### logs/

Create an empty `logs/` folder for lightweight agent-written work notes.

If the filesystem cannot store empty folders, create:

```txt
logs/.gitkeep
```

Do not create a work log during bootstrap unless the user requests one.

### full-session-logs/

Create `full-session-logs/` for automated raw session backups.

Rules:

- Keep it ignored by Git. Always. There is no opt-in for committing it.
- Do not read it during normal work.
- Do not summarize it unless the user asks.
- Do not commit its contents.
- Treat it as a debugging and memory-recovery black box.

If the filesystem cannot store empty folders, create:

```txt
full-session-logs/.gitkeep
```

The `.gitignore` must still ignore `full-session-logs/`, so `.gitkeep` should remain untracked.

## Session Log Backup (Black Box)

`full-session-logs/` is only a flight recorder if something writes to it, and only
a *recoverable* one if something can write back. The scripts that do this are
harness-agnostic. **The agent installing this skill is responsible for wiring
capture into its own runtime.**

Do not assume the paths, config format, or hook system of whichever agent
happened to author this skill. Discover your own.

### Step 0: ask the user first

Capture is the only part of this skill that acts outside the project folder: it
copies whole conversation transcripts to a second location on disk, registers a
hook in the user's agent config, and changes a global retention setting.
Transcripts routinely contain whatever was pasted into the session, including
secrets. That is the user's call, not yours.

**The first time this skill is set up for a project, ask:**

```txt
This project can keep a black box of your full session transcripts, so a
session you lose to your agent's cleanup timer can be recovered later.

  [1] On (recommended) - every session is captured automatically. Transcripts
      are copied into full-session-logs/, which stays Git-ignored and never
      leaves this machine. They can contain anything you paste, secrets included.

  [2] Manual - install the scripts but wire up nothing. Nothing is recorded
      unless you run `bash scripts/backup-session.sh --now` yourself.

Everything else is identical either way: README, AGENTS.md, CHANGELOG.md,
DECISIONS.md, llms.txt, logs/, Git setup and commits all work the same.
```

Record the answer in `scripts/blackbox.conf` as `BLACKBOX_CAPTURE="on"` or
`BLACKBOX_CAPTURE="manual"`, and record the choice in `DECISIONS.md`.

- **Ask once per project.** On any later run, read `BLACKBOX_CAPTURE` from
  `blackbox.conf`. If it is set, honour it silently and do not ask again.
- **Install the scripts either way.** They are inert files; the flag decides
  whether anything fires. This makes changing your mind a one-line edit rather
  than a reinstall.
- **If the user chose manual, skip step 3 and step 4 below** — register no hook
  and do not touch the retention setting. Then say so plainly in your report and
  write it into `AGENTS.md`, so nobody later assumes coverage that is not there.
- **Restore works in both modes.** `restore-session.sh` never depends on the flag.

### What to install

Copy these from this skill's `scripts/` directory into the project's `scripts/`
and make them executable:

| File | Purpose |
| --- | --- |
| `blackbox-common.sh` | Shared helpers. Required by the other two. |
| `backup-session.sh` | Captures the current transcript into `full-session-logs/`, refreshes `MANIFEST.md`. |
| `restore-session.sh` | Copies a backup *back* into the runtime's transcript store. |
| `bb` | Launcher wrapper. Only needed for runtimes with no lifecycle hooks. |

Do not edit these scripts to hardcode a path. Everything machine-specific belongs
in `scripts/blackbox.conf`.

### Install procedure

1. **Locate the transcript.** Find where *your* runtime writes the current
   session's transcript on this machine. Verify it: list the directory, and
   confirm there is a file whose size or mtime advances as the session continues.
   Do not assume a path and do not copy one out of this document.

2. **Record it in `scripts/blackbox.conf`** — never in the script:

   ```sh
   BLACKBOX_AGENT="<your runtime's name>"
   BLACKBOX_TRANSCRIPT_DIR="<the directory you just verified>"
   BLACKBOX_TRANSCRIPT_GLOB="*.jsonl"
   BLACKBOX_MATCH_PROJECT="auto"
   BLACKBOX_CAPTURE="on"        # or "manual" if the user opted out in step 0
   ```

   If your runtime keeps one shared directory for *all* projects, set
   `BLACKBOX_MATCH_PROJECT="always"` so another project's transcript is never
   captured into this one.

3. **Install automatic capture** using whatever your runtime actually supports.
   *Skip this step entirely if the user chose manual in step 0.*

   - **Lifecycle hooks** (stop / session-end / exit): register
     `bash <project>/scripts/backup-session.sh`. If your runtime pipes event JSON
     on stdin, the script already reads `transcript_path`, `transcriptPath`,
     `session_file`, `rollout_path`, and `log_path` — nothing further is needed.
   - **No hooks:** install `scripts/bb` and tell the user to launch the agent as
     `./scripts/bb <agent-command>`. It captures on normal exit, Ctrl-C, and kill.
   - **Neither is possible:** set `BLACKBOX_TRANSCRIPT` and run the script by hand,
     and state plainly in your report that capture is manual.

4. **Raise the runtime's transcript retention.** *Skip if the user chose manual.*
   Most runtimes delete old
   transcripts on a timer. When that fires, the resume list goes empty even though
   the backup is sitting safely in `full-session-logs/`. Find your runtime's
   retention setting and raise it as far as it allows. If it has none, say so.

5. **PROVE IT.** *If the user chose manual, state in one line that capture is off
   by their choice and how to run it by hand — then skip the rest of this step.*
   Otherwise trigger a real capture and show the output of both:

   ```sh
   ls -la full-session-logs/
   bash scripts/restore-session.sh --list
   ```

   Do not report success without that output. If you cannot make capture fire
   automatically, say so plainly, describe what you tried, and stop. Never claim
   the black box is recording when it is not.

### Recovering a lost session

This is the half that makes the black box worth having. When the runtime has
pruned a session and its resume picker no longer lists it:

```sh
bash scripts/restore-session.sh --list      # what the black box holds
bash scripts/restore-session.sh <id>        # put one back in the store
bash scripts/restore-session.sh --all       # put everything back
```

Restored files get a fresh mtime, so the retention clock restarts instead of
pruning them again on the next sweep. Existing files are never overwritten
without `--force`.

### MANIFEST.md

`backup-session.sh` regenerates `full-session-logs/MANIFEST.md` on every capture:
one row per session with its id, first and last timestamp, size, and opening
prompt. Without it the folder is an unreadable pile of UUIDs. It lives inside
`full-session-logs/` and is therefore Git-ignored like everything else there,
because opening prompts can contain private detail.

### Runtime notes

Reference points only — **verify before use**, they change between versions:

- **Claude Code** — per-project transcript directory under `~/.claude/projects/`,
  named after the project path with non-alphanumerics replaced by `-`. Has `Stop`
  and `SessionEnd` hooks in `.claude/settings.json`, and passes `transcript_path`
  on stdin. Retention: `cleanupPeriodDays` in `~/.claude/settings.json`
  (defaults to 30 days — raise it).
- **Codex** — rollout files under `~/.codex/sessions/`, in dated subdirectories
  and shared across projects, so set `BLACKBOX_MATCH_PROJECT="always"` and
  `BLACKBOX_TRANSCRIPT_GLOB="rollout-*.jsonl"`. Codex has a hook system with a
  trust model (see `--dangerously-bypass-hook-trust`); confirm the current event
  names and config schema from Codex's own documentation at install time, and fall
  back to `scripts/bb` if you cannot register a session-end hook.
- **Anything else** — discover it with step 1. Use hooks if the runtime has them,
  `scripts/bb` if it does not. The wrapper needs no knowledge of the runtime at
  all, so there is always a working route.

## Tool-Specific Pointer Files

If the user wants tool-specific pointers, create any of these files with exactly this content:

```txt
Read AGENTS.md first.
```

Possible pointer files:

```txt
CLAUDE.md
GEMINI.md
CODEX.md
HERMES.md
```

Do not create these unless the user asks or the project/tooling clearly benefits from them.

## Git Rules

Use Git for the baseline.

Minimum sequence:

```sh
git init
git add .
git commit -m "chore: initialize project baseline"
```

Before committing, verify `full-session-logs/`, `scripts/blackbox.conf`, `.env`,
`.env.*`, and `*.zip` are ignored.

### Keep offering commits

The first commit is not the last one. Git snapshots are what let the user walk
back to a working state, and a project with one commit and forty files of drift
gives them nothing to walk back to.

Unless the user has given you standing autonomy to commit on your own judgement,
**ask them whether to commit** after any of these:

- a feature, fix, or refactor is finished and verified
- a batch of files has changed enough that `git status` no longer fits on a screen
- you are about to start something risky, so there is a clean point to return to
- `CHANGELOG.md` or `DECISIONS.md` was updated
- the work session is ending

Ask short and concrete, naming what would go in:

```txt
That's the restore path working and CHANGELOG updated - 4 files.
Commit this as "feat: add session restore"?
```

Rules:

- Never commit without asking, unless the user has said you may.
- If the user says "commit whenever you think it's right" or similar, treat that
  as standing permission for the rest of the session and stop asking — but still
  say what you committed.
- If they decline, do not ask again for the same batch. Wait for the next
  milestone.
- One commit per logical change. Do not sweep unrelated work into one commit.
- Always re-check the ignore rules before staging.

Commit the `scripts/` files (executable) plus any runtime config needed to fire
the hook, so the black box ships with the project. The captured transcripts and
the machine-local `blackbox.conf` stay untracked.

## GitHub Remote

After the first local commit, ask:

```txt
Do you want me to create or connect a private GitHub repo for this project?
```

If yes:

1. Create or connect the private remote.
2. Push the default branch.
3. Report the remote URL.

Do not create public repositories unless the user explicitly asks.

## Common Mistakes

- Do not create `tasks/` by default.
- Do not create architecture docs by default.
- Do not create tool-specific pointer files unless useful.
- Do not commit `full-session-logs/` or `scripts/blackbox.conf`.
- Do not put secrets into logs, changelog, decisions, or README.
- Do not skip the first commit.
- Do not skip installing the `scripts/` black-box files — install them in both
  capture modes; the config flag, not their absence, is what turns capture off.
- Do not decide the capture mode for the user, and do not re-ask once
  `BLACKBOX_CAPTURE` is set in `blackbox.conf`.
- Do not report a capture mode you did not actually configure.
- Do not go a whole session without offering a commit.
- Do not hardcode a transcript path into a script; put it in `blackbox.conf`.
- Do not install capture without also raising the runtime's retention setting;
  backups you cannot resume are only half a black box.
- Do not forget to `chmod +x` the scripts.
- Do not claim verification ran unless it actually ran, and do not claim capture
  works without showing `ls -la full-session-logs/`.
