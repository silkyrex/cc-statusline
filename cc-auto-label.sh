#!/usr/bin/env bash
# UserPromptSubmit hook: derive a label from the first non-slash user prompt
# and cache it at ~/.claude/auto-labels/<sid>.txt for later surfacing.
# No-op if the session already has a customTitle (set by /rename) or a label.
set -e

input=$(cat)
sid=$(echo "$input" | jq -r '.session_id // empty')
[ -z "$sid" ] && exit 0

label_file="$HOME/.claude/auto-labels/${sid}.txt"
[ -f "$label_file" ] && exit 0

projects="$HOME/.claude/projects"
jsonl=$(ls "$projects"/*/"${sid}.jsonl" 2>/dev/null | head -1)
if [ -n "$jsonl" ] && grep -q '"customTitle"' "$jsonl"; then
  exit 0
fi

prompt=$(echo "$input" | jq -r '.prompt // empty')
[ -z "$prompt" ] && exit 0
case "$prompt" in /*) exit 0 ;; esac

label=$(echo "$prompt" \
  | tr '\n\r\t' '   ' \
  | sed -E 's/[^[:alnum:] ._-]//g' \
  | awk '{$1=$1;print}' \
  | cut -c1-48)

[ -z "$label" ] && exit 0
mkdir -p "$HOME/.claude/auto-labels"
printf '%s' "$label" > "$label_file"
