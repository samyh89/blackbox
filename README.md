# blackbox

A small skill that gives a project two things:

1. **A written memory layer** — `AGENTS.md`, `CHANGELOG.md`, `DECISIONS.md`,
   `logs/`, `llms.txt` — so the next agent session starts knowing what happened
   in the last one.
2. **A black box** — every session's *full raw transcript* is copied into a
   Git-ignored folder, and can be **put back** into your agent's transcript store
   after the agent has deleted it.

Point 2 is the part that doesn't exist elsewhere. Every coding agent prunes old
sessions on a timer (Claude Code: 30 days by default). When that fires, the
conversation is gone and `--resume` no longer lists it. blackbox keeps a copy and
can restore it, so the session shows up in the resume picker again.

It works with **any** agent or harness. Nothing here is specific to one vendor —
see [How it stays harness-agnostic](#how-it-stays-harness-agnostic).

---

## Install

Put this folder where your agent looks for skills, then tell the agent to use it.

| Harness | Location |
| --- | --- |
| Claude Code | `~/.claude/skills/blackbox/` |
| Codex | `~/.codex/skills/blackbox/` (or the shared `~/.agents/skills/blackbox/`) |
| Anything else | your harness's skill/instruction directory |

Then, in the project you want set up:

```
Use the blackbox skill to set up this project.
```

The agent does the rest — including working out how *its own* runtime stores
transcripts. You do not configure paths by hand.

---

## The one question it will ask you

The first time blackbox is set up for a project, the agent asks whether you want
automatic session-log capture:

**`[1] On` (recommended)** — every session is captured automatically into
`full-session-logs/`. A hook (or launcher wrapper) is registered, and your
agent's transcript retention setting is raised so backups stay resumable.

**`[2] Manual`** — the scripts are installed but nothing is wired up. Nothing is
recorded unless you run it yourself:

```sh
bash scripts/backup-session.sh --now
```

**Everything else is identical in both modes.** README, AGENTS.md, CHANGELOG.md,
DECISIONS.md, llms.txt, `logs/`, Git setup, commits — all the same. Only the
automatic transcript capture is affected.

### Why you're asked at all

Capture is the only part of this skill that reaches outside the project folder.
It duplicates whole conversations onto disk and edits your agent's config.
Transcripts contain whatever you pasted into the session — including API keys.
They stay on your machine and stay Git-ignored, but that is still your decision
to make, not the agent's.

### Changing your mind

The answer lives in `scripts/blackbox.conf` (machine-local, Git-ignored):

```sh
BLACKBOX_CAPTURE="on"        # or "manual"
```

Flip it and capture stops or starts. Going from `manual` to `on` also needs the
hook registered — ask your agent to do it.

**Restoring works in both modes.** Whatever is already in `full-session-logs/`
can always be put back.

---

## Codex

Verified end to end against codex-cli 0.141.0 — capture, prune, restore, resume.

Codex has no user-registerable session hook yet (its hook events are real, but in
0.141.0 they ship through marketplace plugins behind a trust model; a project
`.codex/hooks.json` was tested and does not fire). So Codex uses the wrapper:

```sh
./scripts/bb codex </dev/null
```

**Redirect stdin.** `codex` reads stdin whenever it is not a TTY and will wait
forever on an open pipe. This is a Codex behaviour, not a blackbox one, but it
will look like a hang if you skip it.

Config for Codex:

```sh
BLACKBOX_AGENT="codex"
BLACKBOX_TRANSCRIPT_DIR="$HOME/.codex/sessions"
BLACKBOX_TRANSCRIPT_GLOB="rollout-*.jsonl"
BLACKBOX_MATCH_PROJECT="always"    # one store shared by every project
BLACKBOX_CAPTURE="on"
```

Point `BLACKBOX_TRANSCRIPT_DIR` at the `sessions` root, not a dated
subdirectory. Codex files rollouts under `sessions/YYYY/MM/DD/`, and blackbox
records where each one came from so restore rebuilds that layout instead of
dumping into the root.

One Codex-specific detail worth knowing: it keeps a SQLite index of rollouts
next to the files. Delete a rollout and `codex doctor` starts reporting *"state
DB rows point at missing or unusable rollout files"*. Restoring the file clears
that and the session resumes normally — both verified.

## Recovering a lost session

The whole point. When your agent has pruned a session and won't list it anymore:

```sh
bash scripts/restore-session.sh --list    # what the black box holds
bash scripts/restore-session.sh <id>      # put one back
bash scripts/restore-session.sh --all     # put everything back
```

Then run your agent's resume command — the session is in the picker again.

Restored files get a fresh timestamp, so the retention clock restarts instead of
deleting them on the next sweep. Existing files are never overwritten without
`--force`.

`full-session-logs/MANIFEST.md` lists every backup with its id, timestamps, size
and opening prompt, so the folder isn't an unreadable pile of UUIDs.

### Retention: do this even if you never use blackbox

Backups you can't resume are only half a black box. Raise your agent's retention
window. For Claude Code, in `~/.claude/settings.json`:

```json
{ "cleanupPeriodDays": 365 }
```

Unset defaults to 30 days. Other harnesses have their own setting, or none.

---

## Git and snapshots

**blackbox does not commit continuously.** It makes exactly **one** commit at
setup:

```
chore: initialize project baseline
```

After that, commits happen when you or your agent decide to. The skill instructs
agents to *offer* a commit after finishing a chunk of work — a feature, a fix, a
changelog update, the end of a session — and to name what would go in. It will
not commit without asking unless you tell it it may:

> "commit whenever you think it's right"

That's standing permission for the session; it will stop asking but still report
what it committed.

### Moving between snapshots

Plain Git, nothing custom:

```sh
git log --oneline          # list your snapshots
git checkout <hash>        # visit one (detached HEAD - look, don't edit)
git switch -               # come back
git revert <hash>          # undo one commit, keeping history
```

**One thing that surprises people:** `full-session-logs/` is *ignored*, not
tracked. Checking out an old commit does **not** roll back your session logs —
they survive every checkout, branch switch and revert. That's deliberate. A
black box that gets rewound with the code would be useless exactly when you need
it, but it does mean the folder is not part of your snapshots and is not backed
up by pushing to GitHub. If your disk dies, they're gone.

---

## GitHub (optional)

**You do not need a GitHub account.** Git commits are entirely local — no login,
no network. A remote is optional and can be added at any time, years later.

If you want one, authenticate first — this is interactive, so you run it, not
your agent:

```sh
gh auth login                                     # GitHub CLI, easiest
# or set up an SSH key and: git remote add origin git@github.com:you/repo.git
```

Then your agent can do the rest:

```sh
gh repo create --private --source=. --push
```

blackbox creates **private** repos unless you explicitly ask for public.

### What never gets pushed

`.gitignore` excludes these, so they cannot reach GitHub:

- `full-session-logs/` — your transcripts
- `scripts/blackbox.conf` — machine-local paths
- `.env`, `.env.*` — secrets

Verify any time with:

```sh
git check-ignore -v full-session-logs/ scripts/blackbox.conf
```

---

## What gets created

```txt
README.md              your project's readme
AGENTS.md              instructions every agent reads first
CHANGELOG.md           what changed
DECISIONS.md           why it changed
llms.txt               machine-readable project pointer
logs/                  short human-readable work logs, one per session
full-session-logs/     raw transcripts (Git-ignored)
.gitignore
.env.example
scripts/               the black box itself
```

| Script | Does |
| --- | --- |
| `backup-session.sh` | Captures the current transcript. `--now` forces it in manual mode. |
| `restore-session.sh` | Puts a backup back into the agent's store. `--list`, `--all`, `--force`, `--to DIR`. |
| `blackbox-common.sh` | Shared helpers. Required by both. |
| `bb` | Launcher wrapper, for runtimes with no hooks: `./scripts/bb <agent>`. |
| `blackbox.conf` | Your machine's paths and capture mode. Git-ignored. |

`logs/` and `full-session-logs/` are different things. `logs/` holds short
summaries an agent writes for the next agent, and is committed.
`full-session-logs/` holds raw conversation dumps, and never is.

---

## How it stays harness-agnostic

The skill contains **no** hardcoded transcript path. At install time the agent
discovers where *its own* runtime stores transcripts, verifies it by listing the
directory, and writes it to `scripts/blackbox.conf`. Then it wires capture using
whatever its runtime actually supports:

- **has session lifecycle hooks** → registers `backup-session.sh` there
- **has none** → installs `scripts/bb`, and you launch via `./scripts/bb <agent>`

So a harness that doesn't exist yet works without changing this skill. The agent
knows its own runtime better than any list ever will.

The skill also requires the agent to **prove** capture is working — showing real
`ls -la full-session-logs/` output — and to say so plainly if it can't, rather
than reporting a black box that isn't recording.

---

## Troubleshooting

**`backup: no transcript found`** — the store isn't configured or doesn't match.
Set `BLACKBOX_TRANSCRIPT_DIR` in `scripts/blackbox.conf`, or override once:

```sh
BLACKBOX_TRANSCRIPT=/path/to/transcript.jsonl bash scripts/backup-session.sh --now
```

**Nothing is being captured** — check `BLACKBOX_CAPTURE` in `blackbox.conf`. If
it's `manual`, that's the opt-out working as intended.

**Another project's sessions showed up** — your harness shares one transcript
directory across projects. Set `BLACKBOX_MATCH_PROJECT="always"`.

**Restore says the file exists** — it won't overwrite. Use `--force`.

**Codex seems to hang under `./scripts/bb`** — add `</dev/null`. Codex reads
stdin when it is not a TTY.

**MANIFEST prompts show `-`** — install `jq` for accurate parsing. The fallback
degrades to `-` rather than guessing wrong.
