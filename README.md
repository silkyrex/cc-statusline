# cc-statusline

`/usage` shows totals. This shows burn rate, model mix, and time-to-reset.


```
7d: 20.0M  ~$428  opus 67%  |  today: 3.0M  opus 899K  snt 2.0M  ctx 62%  |  2d10h 65%  ~$656/wk  cache 132x
```

If a Pomodoro session is active, a `🍅 P1 14m  |  ` prefix is added.

### Fields

| Field | Meaning |
|---|---|
| `7d: 20.0M` | Output tokens (≈ words) over the last 7 days. |
| `~$428` | 7d output cost at API rates. Opus $25/M, Sonnet $15/M, Haiku $5/M. Output only — real API bill is higher. |
| `opus 67%` | Opus share of 7d output. Lower = cheaper. |
| `today: 3.0M` | Output tokens today. Catches runaway sessions. |
| `opus 899K` | Today's Opus output. |
| `snt 2.0M` | Today's Sonnet output (hidden if zero). |
| `ctx 62%` | Current session context usage. Compacts near 100%. |
| `2d10h 65%` | Time until weekly reset and % of cycle elapsed. |
| `~$656/wk` | Weekly spend on current pace. Hidden early in cycle. |
| `cache 132x` | Cache reads per output token. Higher = better. Near 1x = nothing cached, full price every turn. |

### Usefulness

| Field | Grade | Why |
|---|---|---|
| `ctx 62%` | A | Changes mid-session, demands action near 100%. |
| `~$656/wk` | A | Only forward-looking number. Triggers slow-down decisions. |
| `~$428` | B+ | Raw baseline. Slightly redundant with weekly projection but anchors it. |
| `cache 132x` | B+ | Silent health check. A broken cache is expensive and invisible. |
| `opus 67%` | B | Tells you to reroute tasks to Sonnet when high. |
| `2d10h 65%` | B | Useful for pacing spend against a weekly budget. |
| `today: 3.0M` | C | Runaway-session signal, but `ctx %` does that better in real time. |
| `7d: 20.0M` | C | Gives context for the cost number; raw token count alone is meaningless. |
| `opus 899K` / `snt 2.0M` | D | Today's model breakdown. The 7d `opus %` is more useful; noise unless debugging. |

**Alert thresholds:** `ctx > 80%` = compact soon. `cache < 10x` = prefix cache broken. `opus% > 70%` = overpaying, route more to Sonnet.

### Planned improvements

| Field | Target | Change |
|---|---|---|
| `opus 899K` / `snt 2.0M` | D → B | Replace raw today-model counts with today's cost + mix: `today: ~$45 (opus 30%)`. A dollar and a ratio are readable; raw token counts are not. |
| `7d: 20.0M` | C → B+ | Merge with `~$428`. Dollar first, tokens in parens: `7d: ~$428 (20M)`. Two fields doing the same job as one. |
| `today: 3.0M` | C → B | Add delta vs. 7-day daily average: `today: 3.0M (+40%)`. Without the comparison it's just a number. |

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
