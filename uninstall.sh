#!/bin/bash
set -euo pipefail

# ============================================================
# Orchestratia Skills Uninstaller
# Removes hooks, skill, and config. Does NOT uninstall pip packages.
# ============================================================

INSTALL_DIR="/opt/orchestratia-skills"
CONFIG_DIR="/etc/orchestratia"
SKILL_DIR="$HOME/.claude/skills/orchestratia"
SETTINGS_FILE="$HOME/.claude/settings.json"

info() { echo -e "\033[0;32m[INFO]\033[0m $*"; }

info "Removing hook scripts..."
rm -rf "$INSTALL_DIR"

info "Removing skill..."
rm -rf "$SKILL_DIR"

info "Removing config..."
rm -rf "$CONFIG_DIR"

# Remove hooks from settings.json if present
if [[ -f "$SETTINGS_FILE" ]]; then
    if grep -q "orchestratia" "$SETTINGS_FILE" 2>/dev/null; then
        info "Cleaning Claude Code settings..."
        python3 -c "
import json
with open('$SETTINGS_FILE', 'r') as f:
    settings = json.load(f)
hooks = settings.get('hooks', {})
for key in ['SessionStart', 'PreToolUse']:
    if key in hooks:
        hooks[key] = [h for h in hooks[key] if not any('orchestratia' in (hook.get('command','') or '') for hook in h.get('hooks',[]))]
        if not hooks[key]:
            del hooks[key]
if not hooks:
    settings.pop('hooks', None)
with open('$SETTINGS_FILE', 'w') as f:
    json.dump(settings, f, indent=2)
" 2>/dev/null || echo "  Could not clean settings.json automatically."
    fi
fi

echo ""
echo "Orchestratia Skills uninstalled."
echo "pip packages (if installed) were not removed."
echo "To fully remove: pip3 uninstall orchestratia-agent"
