#!/usr/bin/env bash
# install.sh
# Installs the cc-weekly-status.py status line for Claude Code.
# Usage: bash install.sh

set -e

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
REPO_DIR="$(cd "$(dirname "$0")" && pwd)"

mkdir -p "$HOME/.local/bin" "$HOME/.claude"
cp "$REPO_DIR/cc-weekly-status.py" "$STATUS_SCRIPT"
chmod +x "$STATUS_SCRIPT"
echo "✓ Status script installed at $STATUS_SCRIPT"

[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"

python3 - "$SETTINGS" "$STATUS_SCRIPT" << 'EOF'
import json, sys
settings_path, script_path = sys.argv[1], sys.argv[2]
with open(settings_path) as f:
    s = json.load(f)
s['statusLine'] = {'type': 'command', 'command': script_path, 'refreshInterval': 60}
with open(settings_path, 'w') as f:
    json.dump(s, f, indent=2)
print(f'✓ settings.json statusLine updated at {settings_path}')
EOF

echo ""
echo "Install complete. Restart Claude Code to see the status line."
echo "Edit $STATUS_SCRIPT to change the weekly reset anchor (see README)."
