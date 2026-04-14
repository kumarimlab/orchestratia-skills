# Orchestratia Skills

Lightweight AI agent integration for [Orchestratia](https://orchestratia.com) — the AI coding agent orchestration platform.

Supports **Claude Code**, **Gemini CLI**, and **Codex CLI** using native extension points: **skills**, **hooks**, and **CLI**. No daemon, no background process.

## What It Does

- **Task orchestration** — AI agents poll for tasks, follow structured specs, report completion
- **Permission enforcement** — PreToolUse/BeforeTool hook checks approval rules before every tool use
- **Permission logging** — All decisions logged and uploaded to the hub
- **Interventions** — Agents can request human help through the hub
- **Session context** — Agents know their role, assigned tasks, and project on session start

## Supported Agents

| Agent | Skills | Hooks | Status |
|-------|--------|-------|--------|
| **Claude Code** | `~/.claude/skills/orchestratia/` | SessionStart + PreToolUse | Full support |
| **Gemini CLI** | `~/.gemini/skills/orchestratia/` | SessionStart + BeforeTool | Full support |
| **Codex CLI** | `~/.codex/skills/orchestratia/` | SessionStart + PreToolUse | Hooks require feature flag |

## Install

```bash
# Auto-detect and configure all installed agents
curl -sL https://raw.githubusercontent.com/kumarimlab/orchestratia-skills/main/install.sh | bash -s -- <token>

# Configure specific agents only
curl -sL .../install.sh | bash -s -- <token> --agent claude,gemini

# Configure a single agent
curl -sL .../install.sh | bash -s -- <token> --agent gemini
```

The install script:
1. Installs the `orchestratia` CLI (via pip)
2. Downloads hook scripts to `/opt/orchestratia-skills/hooks/`
3. Installs agent-specific SKILL.md files
4. Configures hooks in each agent's settings
5. Registers with your Orchestratia hub
6. Reports which agents were configured and which were not found

### Adding an agent later

If you install a new AI agent after Orchestratia:

```bash
orchestratia setup --agent gemini    # Configure Gemini CLI
orchestratia setup --agent codex     # Configure Codex CLI
orchestratia setup --agent all       # Configure all detected agents
```

## Uninstall

```bash
curl -sL https://raw.githubusercontent.com/kumarimlab/orchestratia-skills/main/uninstall.sh | bash
```

## What Gets Installed

| Component | Location | Purpose |
|-----------|----------|---------|
| SessionStart hook | `/opt/orchestratia-skills/hooks/orchestratia-context.sh` | Injects task context on session start |
| PreToolUse hook | `/opt/orchestratia-skills/hooks/orchestratia-pretooluse.sh` | Checks approval rules before tool use |
| Claude SKILL.md | `~/.claude/skills/orchestratia/SKILL.md` | Claude Code workflow instructions |
| Gemini SKILL.md | `~/.gemini/skills/orchestratia/SKILL.md` | Gemini CLI workflow instructions |
| Codex SKILL.md | `~/.codex/skills/orchestratia/SKILL.md` | Codex CLI workflow instructions |
| Shared SKILL.md | `~/.agents/skills/orchestratia/SKILL.md` | Cross-agent compatible path |
| Config | `/etc/orchestratia/config.yaml` | Hub URL + API key |

## Agent-Specific Notes

### Claude Code
- Hooks configured in `~/.claude/settings.json`
- PreToolUse intercepts all tools (Bash, Edit, Write, Read, etc.)

### Gemini CLI
- Hooks configured in `~/.gemini/settings.json`
- Uses `BeforeTool` event (equivalent to PreToolUse)
- Intercepts all tools
- Also supports `gemini skills install` from this repo

### Codex CLI
- Hooks configured in `~/.codex/hooks.json`
- Requires `features.codex_hooks = true` in `~/.codex/config.toml` (auto-set by installer)
- PreToolUse currently intercepts Bash tool calls only (OpenAI limitation)
- File operations governed by Codex's sandbox and `.codexpolicy` rules

## Comparison with Full Agent

| Feature | Skills (this) | Full Agent Daemon |
|---------|--------------|-------------------|
| Task management | Pull-based (CLI) | Push-based (WebSocket) |
| Permission hooks | Yes | Yes |
| Live terminal in dashboard | No | Yes |
| Session sharing | No | Yes |
| File transfers | No | Yes |
| SSH access grants | No | Yes |
| Session recovery | No | Yes (tmux/ConPTY) |
| Background process | None | Python daemon |
| Supported agents | Claude, Gemini, Codex | Any (agent-agnostic) |

For the full agent daemon, see [orchestratia-agent](https://github.com/kumarimlab/orchestratia-agent).

## Documentation

- [Skills Integration Guide](https://orchestratia.com/docs/skills)
- [Getting Started](https://orchestratia.com/docs/getting-started)
- [AI Agent Guide](https://orchestratia.com/docs/agent-guide)

## License

MIT
