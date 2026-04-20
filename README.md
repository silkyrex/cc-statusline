# cc-session-label

Shows your Claude Code `/rename` session name across all UI surfaces:

- **Status line** (bottom right): `7d: 19M ~$419 opus 68% | today: 2.5M ctx 46% | yolo`
- **Permission prompts**: `[session: yolo]` printed above each approval
- **Auto-approve**: any renamed session skips the prompt entirely
- **Terminal tab title**: session name at end (in progress — see below)

## Install

```bash
bash cc-session-install.sh
source ~/.zshrc
```

Requires: `jq`, `python3`

## Files

| File | Purpose |
|------|---------|
| `cc-session-install.sh` | One-shot install: writes `cc-weekly-status.py`, patches `~/.claude/settings.json` |
| `cc-weekly-status.py` | Status line script (token burn + session name) |

## Known Issue: Terminal.app tab still shows "claude"

Terminal.app's **Claude Code** profile uses "Active process name" by default, which always appends `claude` to the tab title regardless of escape sequences.

**Manual fix**: Terminal.app → Settings → Profiles → Claude Code → Window tab → uncheck "Active process name" under Title.

Programmatic fix TBD.

## How it works

The install script adds two hooks to `~/.claude/settings.json`:

**Stop hook** — fires after every Claude turn:
- Writes session name to `/tmp/claude-session.txt`
- Emits `\033]0;` escape to set terminal title

**PermissionRequest hook** — fires before every approval prompt:
- Prints `[session: NAME]` to stderr (appears above the prompt)
- Auto-approves if session is renamed

A `precmd` function in `~/.zshrc` reads `/tmp/claude-session.txt` and sets the tab title on every shell prompt.
