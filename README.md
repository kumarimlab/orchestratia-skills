# Orchestratia Skills

Lightweight Claude Code integration for [Orchestratia](https://orchestratia.com) — the AI agent orchestration platform.

This package adds Orchestratia capabilities to Claude Code using native extension points: **skills**, **hooks**, and **CLI**. No daemon, no background process.

## What It Does

- **Task orchestration** — Claude polls for tasks, follows structured specs, reports completion
- **Permission enforcement** — PreToolUse hook checks approval rules before every tool use
- **Permission logging** — All decisions logged and uploaded to the hub
- **Interventions** — Claude can request human help through the hub
- **Session context** — Claude knows its role, assigned tasks, and project

## Install

```bash
# One-liner with registration token from Orchestratia dashboard
curl -sL https://raw.githubusercontent.com/kumarimlab/orchestratia-skills/main/install.sh | bash -s -- <token>
```

The install script:
1. Installs the `orchestratia` CLI (via pip)
2. Downloads hook scripts to `/opt/orchestratia-skills/`
3. Installs SKILL.md to `~/.claude/skills/orchestratia/`
4. Configures Claude Code hooks in `~/.claude/settings.json`
5. Registers with your Orchestratia hub

## Uninstall

```bash
curl -sL https://raw.githubusercontent.com/kumarimlab/orchestratia-skills/main/uninstall.sh | bash
```

## What Gets Installed

| Component | Location | Purpose |
|-----------|----------|---------|
| SessionStart hook | `/opt/orchestratia-skills/hooks/orchestratia-context.sh` | Injects task context when Claude starts |
| PreToolUse hook | `/opt/orchestratia-skills/hooks/orchestratia-pretooluse.sh` | Checks approval rules before tool use |
| SKILL.md | `~/.claude/skills/orchestratia/SKILL.md` | Teaches Claude the Orchestratia workflow |
| Config | `/etc/orchestratia/config.yaml` | Hub URL + API key |

## Comparison with Full Agent

| Feature | Skills (this) | Full Agent |
|---------|--------------|------------|
| Task management | Pull-based (CLI) | Push-based (WebSocket) |
| Permission hooks | Yes | Yes |
| Live terminal in dashboard | No | Yes |
| Session recovery | No | Yes |
| File transfers | No | Yes |
| Background process | None | Python daemon |

For the full agent, see [orchestratia-agent](https://github.com/kumarimlab/orchestratia-agent).

## License

MIT
