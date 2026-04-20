# cc-statusline

> Know how much Claude Code you've burned this week, and never lose track of which session is which.

A status line for Claude Code: 7-day output-token burn, today's usage, context %, weekly-reset countdown, and an auto-derived session label that also surfaces in permission prompts and your terminal tab title.

## What it shows

```
7d: 20.0M  ~$428  opus 67%  |  today: 3.0M  opus 899K  snt 2.0M  ctx 62%  |  reset 2d21h  time 59%  |  ~fix the scanner registry bug
```

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
| `~fix the scanner...` | Session label. `~` prefix = auto-derived from the first non-slash prompt. No prefix = you ran `/rename`. Max 48 chars. |

## Session labeling

Every session gets a label automatically. A `UserPromptSubmit` hook captures the first non-slash prompt, sanitizes it, and caches it at `~/.claude/auto-labels/<session_id>.txt`. Subsequent prompts are ignored — the label is sticky for the life of the session. Slash-command-only sessions stay unlabeled until a real prompt arrives.

The label surfaces in three places:

- **Status line** — appended after the reset countdown.
- **Permission prompts** — `[session: ~label]` printed to stderr above each approval prompt.
- **Terminal tab title** — a `Stop` hook writes the label to `/tmp/claude-session.txt`. See [Terminal tab title](#terminal-tab-title) for the shell wiring.

### Overriding with `/rename`

```
/rename my-feature
```

Writes `customTitle` into the session JSONL. Status line flips from `~<auto>` to `my-feature`.

> ### ⚠ Security note: `/rename` also auto-approves permission prompts
>
> A renamed session changes posture: the `PermissionRequest` hook emits `allow` for every prompt, skipping the approval UI. Auto-labeled sessions (the `~` ones) are **display-only** — they still prompt normally. Only sessions you explicitly `/rename` unlock auto-approve.
>
> Treat `/rename` as "I've vetted this session; trust tool calls from it." If you don't want that behavior, never run `/rename` — auto-labels give you the name without the trust bump.

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
3. Sets `statusLine` and merges `UserPromptSubmit`, `Stop`, `PermissionRequest` hooks into `settings.json`. Existing hooks are matched by command-substring (`cc-auto-label.sh`, `claude-session.txt`, `customTitle`) and replaced in place; anything else is untouched.

Restart Claude Code.

### Verify it worked

```bash
# 1. Status line renders
echo '{"session_id":"test","context_window":{"used_percentage":50}}' | python3 ~/.local/bin/cc-weekly-status.py

# 2. Hooks landed in settings.json
jq '.statusLine.command, (.hooks | keys)' ~/.claude/settings.json
```

The first command should print one status line. The second should list your three hook events (`UserPromptSubmit`, `Stop`, `PermissionRequest`).

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

If `~/.claude/pomo-state.json` exists with `{"start": <epoch-seconds>}`, the status line prepends a Pomodoro badge following a 25/5/25/5/25/5 block schedule (e.g. `🍅 P1 14m  |  ...`). If you don't use this, the block is a silent no-op.

## Terminal tab title

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

## Known limitations

- **Concurrent Claude Code sessions share `/tmp/claude-session.txt`.** Last-writer-wins on tab title — two active sessions will cause the tab title to flap to whichever most recently completed a turn. The auto-label file (`~/.claude/auto-labels/<sid>.txt`) is per-session and unaffected.
- **Auto-label cache isn't garbage-collected.** Every session writes one small file to `~/.claude/auto-labels/` forever. Harmless but unbounded; `rm ~/.claude/auto-labels/*.txt` safely if it bothers you.
- **`cc-burn-cache.json` has no locking.** Under heavy concurrent refresh it could theoretically be truncated; in practice Claude Code's 60s status-line cadence is too slow for collisions.
- **`/rename` writes `customTitle` into Claude Code's session JSONL.** The hooks only read it, but the initial write is `/rename` mutating CC's own state file — if CC's file format changes upstream, expect breakage.

## Uninstall

```bash
bash uninstall.sh
```

Removes both scripts, clears `~/.claude/auto-labels/`, and strips the `statusLine` + three hooks from `settings.json`. A timestamped backup is written next to `settings.json` before any edit.

## Troubleshooting

**Status line shows `cc-status err: ...`** — the script caught an exception and fell through. Run the verify-it-worked snippet above to see the full trace.

**Countdown shows the wrong time** — your `anchor` datetime isn't aligned with your plan's reset. Edit `cc-weekly-status.py`; see [Configuring the weekly reset](#configuring-the-weekly-reset).

**7d and today are 0** — no `.jsonl` files in `~/.claude/projects/` within the last 8 days. Start a CC session and send at least one message.

**Stale numbers** — the 90s cache lives at `~/.claude/cc-burn-cache.json`. Delete it to force a rescan.

**Auto-label didn't appear** — check `ls ~/.claude/auto-labels/`. If empty, your first prompt was likely a slash command (skipped by design). Send a non-slash prompt and wait for the next status-line refresh.

## License

MIT.
