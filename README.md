# cc-statusline

> Lightweight Claude Code status line: 7-day token burn, today's usage, context %, and a weekly-reset countdown.

## What it shows

```
7d: 20.0M  ~$428  opus 67%  |  today: 3.0M  opus 899K  snt 2.0M  ctx 62%  |  reset 2d21h  time 59%
```

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

## Install

```bash
git clone https://github.com/silkyrex/cc-statusline.git
cd cc-statusline
bash install.sh
```

The installer:
1. Copies `cc-weekly-status.py` to `~/.local/bin/cc-weekly-status.py`
2. Patches `~/.claude/settings.json` to set `statusLine` to run that script every 60s

Restart Claude Code. The status line should appear within ~2 seconds of the first message (first scan is uncached).

### Requirements

- `python3 >= 3.9` (`zoneinfo` is standard library since 3.9)
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
| `cc-weekly-status.py` | The status line script. Reads stdin, prints one line. |
| `install.sh` | One-shot installer: copies the script to `~/.local/bin/` and patches `~/.claude/settings.json`. |

## Uninstall

```bash
# Remove the script
rm ~/.local/bin/cc-weekly-status.py

# Remove the statusLine entry from ~/.claude/settings.json
python3 -c "
import json, pathlib
p = pathlib.Path.home()/'.claude/settings.json'
s = json.loads(p.read_text())
s.pop('statusLine', None)
p.write_text(json.dumps(s, indent=2))
"
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
