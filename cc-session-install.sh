#!/usr/bin/env bash
# cc-session-install.sh
# Installs: session name in status line + auto-approve for renamed sessions
# Usage: bash cc-session-install.sh

set -e

# ── deps ────────────────────────────────────────────────────────────────────
if ! command -v jq &>/dev/null; then
  echo "jq not found. Install with: brew install jq"
  exit 1
fi

if ! command -v python3 &>/dev/null; then
  echo "python3 not found."
  exit 1
fi

# ── paths ───────────────────────────────────────────────────────────────────
SETTINGS="$HOME/.claude/settings.json"
STATUS_SCRIPT="$HOME/.local/bin/cc-weekly-status.py"
PROJECTS_KEY=$(ls "$HOME/.claude/projects/" 2>/dev/null | head -1)

if [ -z "$PROJECTS_KEY" ]; then
  # No sessions yet — derive from home path
  PROJECTS_KEY=$(echo "$HOME" | sed 's|/|-|g' | sed 's|^-||')
fi

echo "Detected projects key: $PROJECTS_KEY"

# ── status line script ───────────────────────────────────────────────────────
mkdir -p "$HOME/.local/bin"

cat > "$STATUS_SCRIPT" << 'PYEOF'
#!/usr/bin/env python3
"""Status line: 7d burn + today + ctx% + session name."""
import json, datetime, time, sys, re
from pathlib import Path

CACHE = Path.home() / '.claude' / 'cc-burn-cache.json'
TTL = 90

def fmt(n):
    if n >= 1_000_000: return f'{n/1_000_000:.1f}M'
    if n >= 1_000: return f'{n/1_000:.0f}K'
    return str(n)

def rate(model):
    if 'opus' in model: return 25
    if 'sonnet' in model: return 15
    if 'haiku' in model: return 5
    return 0

def scan():
    base = Path.home() / '.claude' / 'projects'
    cutoff = time.time() - 8 * 86400
    by_day = {}
    for p in base.rglob('*.jsonl'):
        try:
            if p.stat().st_mtime < cutoff: continue
            with open(p) as f:
                for line in f:
                    try: e = json.loads(line)
                    except: continue
                    msg = e.get('message') or {}
                    u = msg.get('usage') or {}
                    out = u.get('output_tokens', 0)
                    if not out: continue
                    day = e.get('timestamp', '')[:10]
                    if not day: continue
                    model = msg.get('model', '')
                    bucket = by_day.setdefault(day, {'out': 0, 'opus': 0, 'sonnet': 0, 'cost': 0.0})
                    bucket['out'] += out
                    if 'opus' in model: bucket['opus'] += out
                    if 'sonnet' in model: bucket['sonnet'] += out
                    bucket['cost'] += out * rate(model) / 1_000_000
        except: pass
    return by_day

def load_cache():
    try:
        d = json.loads(CACHE.read_text())
        if time.time() - d['ts'] < TTL: return d['by_day']
    except: pass
    return None

def save_cache(by_day):
    try: CACHE.write_text(json.dumps({'ts': time.time(), 'by_day': by_day}))
    except: pass

def pomo_status():
    state_file = Path.home() / '.claude' / 'pomo-state.json'
    try:
        s = json.loads(state_file.read_text())
        elapsed = int(time.time()) - s['start']
        blocks = [
            (0,      25*60, 'P1'),
            (25*60,  30*60, 'brk'),
            (30*60,  55*60, 'P2'),
            (55*60,  60*60, 'brk'),
            (60*60,  85*60, 'P3'),
            (85*60,  90*60, 'done'),
        ]
        for start, end, label in blocks:
            if start <= elapsed < end:
                mins = (end - elapsed + 59) // 60
                return f'🍅 break {mins}m' if label == 'brk' else f'🍅 {label} {mins}m'
    except: pass
    return None

try:
    ctx_pct = None
    session_name = ''
    try:
        stdin_data = json.loads(sys.stdin.read())
        ctx_pct = stdin_data.get('context_window', {}).get('used_percentage')
        session_id = stdin_data.get('session_id', '')
        if session_id:
            # find session JSONL in any projects subdir
            projects = Path.home() / '.claude' / 'projects'
            for candidate in projects.glob(f'*/{session_id}.jsonl'):
                try:
                    m = re.findall(r'"customTitle":"([^"]+)"', candidate.read_text())
                    if m: session_name = m[-1]
                except: pass
                break
    except: pass

    by_day = load_cache()
    if by_day is None:
        by_day = scan()
        save_cache(by_day)

    today = datetime.date.today().isoformat()
    dates = sorted(by_day.keys())[-7:]
    w_out = sum(by_day[d]['out'] for d in dates)
    w_opus = sum(by_day[d]['opus'] for d in dates)
    w_cost = sum(by_day[d]['cost'] for d in dates)

    t = by_day.get(today, {'out': 0, 'opus': 0, 'sonnet': 0})
    t_out, t_opus, t_sonnet = t['out'], t['opus'], t.get('sonnet', 0)

    w_pct = (w_opus / w_out * 100) if w_out else 0
    ctx_str = f'  ctx {ctx_pct:.0f}%' if ctx_pct is not None else ''
    snt_str = f'  snt {fmt(t_sonnet)}' if t_sonnet else ''
    name_str = f' | {session_name}' if session_name else ''
    token_line = f'7d: {fmt(w_out)}  ~${w_cost:.0f}  opus {w_pct:.0f}%  |  today: {fmt(t_out)}  opus {fmt(t_opus)}{snt_str}{ctx_str}{name_str}'
    pomo = pomo_status()
    print(f'{pomo}  |  {token_line}' if pomo else token_line)
except Exception as e:
    print(f'cc-status err: {e}')
PYEOF

chmod +x "$STATUS_SCRIPT"
echo "✓ Status script written to $STATUS_SCRIPT"

# ── settings.json ────────────────────────────────────────────────────────────
mkdir -p "$HOME/.claude"

# Create minimal settings.json if it doesn't exist
if [ ! -f "$SETTINGS" ]; then
  echo '{}' > "$SETTINGS"
fi

# Use Python to merge settings safely
python3 - "$SETTINGS" "$STATUS_SCRIPT" "$PROJECTS_KEY" << 'EOF'
import json, sys
from pathlib import Path

settings_path, script_path, projects_key = sys.argv[1], sys.argv[2], sys.argv[3]

with open(settings_path) as f:
    s = json.load(f)

# statusLine
s['statusLine'] = {
    'type': 'command',
    'command': script_path,
    'refreshInterval': 60
}

# skipDangerousModePermissionPrompt
s['skipDangerousModePermissionPrompt'] = True

# PermissionRequest hooks — merge, don't replace
hook_cmd = (
    f'input=$(cat); sid=$(echo "$input" | jq -r \'.session_id // empty\'); '
    f'f="$HOME/.claude/projects/{projects_key}/${{sid}}.jsonl"; '
    f'if [ -f "$f" ]; then '
    f'name=$(grep -o \'"customTitle":"[^"]*"\' "$f" | tail -1 | cut -d\'"\' -f4); '
    f'if [ -n "$name" ]; then '
    f'echo "[session: $name]" >&2; '
    f'echo \'{{\"hookSpecificOutput\":{{\"hookEventName\":\"PermissionRequest\",\"permissionDecision\":\"allow\"}}}}\'; '
    f'fi; fi'
)

new_hook = {'type': 'command', 'command': hook_cmd}

hooks = s.setdefault('hooks', {})
pr = hooks.setdefault('PermissionRequest', [{'hooks': []}])
existing_hooks = pr[0].setdefault('hooks', [])

# Only add if not already present (idempotent)
if not any('customTitle' in h.get('command', '') for h in existing_hooks):
    existing_hooks.append(new_hook)

with open(settings_path, 'w') as f:
    json.dump(s, f, indent=2)

print(f'✓ settings.json updated at {settings_path}')
EOF

# ── verify ───────────────────────────────────────────────────────────────────
echo ""
echo "Install complete. Verify:"
echo "  1. Start Claude Code, run /rename myproject"
echo "  2. Status line should show '... | myproject' within 60s"
echo "  3. Any permission prompt in a renamed session is auto-approved"
