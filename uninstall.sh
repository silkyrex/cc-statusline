#!/usr/bin/env bash
# uninstall.sh
# Removes scripts, auto-label cache, and the statusLine + three hooks this repo installed.
# Leaves unrelated entries in ~/.claude/settings.json untouched.
# Usage: bash uninstall.sh

set -e

SETTINGS="$HOME/.claude/settings.json"

rm -f "$HOME/.local/bin/cc-weekly-status.py" "$HOME/.local/bin/cc-auto-label.sh"
rm -rf "$HOME/.claude/auto-labels"

[ ! -f "$SETTINGS" ] && { echo "No settings.json — nothing to unpatch."; exit 0; }

cp "$SETTINGS" "$SETTINGS.bak.$(date +%s)"

python3 - "$SETTINGS" << 'EOF'
import json, sys
p = sys.argv[1]
s = json.loads(open(p).read())
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
open(p, 'w').write(json.dumps(s, indent=2))
print(f'✓ Removed statusLine + three hooks from {p}')
EOF

echo "Backup written next to $SETTINGS"
