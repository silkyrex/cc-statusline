# cc-session-label

> Claude Code status line + automatic session labeling. 7-day token burn, today's usage, context %, weekly-reset countdown, and a session name derived from your first prompt (or set with `/rename`).

## What it shows

```
7d: 20.0M  ~$428  opus 67%  |  today: 3.0M  opus 899K  snt 2.0M  ctx 62%  |  reset 2d21h  time 59%  |  ~fix the scanner registry bug
```

A leading `~` means the label was auto-derived from the first non-slash prompt. Run `/rename NAME` to override — renamed sessions drop the `~` and also auto-approve permission prompts.

If a Pomodoro session is active (from a separate tool), a `🍅 P1 14m  |  ` prefix is added.

### Fields

| Field | Meaning |
|---|---|
| `7d: 20.0M` | Total output tokens across all models over the rolling last 7 days, scanned from session JSONLs in `~/.claude/projects/`. |
| `~$428` | Estimated API-equivalent cost of that 7-day output, using flat per-million rates (Opus $25, Sonnet $15, Haiku $5). Sanity check, not a bill. |
| `opus 67%` | Share of the 7-day output that came from Opus. Mix indicator, not a quota. |
| `today: 3.0M` | Output tokens so far today (local date). |
| `opus 899K` | Today's Opus output. |
| `snt 2.0M` | Today's Sonnet output (only shown if non-zero). |
| `ctx 62%` | Current session context window usage. Comes from Claude Code's status-line stdin payload. |
| `reset 2d21h` | Time until the next weekly reset anchor. |
| `time 59%` | Percent of the 7-day window that has elapsed since the last reset. Pairs with the `/usage` dialog's "X% used" so you can eyeball pacing. |
| `~fix the scanner...` | Session label. `~` prefix = auto-derived from the first non-slash user prompt (max 48 chars). No prefix = you ran `/rename`. |

## Session labeling

Every session gets a label automatically. The first time you send a non-slash prompt, a `UserPromptSubmit` hook captures it, sanitizes it (alphanumerics + `space ._-`, trimmed to 48 chars), and caches it at `~/.claude/auto-labels/<session_id>.txt`. Subsequent prompts are ignored — the label is sticky for the life of the session.

The label surfaces in three places:

- **Status line** — appended after the reset countdown. `~prefix` for auto, no prefix for `/rename`.
- **Permission prompts** — `[session: ~label]` is printed to stderr above each approval prompt.
- **Tab title** — a `Stop` hook writes the label to `/tmp/claude-session.txt`. Wire a `precmd` in your shell to read this file and set the terminal title (see "Terminal tab title" below).

### `/rename` overrides

```
/rename my-feature
```

Writes `customTitle` into the session JSONL. Status line flips from `~<auto>` to `my-feature`. Permission prompts change from display-only to **auto-approved** — this is the only way to unlock auto-approve. Auto-labels never auto-approve.

### Slash commands are skipped

If the first prompt is a slash command (`/today`, `/someday-review`, etc.), no auto-label is written — slash commands aren't meaningful labels. The next non-slash prompt generates the label.

## Install

```bash
git clone https://github.com/silkyrex/cc-session-label.git
cd cc-session-label
bash install.sh
```

The installer:
1. Copies `cc-weekly-status.py` to `~/.local/bin/cc-weekly-status.py`
2. Copies `cc-auto-label.sh` to `~/.local/bin/cc-auto-label.sh`
3. Creates `~/.claude/auto-labels/`
4. Patches `~/.claude/settings.json`: sets `statusLine` and merges three hooks (`UserPromptSubmit`, `Stop`, `PermissionRequest`). Existing hooks with the same commands are replaced in place; unrelated hooks are left alone.

Restart Claude Code. The status line should appear within ~2 seconds of the first message (first scan is uncached). The auto-label shows up on the refresh after your first non-slash prompt.

### Requirements

- `python3 >= 3.9` (`zoneinfo` is standard library since 3.9)
- `jq`
- macOS or Linux
- Claude Code installed and run at least once (so `~/.claude/projects/` exists)

## Configuring the weekly reset

The reset countdown is anchored to a hardcoded timestamp in `cc-weekly-status.py`:

```python
def reset_countdown():
    pt = ZoneInfo('America/Los_Angeles')
    anchor = datetime.datetime(2026, 4, 23, 12, 0, tzinfo=pt)
    ...
```

Your Claude Code `/usage` dialog shows something like:

> Current week (all models)
> Resets Apr 23 at 12pm (America/Los_Angeles)

Set the `anchor` to that date/time and the `ZoneInfo` to that timezone. Any one occurrence works — the script takes the delta modulo 7 days, so it auto-rolls forward each week.

If your plan uses a different cadence (not weekly), the modulo arithmetic won't match; edit the `7 * 86400` constant as needed.

## How token counting works

- The script recursively reads every `.jsonl` under `~/.claude/projects/` whose mtime is within the last 8 days.
- For each assistant message, it adds `usage.output_tokens` to a per-day bucket, keyed by the entry's ISO date.
- Model is detected by substring match on `message.model` (`opus`, `sonnet`, `haiku`).
- Results are cached to `~/.claude/cc-burn-cache.json` with a 90-second TTL, so most refreshes are instant.

A full scan of a heavily-used history is ~2s. The cache keeps the status line responsive on the 60s refresh.

**Input tokens are not counted.** The `$` estimate is output-only and deliberately undersells the true cost. It's a burn-rate indicator, not an invoice.

## Pomodoro integration (optional)

If a file at `~/.claude/pomo-state.json` exists with `{"start": <epoch-seconds>}`, the status line prepends a Pomodoro badge following a 25/5/25/5/25/5 block schedule. If you don't use this, the block is a silent no-op.

## Files

| File | Purpose |
|---|---|
| `cc-weekly-status.py` | Status line script. Reads stdin, prints one line (token burn + session label). |
| `cc-auto-label.sh` | `UserPromptSubmit` hook. Derives the session label from the first non-slash prompt and caches it at `~/.claude/auto-labels/<sid>.txt`. |
| `install.sh` | One-shot installer: copies both scripts to `~/.local/bin/` and merges `statusLine` + three hooks into `~/.claude/settings.json`. |

## Terminal tab title

The `Stop` hook writes the session label to `/tmp/claude-session.txt` after every turn. To show it in the terminal tab, add this to your shell rc:

```zsh
_cc_tab_title() {
  local name=""
  [ -f /tmp/claude-session.txt ] && name=$(cat /tmp/claude-session.txt)
  [ -n "$name" ] && printf '\033]0;claude | %s\007' "$name"
}
precmd_functions+=(_cc_tab_title)
```

**Terminal.app note:** If your Claude Code profile has "Active process name" enabled under Settings → Profiles → [profile] → Window → Title, it overrides escape sequences. Uncheck it.

## Uninstall

```bash
# Remove the scripts and auto-label cache
rm -f ~/.local/bin/cc-weekly-status.py ~/.local/bin/cc-auto-label.sh
rm -rf ~/.claude/auto-labels

# Remove statusLine and the three hooks this repo installed
python3 <<'PY'
import json, pathlib
p = pathlib.Path.home() / '.claude' / 'settings.json'
s = json.loads(p.read_text())
s.pop('statusLine', None)
hooks = s.get('hooks', {})
def drop(event, needle):
    arr = hooks.get(event)
    if not arr: return
    inner = arr[0].get('hooks', [])
    arr[0]['hooks'] = [h for h in inner if needle not in h.get('command', '')]
    if not arr[0]['hooks']: hooks.pop(event)
drop('UserPromptSubmit', 'cc-auto-label.sh')
drop('Stop', 'claude-session.txt')
drop('PermissionRequest', 'customTitle')
if not hooks: s.pop('hooks', None)
p.write_text(json.dumps(s, indent=2))
PY
```

## Troubleshooting

**Status line shows `cc-status err: ...`** — the script caught an exception and fell through to the error handler. Run it manually to see the full trace:

```bash
echo '{"session_id":"test","context_window":{"used_percentage":50}}' | python3 ~/.local/bin/cc-weekly-status.py
```

**Countdown shows the wrong time** — your local `anchor` datetime is not aligned with your plan's reset. Edit `cc-weekly-status.py`; see "Configuring the weekly reset" above.

**7d and today are 0** — no `.jsonl` files in `~/.claude/projects/` within the last 8 days. Start a Claude Code session and send at least one message.

**Stale numbers** — the 90-second TTL cache lives at `~/.claude/cc-burn-cache.json`. Delete it to force a rescan on next refresh.

## License

MIT.
