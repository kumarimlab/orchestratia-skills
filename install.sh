#!/bin/bash
set -euo pipefail

# ============================================================
# Orchestratia Skills Installer
#
# Installs Claude Code hooks and CLI for Orchestratia integration.
# No daemon, no background process — just hooks + CLI.
#
# Usage:
#   curl -sL https://raw.githubusercontent.com/kumarimlab/orchestratia-skills/main/install.sh | bash -s -- <registration_token>
#
# Or with explicit hub URL:
#   curl -sL .../install.sh | bash -s -- --hub https://orchestratia.com --token <token>
# ============================================================

INSTALL_DIR="/opt/orchestratia-skills"
CONFIG_DIR="/etc/orchestratia"
SKILL_DIR="$HOME/.claude/skills/orchestratia"
SETTINGS_FILE="$HOME/.claude/settings.json"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# ── Parse arguments ──
TOKEN=""
HUB_URL=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --hub)    HUB_URL="$2"; shift 2 ;;
        --token)  TOKEN="$2"; shift 2 ;;
        -*)       error "Unknown option: $1"; exit 1 ;;
        *)        TOKEN="$1"; shift ;;
    esac
done

if [[ -z "$TOKEN" ]]; then
    error "Registration token is required."
    echo "Usage: $0 <registration_token>"
    echo "       $0 --token <token> --hub <hub_url>"
    exit 1
fi

# ── Extract hub URL from token (orcreg_ format) ──
if [[ -z "$HUB_URL" ]]; then
    if [[ "$TOKEN" == orcreg_* ]]; then
        # Token format: orcreg_<base64url(hub_url)>.<secret>
        URL_PART=$(echo "$TOKEN" | sed 's/^orcreg_//' | cut -d. -f1)
        # Add base64 padding
        PADDING=$((4 - ${#URL_PART} % 4))
        [[ $PADDING -ne 4 ]] && URL_PART="${URL_PART}$(printf '=%.0s' $(seq 1 $PADDING))"
        # Replace URL-safe base64 chars
        URL_PART=$(echo "$URL_PART" | tr '_-' '/+')
        HUB_URL=$(echo "$URL_PART" | base64 -d 2>/dev/null || true)
    fi
fi

if [[ -z "$HUB_URL" ]]; then
    error "Could not extract hub URL from token. Use --hub <url>"
    exit 1
fi

info "Hub URL: $HUB_URL"

# ── 1. Install orchestratia-agent pip package (for CLI only) ──
info "[1/5] Installing orchestratia CLI..."
if command -v pip3 &>/dev/null; then
    pip3 install --quiet orchestratia-agent 2>/dev/null || pip3 install --quiet --break-system-packages orchestratia-agent 2>/dev/null || true
fi

# ── 2. Download hook scripts ──
info "[2/5] Installing hook scripts..."
mkdir -p "$INSTALL_DIR/hooks"

REPO_BASE="https://raw.githubusercontent.com/kumarimlab/orchestratia-skills/main"
curl -fsSL "$REPO_BASE/hooks/orchestratia-context.sh" -o "$INSTALL_DIR/hooks/orchestratia-context.sh"
curl -fsSL "$REPO_BASE/hooks/orchestratia-pretooluse.sh" -o "$INSTALL_DIR/hooks/orchestratia-pretooluse.sh"
chmod +x "$INSTALL_DIR/hooks/"*.sh

# ── 3. Install SKILL.md ──
info "[3/5] Installing Claude Code skill..."
mkdir -p "$SKILL_DIR"
curl -fsSL "$REPO_BASE/skill/SKILL.md" -o "$SKILL_DIR/SKILL.md"

# ── 4. Configure Claude Code hooks ──
info "[4/5] Configuring Claude Code hooks..."
mkdir -p "$(dirname "$SETTINGS_FILE")"

# Create or update settings.json with hooks
if [[ -f "$SETTINGS_FILE" ]]; then
    # Check if hooks already configured
    if grep -q "orchestratia-context" "$SETTINGS_FILE" 2>/dev/null; then
        info "  Hooks already configured in $SETTINGS_FILE"
    else
        # Use python to merge hooks into existing settings
        python3 -c "
import json, sys
with open('$SETTINGS_FILE', 'r') as f:
    settings = json.load(f)
hooks = settings.setdefault('hooks', {})
hooks.setdefault('SessionStart', []).append({
    'hooks': [{'type': 'command', 'command': '$INSTALL_DIR/hooks/orchestratia-context.sh', 'timeout': 10000}]
})
hooks.setdefault('PreToolUse', []).append({
    'hooks': [{'type': 'command', 'command': '$INSTALL_DIR/hooks/orchestratia-pretooluse.sh', 'timeout': 30000}]
})
with open('$SETTINGS_FILE', 'w') as f:
    json.dump(settings, f, indent=2)
" 2>/dev/null || warn "Could not update $SETTINGS_FILE automatically. Add hooks manually."
    fi
else
    cat > "$SETTINGS_FILE" <<SETTINGSEOF
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "$INSTALL_DIR/hooks/orchestratia-context.sh",
            "timeout": 10000
          }
        ]
      }
    ],
    "PreToolUse": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "$INSTALL_DIR/hooks/orchestratia-pretooluse.sh",
            "timeout": 30000
          }
        ]
      }
    ]
  }
}
SETTINGSEOF
fi

# ── 5. Register with hub ──
info "[5/5] Registering with hub..."
mkdir -p "$CONFIG_DIR"

HOSTNAME=$(hostname)
OS=$(uname -s)
MACHINE_ID=$(cat /etc/machine-id 2>/dev/null || echo "")

REGISTER_RESP=$(curl -sS -X POST "$HUB_URL/api/v1/servers/register" \
    -H "Content-Type: application/json" \
    -d "{
        \"name\": \"$HOSTNAME\",
        \"hostname\": \"$HOSTNAME\",
        \"ip\": \"0.0.0.0\",
        \"os\": \"$OS\",
        \"registration_token\": \"$TOKEN\",
        \"connection_mode\": \"skill\",
        \"machine_id\": \"$MACHINE_ID\",
        \"system_info\": {}
    }" 2>&1) || true

API_KEY=$(echo "$REGISTER_RESP" | python3 -c "import sys,json; print(json.load(sys.stdin).get('api_key',''))" 2>/dev/null || echo "")

if [[ -n "$API_KEY" ]]; then
    # Write config
    cat > "$CONFIG_DIR/config.yaml" <<CFGEOF
hub_url: "$HUB_URL"
api_key: "$API_KEY"
CFGEOF
    chmod 600 "$CONFIG_DIR/config.yaml"
    info "Registered successfully!"
else
    warn "Registration failed. Response: $REGISTER_RESP"
    warn "You can register manually later."
    cat > "$CONFIG_DIR/config.yaml" <<CFGEOF
hub_url: "$HUB_URL"
api_key: ""
# Registration failed — run: orchestratia --register $TOKEN
CFGEOF
fi

echo ""
echo "============================================="
echo "  Orchestratia Skills installed!"
echo ""
echo "  Hooks: $INSTALL_DIR/hooks/"
echo "  Skill: $SKILL_DIR/SKILL.md"
echo "  Config: $CONFIG_DIR/config.yaml"
echo ""
echo "  Start Claude Code to activate the hooks."
echo "  Run 'orchestratia status' to verify."
echo "============================================="
