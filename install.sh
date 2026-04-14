#!/bin/bash
set -euo pipefail

# ============================================================
# Orchestratia Skills Installer (Multi-Agent)
#
# Installs hooks, skills, and CLI for Claude Code, Gemini CLI,
# and/or Codex CLI integration with Orchestratia.
#
# Usage:
#   curl -sL .../install.sh | bash -s -- <registration_token>
#   curl -sL .../install.sh | bash -s -- <token> --agent claude,gemini,codex
#   curl -sL .../install.sh | bash -s -- --hub https://orchestratia.com --token <token>
#
# Agent flag:
#   --agent all           Auto-detect installed agents (default)
#   --agent claude        Only configure Claude Code
#   --agent gemini        Only configure Gemini CLI
#   --agent codex         Only configure Codex CLI
#   --agent claude,gemini Comma-separated list
# ============================================================

INSTALL_DIR="/opt/orchestratia-skills"
CONFIG_DIR="/etc/orchestratia"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

info()  { echo -e "${GREEN}[✓]${NC} $*"; }
warn()  { echo -e "${YELLOW}[!]${NC} $*"; }
error() { echo -e "${RED}[✗]${NC} $*" >&2; }
step()  { echo -e "${CYAN}[→]${NC} $*"; }

# ── Parse arguments ──
TOKEN=""
HUB_URL=""
AGENT_FLAG="all"

while [[ $# -gt 0 ]]; do
    case $1 in
        --hub)    HUB_URL="$2"; shift 2 ;;
        --token)  TOKEN="$2"; shift 2 ;;
        --agent)  AGENT_FLAG="$2"; shift 2 ;;
        -*)       error "Unknown option: $1"; exit 1 ;;
        *)        TOKEN="$1"; shift ;;
    esac
done

if [[ -z "$TOKEN" ]]; then
    error "Registration token is required."
    echo "Usage: $0 <registration_token>"
    echo "       $0 <token> --agent claude,gemini,codex"
    echo "       $0 --token <token> --hub <hub_url>"
    exit 1
fi

# ── Extract hub URL from token (orcreg_ format) ──
if [[ -z "$HUB_URL" ]]; then
    if [[ "$TOKEN" == orcreg_* ]]; then
        URL_PART=$(echo "$TOKEN" | sed 's/^orcreg_//' | cut -d. -f1)
        PADDING=$((4 - ${#URL_PART} % 4))
        [[ $PADDING -ne 4 ]] && URL_PART="${URL_PART}$(printf '=%.0s' $(seq 1 $PADDING))"
        URL_PART=$(echo "$URL_PART" | tr '_-' '/+')
        HUB_URL=$(echo "$URL_PART" | base64 -d 2>/dev/null || true)
    fi
fi

if [[ -z "$HUB_URL" ]]; then
    error "Could not extract hub URL from token. Use --hub <url>"
    exit 1
fi

echo ""
echo -e "${BOLD}Orchestratia Skills Installer${NC}"
echo -e "Hub: ${CYAN}$HUB_URL${NC}"
echo ""

# ── Agent detection ──
detect_claude() { command -v claude >/dev/null 2>&1; }
detect_gemini() { command -v gemini >/dev/null 2>&1; }
detect_codex()  { command -v codex >/dev/null 2>&1; }

CONFIGURE_CLAUDE=false
CONFIGURE_GEMINI=false
CONFIGURE_CODEX=false

if [[ "$AGENT_FLAG" == "all" ]]; then
    detect_claude && CONFIGURE_CLAUDE=true
    detect_gemini && CONFIGURE_GEMINI=true
    detect_codex  && CONFIGURE_CODEX=true
else
    IFS=',' read -ra AGENTS <<< "$AGENT_FLAG"
    for a in "${AGENTS[@]}"; do
        case "$(echo "$a" | tr '[:upper:]' '[:lower:]' | xargs)" in
            claude) CONFIGURE_CLAUDE=true ;;
            gemini) CONFIGURE_GEMINI=true ;;
            codex)  CONFIGURE_CODEX=true ;;
            *) warn "Unknown agent: $a (valid: claude, gemini, codex)" ;;
        esac
    done
fi

# ── 1. Install CLI ──
step "[1/5] Installing orchestratia CLI..."
if command -v pip3 &>/dev/null; then
    pip3 install --quiet orchestratia-agent 2>/dev/null || \
    pip3 install --quiet --break-system-packages orchestratia-agent 2>/dev/null || true
fi
if command -v orchestratia >/dev/null 2>&1; then
    info "CLI installed"
else
    warn "CLI installation failed. Install manually: pip3 install orchestratia-agent"
fi

# ── 2. Download hook scripts ──
step "[2/5] Installing hook scripts..."
mkdir -p "$INSTALL_DIR/hooks"

REPO_BASE="https://raw.githubusercontent.com/kumarimlab/orchestratia-skills/main"
curl -fsSL "$REPO_BASE/hooks/orchestratia-context.sh" -o "$INSTALL_DIR/hooks/orchestratia-context.sh"
curl -fsSL "$REPO_BASE/hooks/orchestratia-pretooluse.sh" -o "$INSTALL_DIR/hooks/orchestratia-pretooluse.sh"
chmod +x "$INSTALL_DIR/hooks/"*.sh
info "Hooks installed to $INSTALL_DIR/hooks/"

# ── 3. Install agent-specific skills ──
step "[3/5] Installing skills..."

install_claude_skill() {
    local SKILL_DIR="$HOME/.claude/skills/orchestratia"
    mkdir -p "$SKILL_DIR"
    curl -fsSL "$REPO_BASE/skill/claude/SKILL.md" -o "$SKILL_DIR/SKILL.md"
    info "Claude Code skill → $SKILL_DIR/SKILL.md"
}

install_gemini_skill() {
    # Gemini supports both ~/.gemini/skills/ and ~/.agents/skills/
    local SKILL_DIR="$HOME/.gemini/skills/orchestratia"
    local SHARED_DIR="$HOME/.agents/skills/orchestratia"
    mkdir -p "$SKILL_DIR" "$SHARED_DIR"
    curl -fsSL "$REPO_BASE/skill/gemini/SKILL.md" -o "$SKILL_DIR/SKILL.md"
    # Also install to shared path (used by both Gemini and Codex)
    cp "$SKILL_DIR/SKILL.md" "$SHARED_DIR/SKILL.md"
    info "Gemini CLI skill  → $SKILL_DIR/SKILL.md"
}

install_codex_skill() {
    # Codex supports ~/.agents/skills/ and ~/.codex/skills/
    local SKILL_DIR="$HOME/.agents/skills/orchestratia"
    local CODEX_DIR="$HOME/.codex/skills/orchestratia"
    mkdir -p "$SKILL_DIR" "$CODEX_DIR"
    curl -fsSL "$REPO_BASE/skill/codex/SKILL.md" -o "$CODEX_DIR/SKILL.md"
    # Also install to shared path
    if [[ ! -f "$SKILL_DIR/SKILL.md" ]]; then
        cp "$CODEX_DIR/SKILL.md" "$SKILL_DIR/SKILL.md"
    fi
    info "Codex CLI skill   → $CODEX_DIR/SKILL.md"
}

$CONFIGURE_CLAUDE && install_claude_skill
$CONFIGURE_GEMINI && install_gemini_skill
$CONFIGURE_CODEX  && install_codex_skill

# ── 4. Configure agent hooks ──
step "[4/5] Configuring agent hooks..."

configure_claude_hooks() {
    local SETTINGS_FILE="$HOME/.claude/settings.json"
    mkdir -p "$(dirname "$SETTINGS_FILE")"

    if [[ -f "$SETTINGS_FILE" ]] && grep -q "orchestratia-context" "$SETTINGS_FILE" 2>/dev/null; then
        info "Claude Code hooks already configured"
        return
    fi

    if [[ -f "$SETTINGS_FILE" ]]; then
        python3 -c "
import json
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
" 2>/dev/null || { warn "Could not update Claude settings. Add hooks manually."; return; }
    else
        cat > "$SETTINGS_FILE" <<JSONEOF
{
  "hooks": {
    "SessionStart": [
      {"hooks": [{"type": "command", "command": "$INSTALL_DIR/hooks/orchestratia-context.sh", "timeout": 10000}]}
    ],
    "PreToolUse": [
      {"hooks": [{"type": "command", "command": "$INSTALL_DIR/hooks/orchestratia-pretooluse.sh", "timeout": 30000}]}
    ]
  }
}
JSONEOF
    fi
    info "Claude Code hooks configured in $SETTINGS_FILE"
}

configure_gemini_hooks() {
    local SETTINGS_FILE="$HOME/.gemini/settings.json"
    mkdir -p "$(dirname "$SETTINGS_FILE")"

    if [[ -f "$SETTINGS_FILE" ]] && grep -q "orchestratia-context" "$SETTINGS_FILE" 2>/dev/null; then
        info "Gemini CLI hooks already configured"
        return
    fi

    if [[ -f "$SETTINGS_FILE" ]]; then
        python3 -c "
import json
with open('$SETTINGS_FILE', 'r') as f:
    settings = json.load(f)
hooks = settings.setdefault('hooks', {})
hooks.setdefault('SessionStart', []).append({
    'hooks': [{'name': 'orchestratia-context', 'type': 'command', 'command': '$INSTALL_DIR/hooks/orchestratia-context.sh', 'timeout': 10000}]
})
hooks.setdefault('BeforeTool', []).append({
    'hooks': [{'name': 'orchestratia-pretooluse', 'type': 'command', 'command': '$INSTALL_DIR/hooks/orchestratia-pretooluse.sh', 'timeout': 30000}]
})
with open('$SETTINGS_FILE', 'w') as f:
    json.dump(settings, f, indent=2)
" 2>/dev/null || { warn "Could not update Gemini settings. Add hooks manually."; return; }
    else
        cat > "$SETTINGS_FILE" <<JSONEOF
{
  "hooks": {
    "SessionStart": [
      {"hooks": [{"name": "orchestratia-context", "type": "command", "command": "$INSTALL_DIR/hooks/orchestratia-context.sh", "timeout": 10000}]}
    ],
    "BeforeTool": [
      {"hooks": [{"name": "orchestratia-pretooluse", "type": "command", "command": "$INSTALL_DIR/hooks/orchestratia-pretooluse.sh", "timeout": 30000}]}
    ]
  }
}
JSONEOF
    fi
    info "Gemini CLI hooks configured in $SETTINGS_FILE"
}

configure_codex_hooks() {
    local CONFIG_FILE="$HOME/.codex/config.toml"
    local HOOKS_FILE="$HOME/.codex/hooks.json"
    mkdir -p "$HOME/.codex"

    # Enable hooks feature flag in config.toml
    if [[ -f "$CONFIG_FILE" ]]; then
        if ! grep -q "codex_hooks" "$CONFIG_FILE" 2>/dev/null; then
            echo -e "\n[features]\ncodex_hooks = true" >> "$CONFIG_FILE"
        fi
    else
        cat > "$CONFIG_FILE" <<TOMLEOF
[features]
codex_hooks = true
TOMLEOF
    fi

    # Create hooks.json
    if [[ -f "$HOOKS_FILE" ]] && grep -q "orchestratia-context" "$HOOKS_FILE" 2>/dev/null; then
        info "Codex CLI hooks already configured"
        return
    fi

    if [[ -f "$HOOKS_FILE" ]]; then
        python3 -c "
import json
with open('$HOOKS_FILE', 'r') as f:
    hooks = json.load(f)
h = hooks.setdefault('hooks', {})
h.setdefault('SessionStart', []).append({
    'hooks': [{'type': 'command', 'command': '$INSTALL_DIR/hooks/orchestratia-context.sh', 'timeout': 10000}]
})
h.setdefault('PreToolUse', []).append({
    'matcher': '.*',
    'hooks': [{'type': 'command', 'command': '$INSTALL_DIR/hooks/orchestratia-pretooluse.sh', 'timeout': 30000}]
})
with open('$HOOKS_FILE', 'w') as f:
    json.dump(hooks, f, indent=2)
" 2>/dev/null || { warn "Could not update Codex hooks.json. Add hooks manually."; return; }
    else
        cat > "$HOOKS_FILE" <<JSONEOF
{
  "hooks": {
    "SessionStart": [
      {"hooks": [{"type": "command", "command": "$INSTALL_DIR/hooks/orchestratia-context.sh", "timeout": 10000}]}
    ],
    "PreToolUse": [
      {"matcher": ".*", "hooks": [{"type": "command", "command": "$INSTALL_DIR/hooks/orchestratia-pretooluse.sh", "timeout": 30000}]}
    ]
  }
}
JSONEOF
    fi
    info "Codex CLI hooks configured (hooks.json + feature flag enabled)"
}

$CONFIGURE_CLAUDE && configure_claude_hooks
$CONFIGURE_GEMINI && configure_gemini_hooks
$CONFIGURE_CODEX  && configure_codex_hooks

# ── 5. Register with hub ──
step "[5/5] Registering with hub..."
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
    cat > "$CONFIG_DIR/config.yaml" <<CFGEOF
hub_url: "$HUB_URL"
api_key: "$API_KEY"
CFGEOF
    chmod 600 "$CONFIG_DIR/config.yaml"
    info "Registered with hub successfully"
else
    warn "Registration failed. Response: $REGISTER_RESP"
    cat > "$CONFIG_DIR/config.yaml" <<CFGEOF
hub_url: "$HUB_URL"
api_key: ""
# Registration failed — run: orchestratia --register $TOKEN
CFGEOF
fi

# ── Post-install summary ──
echo ""
echo -e "${BOLD}═══════════════════════════════════════════════════${NC}"
echo -e "${BOLD}  Orchestratia Skills — Installation Complete${NC}"
echo -e "${BOLD}═══════════════════════════════════════════════════${NC}"
echo ""
echo -e "  Hooks:  $INSTALL_DIR/hooks/"
echo -e "  Config: $CONFIG_DIR/config.yaml"
echo ""

# Agent detection report
echo -e "  ${BOLD}Agent Detection:${NC}"

if $CONFIGURE_CLAUDE; then
    if detect_claude; then
        echo -e "    ${GREEN}✓${NC} Claude Code  — configured (skill + hooks)"
    else
        echo -e "    ${YELLOW}!${NC} Claude Code  — configured but binary not found on PATH"
    fi
else
    if detect_claude; then
        echo -e "    ${YELLOW}○${NC} Claude Code  — found but not configured. Run: ${CYAN}orchestratia setup --agent claude${NC}"
    else
        echo -e "    ${RED}✗${NC} Claude Code  — not found. Install it, then run: ${CYAN}orchestratia setup --agent claude${NC}"
    fi
fi

if $CONFIGURE_GEMINI; then
    if detect_gemini; then
        echo -e "    ${GREEN}✓${NC} Gemini CLI   — configured (skill + hooks)"
    else
        echo -e "    ${YELLOW}!${NC} Gemini CLI   — configured but binary not found on PATH"
    fi
else
    if detect_gemini; then
        echo -e "    ${YELLOW}○${NC} Gemini CLI   — found but not configured. Run: ${CYAN}orchestratia setup --agent gemini${NC}"
    else
        echo -e "    ${RED}✗${NC} Gemini CLI   — not found. Install it, then run: ${CYAN}orchestratia setup --agent gemini${NC}"
    fi
fi

if $CONFIGURE_CODEX; then
    if detect_codex; then
        echo -e "    ${GREEN}✓${NC} Codex CLI    — configured (skill + hooks + feature flag)"
    else
        echo -e "    ${YELLOW}!${NC} Codex CLI    — configured but binary not found on PATH"
    fi
else
    if detect_codex; then
        echo -e "    ${YELLOW}○${NC} Codex CLI    — found but not configured. Run: ${CYAN}orchestratia setup --agent codex${NC}"
    else
        echo -e "    ${RED}✗${NC} Codex CLI    — not found. Install it, then run: ${CYAN}orchestratia setup --agent codex${NC}"
    fi
fi

echo ""

if $CONFIGURE_CLAUDE || $CONFIGURE_GEMINI || $CONFIGURE_CODEX; then
    echo -e "  Open a new AI agent session to activate the hooks."
else
    echo -e "  ${YELLOW}No AI agents were detected or configured.${NC}"
    echo -e "  Install Claude Code, Gemini CLI, or Codex CLI, then run:"
    echo -e "    ${CYAN}orchestratia setup --agent all${NC}"
fi

echo -e "  Run '${CYAN}orchestratia status${NC}' to verify the connection."
echo ""
echo -e "${BOLD}═══════════════════════════════════════════════════${NC}"
