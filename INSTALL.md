# Installation

## Prerequisites

- Docker (Engine on Linux, Docker Desktop on macOS)
- An Anthropic API key **or** a Claude Pro/Max subscription
- A reachable Linux host running `kali-server-mcp` on `127.0.0.1:5000`

See [docker/README.md](docker/README.md) for the full architecture and setup walkthrough.

## Docker (recommended)

```bash
git clone https://github.com/ogeid/pt-ai.git
cd pt-ai
docker/ptai build
docker/ptai auth        # first time only
docker/ptai run <engagement-id>
```

Agents are bind-mounted directly from `agents/` — no install step needed. Each engagement runs in a throwaway container; only the evidence directory under `engagements/<engagement-id>/` survives.

## Manual (no Docker)

If you want the agents available in a local Claude Code session without Docker:

```bash
# Global — available in all Claude Code sessions
cp agents/*.md ~/.claude/agents/

# Project-level — available only in the current directory
mkdir -p .claude/agents && cp agents/*.md .claude/agents/
```
