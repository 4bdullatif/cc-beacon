#!/bin/bash
set -euo pipefail

BIN="$HOME/.local/bin/cc-beacon"
SETTINGS="$HOME/.claude/settings.json"

if ! command -v jq &>/dev/null; then
    echo "jq is required. Install with: brew install jq"
    exit 1
fi

mkdir -p "$HOME/.claude"
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"

HOOK='{"type":"command","command":"'"$BIN"'"}'

# Remove existing cc-beacon hooks, then add fresh ones
jq --arg bin "$BIN" '
  # Strip any existing cc-beacon entries
  .hooks //= {} |
  .hooks |= with_entries(
    .value |= [ .[] | select(.hooks | all(.command | contains("cc-beacon") | not)) ]
  ) |
  # Add new hooks
  .hooks.Notification = (.hooks.Notification // []) + [
    {"matcher":"permission_prompt","hooks":[{"type":"command","command":$bin}]},
    {"matcher":"idle_prompt","hooks":[{"type":"command","command":$bin}]}
  ] |
  .hooks.Stop = (.hooks.Stop // []) + [
    {"matcher":"","hooks":[{"type":"command","command":$bin}]}
  ] |
  .hooks.SubagentStop = (.hooks.SubagentStop // []) + [
    {"matcher":"","hooks":[{"type":"command","command":$bin}]}
  ]
' "$SETTINGS" > "$SETTINGS.tmp" && mv "$SETTINGS.tmp" "$SETTINGS"

echo "✓ Hooks configured in $SETTINGS"
echo ""
echo "  Notification  permission_prompt  → amber HUD"
echo "  Notification  idle_prompt        → blue HUD"
echo "  Stop          task complete       → green HUD"
echo "  SubagentStop  subagent done       → green HUD"
