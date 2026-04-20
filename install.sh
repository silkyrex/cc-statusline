#!/usr/bin/env bash
# install.sh
# Installs cc-weekly-status.py (status line) and cc-auto-label.sh (auto-label hook),
# then merges statusLine + three hook entries into ~/.claude/settings.json.
# Usage: bash install.sh

set -e

if ! command -v jq &>/dev/null; then
  echo "jq not found. Install with: brew install jq"
  exit 1
fi

if ! command -v python3 &>/dev/null; then
  echo "python3 not found."
  exit 1
fi

PY_VER=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
PY_MAJOR=${PY_VER%%.*}
PY_MINOR=${PY_VER##*.}
if [ "$PY_MAJOR" -lt 3 ] || { [ "$PY_MAJOR" -eq 3 ] && [ "$PY_MINOR" -lt 9 ]; }; then
  echo "python3 >= 3.9 required (found $PY_VER). zoneinfo is stdlib since 3.9."
  exit 1
fi

SETTINGS="$HOME/.claude/settings.json"
STATUS_SCRIPT="$HOME/.local/bin/cc-weekly-status.py"
AUTO_LABEL_SCRIPT="$HOME/.local/bin/cc-auto-label.sh"
REPO_DIR="$(cd "$(dirname "$0")" && pwd)"

mkdir -p "$HOME/.local/bin" "$HOME/.claude" "$HOME/.claude/auto-labels"
cp "$REPO_DIR/cc-weekly-status.py" "$STATUS_SCRIPT"
cp "$REPO_DIR/cc-auto-label.sh"   "$AUTO_LABEL_SCRIPT"
chmod +x "$STATUS_SCRIPT" "$AUTO_LABEL_SCRIPT"
echo "✓ Status script installed at $STATUS_SCRIPT"
echo "✓ Auto-label script installed at $AUTO_LABEL_SCRIPT"

[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"

python3 - "$SETTINGS" "$STATUS_SCRIPT" "$AUTO_LABEL_SCRIPT" << 'EOF'
import json, sys

settings_path, status_script, auto_label_script = sys.argv[1], sys.argv[2], sys.argv[3]
with open(settings_path) as f:
    s = json.load(f)

s['statusLine'] = {'type': 'command', 'command': status_script, 'refreshInterval': 60}

STOP_CMD = (
    'input=$(cat); sid=$(echo "$input" | jq -r \'.session_id // empty\'); '
    'f=$(ls "$HOME/.claude/projects/"*/"${sid}.jsonl" 2>/dev/null | head -1); '
    'auto="$HOME/.claude/auto-labels/${sid}.txt"; name=""; '
    'if [ -n "$f" ] && [ -f "$f" ]; then '
    'name=$(grep -o \'"customTitle":"[^"]*"\' "$f" | tail -1 | cut -d\'"\' -f4); fi; '
    'if [ -z "$name" ] && [ -f "$auto" ]; then name=$(cat "$auto"); fi; '
    'if [ -n "$name" ]; then printf \'%s\' "$name" > /tmp/claude-session.txt; fi'
)

PR_CMD = (
    'input=$(cat); sid=$(echo "$input" | jq -r \'.session_id // empty\'); '
    'f=$(ls "$HOME/.claude/projects/"*/"${sid}.jsonl" 2>/dev/null | head -1); '
    'auto="$HOME/.claude/auto-labels/${sid}.txt"; name=""; renamed=0; '
    'if [ -n "$f" ] && [ -f "$f" ]; then '
    'name=$(grep -o \'"customTitle":"[^"]*"\' "$f" | tail -1 | cut -d\'"\' -f4); fi; '
    'if [ -n "$name" ]; then renamed=1; '
    'elif [ -f "$auto" ]; then name="~$(cat "$auto")"; fi; '
    'if [ -n "$name" ]; then echo "[session: $name]" >&2; fi; '
    'if [ "$renamed" = 1 ]; then '
    'echo \'{"hookSpecificOutput":{"hookEventName":"PermissionRequest","permissionDecision":"allow"}}\'; fi'
)

hooks = s.setdefault('hooks', {})

def upsert(event, match_substr, command):
    arr = hooks.setdefault(event, [{'hooks': []}])
    if not arr: arr.append({'hooks': []})
    inner = arr[0].setdefault('hooks', [])
    for h in inner:
        if match_substr in h.get('command', ''):
            h['command'] = command
            return
    inner.append({'type': 'command', 'command': command})

upsert('UserPromptSubmit', 'cc-auto-label.sh', auto_label_script)
upsert('Stop',             'claude-session.txt', STOP_CMD)
upsert('PermissionRequest', 'customTitle',       PR_CMD)

with open(settings_path, 'w') as f:
    json.dump(s, f, indent=2)

print(f'✓ settings.json updated at {settings_path}')
EOF

echo ""
echo "Install complete. Restart Claude Code."
echo "- Send a non-slash prompt → auto-label appears in status line within 60s (prefixed with ~)."
echo "- Run /rename NAME to override. Renamed sessions also auto-approve permission prompts."
