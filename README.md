# cc-statusline

> Lightweight Claude Code status line: 7-day token burn, today's usage, context %, and a weekly-reset countdown.


```
7d: 20.0M  ~$428  opus 67%  |  today: 3.0M  opus 899K  snt 2.0M  ctx 62%  |  reset 2d21h  time 59%
```

If a Pomodoro session is active, a `🍅 P1 14m  |  ` prefix is added.

### Fields

| Field | Meaning |
|---|---|
| `7d: 20.0M` | Total output tokens across all models over the rolling last 7 days, scanned from session JSONLs in `~/.claude/projects/`. |
| `~$428` | Estimated API-equivalent cost of that 7-day output at flat per-million rates (Opus $25, Sonnet $15, Haiku $5). Sanity check, not a bill. Input tokens are not counted. |
| `opus 67%` | Share of the 7-day output that came from Opus. Mix indicator, not a quota. |
| `today: 3.0M` | Output tokens so far today (local date). |
| `opus 899K` | Today's Opus output. |
| `snt 2.0M` | Today's Sonnet output (shown only if non-zero). |
| `ctx 62%` | Current session context window usage. Comes from Claude Code's status-line stdin payload. |
| `reset 2d21h` | Time until the next weekly reset anchor. |
| `time 59%` | Percent of the 7-day window that has elapsed since the last reset. Pairs with the `/usage` dialog's "X% used". |

## Install

```bash
git clone https://github.com/silkyrex/cc-statusline.git
cd cc-statusline
bash install.sh
```

**Requirements:** `python3 >= 3.9` (zoneinfo is stdlib since 3.9), `jq`, macOS or Linux, Claude Code installed and run at least once.

The installer backs up your existing `~/.claude/settings.json` to `settings.json.bak.<epoch>`, copies `cc-weekly-status.py` to `~/.local/bin/`, and sets the `statusLine` entry. Nothing else in `settings.json` is touched.

Restart Claude Code.

### Verify it worked

```bash
echo '{"session_id":"test","context_window":{"used_percentage":50}}' | python3 ~/.local/bin/cc-weekly-status.py
```

Should print one status line.

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

Set the `anchor` to that date/time and `ZoneInfo` to that timezone. Any single occurrence works — the script takes the delta modulo 7 days, so it auto-rolls forward each week.

## How token counting works

- Recursively reads every `.jsonl` under `~/.claude/projects/` whose mtime is within the last 8 days.
- For each assistant message, adds `usage.output_tokens` to a per-day bucket keyed by ISO date.
- Model is detected by substring match on `message.model` (`opus`, `sonnet`, `haiku`).
- Cached to `~/.claude/cc-burn-cache.json` with a 90s TTL — a full scan is ~2s, cache keeps the 60s refresh instant.
- **Input tokens are not counted.** The `$` estimate deliberately undersells true cost. Burn-rate indicator, not invoice.

## Pomodoro integration (optional)

If `~/.claude/pomo-state.json` exists with `{"start": <epoch-seconds>}`, the status line prepends a Pomodoro badge following a 25/5/25/5/25/5 block schedule. If you don't use this, the block is a silent no-op.

## Known limitations

- **`cc-burn-cache.json` has no locking.** Under heavy concurrent refresh it could theoretically be truncated; in practice Claude Code's 60s status-line cadence is too slow for collisions.

## Uninstall

```bash
bash uninstall.sh
```

Removes the script and strips the `statusLine` entry from `settings.json`. A timestamped backup is written next to `settings.json` before any edit.

## Troubleshooting

**Status line shows `cc-status err: ...`** — the script caught an exception. Run the verify-it-worked snippet to see the full trace.

**Countdown shows the wrong time** — your `anchor` isn't aligned with your plan's reset. Edit `cc-weekly-status.py`; see [Configuring the weekly reset](#configuring-the-weekly-reset).

**7d and today are 0** — no `.jsonl` files in `~/.claude/projects/` within the last 8 days. Start a session and send a message.

**Stale numbers** — the 90s cache lives at `~/.claude/cc-burn-cache.json`. Delete it to force a rescan.

## License

MIT.
