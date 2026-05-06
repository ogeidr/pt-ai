#!/bin/sh
# pt-ai entrypoint.
#
# Runs inside the container. Verifies auth, registers the kali MCP bridge in
# Claude Code's config pointing at the remote API URL, probes that URL for
# readiness, then execs the command (claude by default).
#
# PT_AI_MCP_SERVER is required: the URL of the remote kali-server-mcp API
# (typical value: http://host.docker.internal:5000, with an SSH tunnel
# forwarding that to a Linux host running kali-server-mcp on 127.0.0.1:5000).
#
set -eu

# --- auth presence check --------------------------------------------------
# Either an API key in the env, or a credential file from a prior `ptai auth`.
if [ -z "${ANTHROPIC_API_KEY:-}" ] && [ ! -f "$HOME/.claude/.credentials.json" ]; then
    echo "pt-ai: no authentication available." >&2
    echo "  Either export ANTHROPIC_API_KEY before launching, or run 'ptai auth'" >&2
    echo "  on the host first to perform a one-time browser OAuth login." >&2
    exit 1
fi

# --- require remote MCP URL ----------------------------------------------
if [ -z "${PT_AI_MCP_SERVER:-}" ]; then
    echo "pt-ai: PT_AI_MCP_SERVER is required." >&2
    echo "  This container ships only the MCP bridge; the API server must run" >&2
    echo "  on a separate Linux host (typically your Kali VM)." >&2
    echo "  Example:" >&2
    echo "    PT_AI_MCP_SERVER=http://host.docker.internal:5000 docker/ptai run <id>" >&2
    echo "  See docker/README.md for the full setup." >&2
    exit 1
fi

# --- vendored MCP bridge paths --------------------------------------------
MCP_PY=/opt/mcp-bridge/.venv/bin/python3
MCP_CLIENT=/opt/mcp-bridge/client.py
if [ ! -x "$MCP_PY" ] || [ ! -f "$MCP_CLIENT" ]; then
    echo "pt-ai: vendored MCP bridge missing at /opt/mcp-bridge — image build is incomplete." >&2
    exit 1
fi

# --- register the kali MCP server in ~/.claude.json (idempotent) ----------
# Claude Code 2.x reads MCP server config from ~/.claude.json under the
# "mcpServers" key. We merge our entry in via jq so it persists alongside
# whatever else Claude Code has written there.
CLAUDE_JSON="$HOME/.claude.json"
# Seed the file in place; bind-mounted file inode must be preserved, so we
# write contents (cat >) rather than replace (mv).
[ -s "$CLAUDE_JSON" ] || printf '{}' > "$CLAUDE_JSON"
TMP_JSON=$(mktemp)
if jq --arg py "$MCP_PY" --arg client "$MCP_CLIENT" --arg url "$PT_AI_MCP_SERVER" '.mcpServers.kali = {
        "type": "stdio",
        "command": $py,
        "args": [$client, "--server", $url]
    }' "$CLAUDE_JSON" > "$TMP_JSON" 2>/dev/null; then
    cat "$TMP_JSON" > "$CLAUDE_JSON"
fi
rm -f "$TMP_JSON"

# --- probe the remote MCP for readiness (~5s max) ------------------------
i=0
ok=0
while [ "$i" -lt 25 ]; do
    if curl -fs -o /dev/null "${PT_AI_MCP_SERVER}/health" 2>/dev/null \
        || curl -fs -o /dev/null "${PT_AI_MCP_SERVER}/" 2>/dev/null; then
        ok=1
        break
    fi
    sleep 0.2
    i=$((i + 1))
done

if [ "$ok" = "0" ]; then
    echo "pt-ai: warning — remote MCP at $PT_AI_MCP_SERVER is not reachable." >&2
    echo "  Check that:" >&2
    echo "    1. The remote kali-server-mcp is running (listening on 127.0.0.1:5000 on the Kali host)." >&2
    echo "    2. Your SSH tunnel is up (e.g. 'ssh -L 5000:127.0.0.1:5000 user@vm -N')." >&2
    echo "    3. PT_AI_MCP_SERVER points at the correct URL (currently $PT_AI_MCP_SERVER)." >&2
    echo "  Continuing anyway; MCP tool calls will fail until the server is reachable." >&2
fi

cd /work
exec "$@"
