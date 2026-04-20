# cc-statusline

> Lightweight Claude Code status line: 7-day token burn, today's usage, context %, and a weekly-reset countdown.

![status line](screenshot.png)

```
7d: 20.0M  ~$428  opus 67%  |  today: 3.0M  opus 899K  snt 2.0M  ctx 62%  |  reset 2d21h  time 59%
```

If a Pomodoro session is active, a `🍅 P1 14m  |  ` prefix is added. If the session has a label (see [Bonus: session labeling](#bonus-session-labeling)), it's appended to the end.

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

The installer backs up your existing `~/.claude/settings.json` to `settings.json.bak.<epoch>`, then:
1. Copies `cc-weekly-status.py` and `cc-auto-label.sh` to `~/.local/bin/`.
2. Creates `~/.claude/auto-labels/`.
3. Sets `statusLine` and merges `UserPromptSubmit`, `Stop`, `PermissionRequest` hooks into `settings.json`. Existing hooks are matched by command-substring and replaced in place; anything else is untouched.

Restart Claude Code.

### Verify it worked

```bash
# 1. Status line renders
echo '{"session_id":"test","context_window":{"used_percentage":50}}' | python3 ~/.local/bin/cc-weekly-status.py

# 2. Hooks landed in settings.json
jq '.statusLine.command, (.hooks | keys)' ~/.claude/settings.json
```

The first command should print one status line. The second should list your hook events.

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

---

## Bonus: session labeling

The installer also wires up automatic session labels — handy if you run multiple Claude Code sessions and keep losing track of which is which.

A `UserPromptSubmit` hook captures the first non-slash prompt, sanitizes it, and caches it at `~/.claude/auto-labels/<session_id>.txt` (max 48 chars, sticky for the life of the session). The label is then appended to the status line with a `~` prefix, printed above permission prompts as `[session: ~label]`, and written to `/tmp/claude-session.txt` for terminal-tab wiring (see below).

### `/rename` overrides

```
/rename my-feature
```

Writes `customTitle` into the session JSONL. Status line drops the `~` prefix.

> **⚠ Security note:** `/rename` also **auto-approves permission prompts** for that session. The hook emits `allow` on every approval, skipping the UI. Auto-labeled sessions (the `~` ones) are display-only — they still prompt normally. Only explicit `/rename` unlocks auto-approve. Treat `/rename` as "I trust tool calls from this session." If you don't want that, never run it.

### Terminal tab title

The `Stop` hook writes the label to `/tmp/claude-session.txt` after every turn. To reflect it in the terminal tab, add this to your shell rc:

```zsh
_cc_tab_title() {
  local name=""
  [ -f /tmp/claude-session.txt ] && name=$(cat /tmp/claude-session.txt)
  [ -n "$name" ] && printf '\033]0;claude | %s\007' "$name"
}
precmd_functions+=(_cc_tab_title)
```

**Terminal.app note:** If your profile has "Active process name" enabled under Settings → Profiles → [profile] → Window → Title, it overrides escape sequences. Uncheck it.

---

## Known limitations

- **Concurrent Claude Code sessions share `/tmp/claude-session.txt`.** Last-writer-wins on tab title — two active sessions will cause the tab title to flap. The per-session auto-label file is unaffected.
- **Auto-label cache isn't garbage-collected.** Every session writes one small file to `~/.claude/auto-labels/` forever. Harmless but unbounded; `rm ~/.claude/auto-labels/*.txt` if it bothers you.
- **`cc-burn-cache.json` has no locking.** Under heavy concurrent refresh it could theoretically be truncated; in practice Claude Code's 60s status-line cadence is too slow for collisions.
- **`/rename` writes into Claude Code's session JSONL.** The hooks only read `customTitle`, but `/rename` itself mutates CC's state file — if the file format changes upstream, expect breakage.

## Uninstall

```bash
bash uninstall.sh
```

Removes both scripts, clears `~/.claude/auto-labels/`, and strips the `statusLine` + three hooks from `settings.json`. A timestamped backup is written next to `settings.json` before any edit.

## Troubleshooting

**Status line shows `cc-status err: ...`** — the script caught an exception. Run the verify-it-worked snippet to see the full trace.

**Countdown shows the wrong time** — your `anchor` isn't aligned with your plan's reset. Edit `cc-weekly-status.py`; see [Configuring the weekly reset](#configuring-the-weekly-reset).

**7d and today are 0** — no `.jsonl` files in `~/.claude/projects/` within the last 8 days. Start a session and send a message.

**Stale numbers** — the 90s cache lives at `~/.claude/cc-burn-cache.json`. Delete it to force a rescan.

**Auto-label didn't appear** — `ls ~/.claude/auto-labels/`. If empty, your first prompt was a slash command (skipped by design). Send a non-slash prompt.

## License

MIT.
