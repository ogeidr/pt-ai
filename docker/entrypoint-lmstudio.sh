#!/bin/sh
# pt-ai-lmstudio entrypoint.
#
# Converts pt-ai agents to opencode commands, generates opencode.json pointing
# at LM Studio on the host, registers the MCP bridge, probes both services for
# readiness, then execs the command (opencode by default).
#
# Required env:
#   PT_AI_LM_STUDIO_MODEL   model identifier as shown in LM Studio
#   PT_AI_MCP_SERVER        URL of the remote kali-server-mcp API
#
# Optional env:
#   PT_AI_LM_STUDIO_URL     LM Studio base URL (default: http://host.docker.internal:1234)
#
set -eu

LM_STUDIO_URL="${PT_AI_LM_STUDIO_URL:-http://host.docker.internal:1234}"
AGENTS_DIR=/opt/pt-ai/agents

# --- require LM Studio model name ----------------------------------------
if [ -z "${PT_AI_LM_STUDIO_MODEL:-}" ]; then
    echo "pt-ai-lmstudio: PT_AI_LM_STUDIO_MODEL is required." >&2
    echo "  Set it to the model identifier shown in LM Studio." >&2
    echo "  Example:" >&2
    echo "    PT_AI_LM_STUDIO_MODEL=google/gemma-3-27b docker/ptai-lmstudio run <id>" >&2
    exit 1
fi

# --- require remote MCP URL ----------------------------------------------
if [ -z "${PT_AI_MCP_SERVER:-}" ]; then
    echo "pt-ai-lmstudio: PT_AI_MCP_SERVER is required." >&2
    echo "  This container ships only the MCP bridge; the API server must run" >&2
    echo "  on a separate Linux host (typically your Kali VM)." >&2
    echo "  Example:" >&2
    echo "    PT_AI_MCP_SERVER=http://host.docker.internal:5000 docker/ptai-lmstudio run <id>" >&2
    echo "  See docker/README-lmstudio.md for the full setup." >&2
    exit 1
fi

# --- vendored MCP bridge paths -------------------------------------------
MCP_PY=/opt/mcp-bridge/.venv/bin/python3
MCP_CLIENT=/opt/mcp-bridge/client.py
if [ ! -x "$MCP_PY" ] || [ ! -f "$MCP_CLIENT" ]; then
    echo "pt-ai-lmstudio: vendored MCP bridge missing at /opt/mcp-bridge — image build is incomplete." >&2
    exit 1
fi

# --- convert agents to opencode commands ---------------------------------
# Strip YAML frontmatter from each agent and write to the opencode commands dir.
# _* files (shared prompt blocks) are skipped — they are not standalone commands.
CMD_DIR="$HOME/.config/opencode/commands"
mkdir -p "$CMD_DIR"
if [ -d "$AGENTS_DIR" ]; then
    for agent in "$AGENTS_DIR"/*.md; do
        [ -f "$agent" ] || continue
        name=$(basename "$agent" .md)
        case "$name" in _*) continue ;; esac
        awk 'BEGIN{found=0} /^---$/ && found<2 {found++; next} found>=2{print}' \
            "$agent" > "$CMD_DIR/${name}.md"
    done
fi

# --- generate opencode.json ----------------------------------------------
# Points opencode at LM Studio via the OpenAI-compatible provider.
# MCP bridge is registered as a local stdio server.
mkdir -p "$HOME/.config/opencode"
jq -n \
    --arg base_url "${LM_STUDIO_URL}/v1" \
    --arg model_id "${PT_AI_LM_STUDIO_MODEL}" \
    --arg model    "lmstudio/${PT_AI_LM_STUDIO_MODEL}" \
    --arg mcp_py   "$MCP_PY" \
    --arg mcp_cl   "$MCP_CLIENT" \
    --arg mcp_url  "$PT_AI_MCP_SERVER" \
    '{
        "$schema": "https://opencode.ai/config.json",
        provider: {
            lmstudio: {
                npm:  "@ai-sdk/openai-compatible",
                name: "LM Studio",
                options: { baseURL: $base_url },
                models: { ($model_id): { name: $model_id } }
            }
        },
        model: $model,
        mcp: {
            kali: {
                type: "local",
                command: [$mcp_py, $mcp_cl, "--server", $mcp_url],
                enabled: true
            }
        }
    }' > "$HOME/.config/opencode/opencode.json"

# --- probe LM Studio for readiness (~5s) ---------------------------------
i=0
ok=0
while [ "$i" -lt 25 ]; do
    if curl -fs -o /dev/null "${LM_STUDIO_URL}/v1/models" 2>/dev/null; then
        ok=1
        break
    fi
    sleep 0.2
    i=$((i + 1))
done

if [ "$ok" = "0" ]; then
    echo "pt-ai-lmstudio: warning — LM Studio at $LM_STUDIO_URL is not reachable." >&2
    echo "  Check that:" >&2
    echo "    1. LM Studio is running and the local server is started." >&2
    echo "    2. A model is loaded in LM Studio." >&2
    echo "    3. PT_AI_LM_STUDIO_URL is correct (currently $LM_STUDIO_URL)." >&2
    echo "  Continuing anyway; LLM calls will fail until LM Studio is reachable." >&2
fi

# --- probe the remote MCP for readiness (~5s) ----------------------------
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
    echo "pt-ai-lmstudio: warning — remote MCP at $PT_AI_MCP_SERVER is not reachable." >&2
    echo "  Check that:" >&2
    echo "    1. The remote kali-server-mcp is running (listening on 127.0.0.1:5000 on the Kali host)." >&2
    echo "    2. Your SSH tunnel is up (e.g. 'ssh -L 5000:127.0.0.1:5000 user@vm -N')." >&2
    echo "    3. PT_AI_MCP_SERVER points at the correct URL (currently $PT_AI_MCP_SERVER)." >&2
    echo "  Continuing anyway; MCP tool calls will fail until the server is reachable." >&2
fi

cd /work
exec "$@"
