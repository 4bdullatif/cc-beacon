#!/bin/bash
set -euo pipefail

REPO="4bdullatif/cc-beacon"
INSTALL_DIR="$HOME/.local/bin"
BIN="$INSTALL_DIR/cc-beacon"
CONFIG="$HOME/.config/ccbeacon.conf"
SETTINGS="$HOME/.claude/settings.json"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
DIM='\033[2m'
BOLD='\033[1m'
RESET='\033[0m'

echo ""
echo -e "${BOLD}cc-beacon${RESET} — install"
echo -e "${DIM}─────────────────────────${RESET}"
echo ""

# ── Check macOS ──
if [[ "$(uname)" != "Darwin" ]]; then
    echo -e "${RED}✗${RESET} macOS only. This tool uses native macOS APIs."
    exit 1
fi

# ── Download binary ──
mkdir -p "$INSTALL_DIR"

echo -e "${DIM}▸ Downloading latest release...${RESET}"

# Get latest release download URL
LATEST_URL=$(curl -sL "https://api.github.com/repos/$REPO/releases/latest" \
    | grep '"browser_download_url"' \
    | grep 'cc-beacon-macos' \
    | head -1 \
    | cut -d'"' -f4)

if [ -z "$LATEST_URL" ]; then
    echo -e "${RED}✗${RESET} Could not find release binary."
    echo -e "  ${DIM}Build from source instead: make install && bash setup-hooks.sh${RESET}"
    exit 1
fi

curl -sL "$LATEST_URL" -o "$BIN"
chmod +x "$BIN"
echo -e "  ${GREEN}✓${RESET} Binary installed to ${DIM}$BIN${RESET}"

# ── Quarantine (macOS Gatekeeper) ──
xattr -d com.apple.quarantine "$BIN" 2>/dev/null || true

# ── Config file ──
mkdir -p "$HOME/.config"
if [ ! -f "$CONFIG" ]; then
    cat > "$CONFIG" << 'EOF'
{
  "theme": "dark",
  "duration": 4,

  "sounds": {
    "permission": "Submarine",
    "feedback": "Pop",
    "done": "Glass",
    "info": null
  }
}
EOF
    echo -e "  ${GREEN}✓${RESET} Config created at ${DIM}$CONFIG${RESET}"
else
    echo -e "  ${DIM}○${RESET} Config already exists, skipping"
fi

# ── Check jq ──
if ! command -v jq &>/dev/null; then
    echo -e "${RED}✗${RESET} jq is required. Install with: ${BOLD}brew install jq${RESET}"
    exit 1
fi

# ── Claude Code hooks ──
echo ""
echo -e "${DIM}▸ Configuring Claude Code hooks...${RESET}"

mkdir -p "$HOME/.claude"
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"

jq --arg bin "$BIN" '
  .hooks //= {} |
  .hooks |= with_entries(
    .value |= [ .[] | select(.hooks | all(.command | contains("cc-beacon") | not)) ]
  ) |
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

echo -e "  ${GREEN}✓${RESET} Hooks added to ${DIM}$SETTINGS${RESET}"
echo ""
echo -e "${DIM}Events:${RESET}"
echo -e "  ${YELLOW}Notification${RESET}  permission_prompt  → amber HUD"
echo -e "  ${YELLOW}Notification${RESET}  idle_prompt        → blue HUD"
echo -e "  ${YELLOW}Stop${RESET}          task complete       → green HUD"
echo -e "  ${YELLOW}SubagentStop${RESET}  subagent done       → green HUD"
echo ""
echo -e "${DIM}Sounds, theme, and duration are controlled by: $CONFIG${RESET}"
echo ""

# ── Test ──
echo -e "${DIM}▸ Test notification...${RESET}"
echo '{"hook_event_name":"Stop","cwd":"'"$PWD"'","message":"cc-beacon installed successfully"}' \
    | "$BIN" &

echo -e "  ${GREEN}✓${RESET} Done. Restart Claude Code to activate hooks."
echo ""
