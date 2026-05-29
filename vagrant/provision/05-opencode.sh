#!/usr/bin/env bash
# 05-opencode.sh: Install opencode CLI; convert pt-ai agents to opencode commands;
# write opencode.json with the native Anthropic provider.
#
# opencode runs inside the VM, so it shells out to Kali tools directly — no MCP
# bridge needed (same architectural advantage Claude Code already enjoys here).
# Auth reuses the existing ANTHROPIC_API_KEY plumbing (./kali key store / session
# forwarding).  OAuth-only users (Pro/Max) must add an API key — opencode does
# not consume Claude Code's ~/.claude/ OAuth tokens.
set -euo pipefail

VAGRANT_HOME="/home/vagrant"
NPM_GLOBAL="$VAGRANT_HOME/.npm-global"
OPENCODE_DIR="$VAGRANT_HOME/.config/opencode"
CMD_DIR="$OPENCODE_DIR/commands"
AGENTS_SRC="/opt/pt-ai/agents"
COMMANDS_SRC="/opt/pt-ai/commands"

# --- opencode CLI ---------------------------------------------------------
# Installed as the vagrant user under the same npm-global prefix as Claude Code
# so self-updates work without root.
sudo -u vagrant bash -c "
    npm config set prefix '$NPM_GLOBAL'
    if ! '$NPM_GLOBAL/bin/opencode' --version >/dev/null 2>&1; then
        npm install -g opencode-ai@latest
    fi
"

# --- agent → command conversion -------------------------------------------
# opencode commands are plain markdown without YAML frontmatter.  Strip the
# frontmatter from each agent file and write it into ~/.config/opencode/commands/.
# _* files are shared prompt blocks, not standalone commands — skip them.
# Re-runs cleanly: previously-generated files in CMD_DIR are removed first so
# deletions on the host propagate.
sudo -u vagrant mkdir -p "$CMD_DIR"
sudo -u vagrant find "$CMD_DIR" -maxdepth 1 -type f -name '*.md' -delete

if [ -d "$AGENTS_SRC" ]; then
    for agent in "$AGENTS_SRC"/*.md; do
        [ -f "$agent" ] || continue
        name=$(basename "$agent" .md)
        case "$name" in _*) continue ;; esac
        awk 'BEGIN{found=0} /^---$/ && found<2 {found++; next} found>=2{print}' \
            "$agent" > "$CMD_DIR/${name}.md"
    done
fi

# pt-ai commands/ are already plain markdown — copy verbatim.
if [ -d "$COMMANDS_SRC" ]; then
    for cmd in "$COMMANDS_SRC"/*.md; do
        [ -f "$cmd" ] || continue
        cp "$cmd" "$CMD_DIR/$(basename "$cmd")"
    done
fi

chown -R vagrant:vagrant "$OPENCODE_DIR"

# --- opencode.json --------------------------------------------------------
# Native Anthropic provider, default model claude-sonnet-4-6.  Kept minimal so
# additional providers (LM Studio, Ollama, OpenAI-compat) can be added with a
# few-line edit.  Model can be overridden per session via PT_AI_OPENCODE_MODEL
# (the ./kali opencode wrapper forwards it).
cat > "$OPENCODE_DIR/opencode.json" <<'EOF'
{
  "$schema": "https://opencode.ai/config.json",
  "model": "anthropic/claude-sonnet-4-6"
}
EOF
chown vagrant:vagrant "$OPENCODE_DIR/opencode.json"
