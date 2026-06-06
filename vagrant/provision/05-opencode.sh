#!/usr/bin/env bash
# 05-opencode.sh: Install opencode CLI; convert pt-ai agents to opencode commands;
# write opencode.json with the native Anthropic provider.
#
# opencode runs inside the VM, so it shells out to Kali tools directly — no MCP
# bridge needed (same architectural advantage Claude Code already enjoys here).
# Auth reuses the existing ANTHROPIC_API_KEY plumbing (./pt-ai key store / session
# forwarding).  OAuth-only users (Pro/Max) must add an API key — opencode does
# not consume Claude Code's ~/.claude/ OAuth tokens.
set -euo pipefail

VAGRANT_HOME="/home/vagrant"
NPM_GLOBAL="$VAGRANT_HOME/.npm-global"
OPENCODE_DIR="$VAGRANT_HOME/.config/opencode"
CMD_DIR="$OPENCODE_DIR/commands"
AGENTS_SRC="/opt/pt-ai/agents"
SKILLS_SRC="/opt/pt-ai/skills"

# --- opencode CLI ---------------------------------------------------------
# Installed as the vagrant user under the same npm-global prefix as Claude Code
# so self-updates work without root.
sudo -u vagrant bash -c "
    npm config set prefix '$NPM_GLOBAL'
    if ! '$NPM_GLOBAL/bin/opencode' --version >/dev/null 2>&1; then
        npm install -g opencode-ai@latest
    fi
"

# --- agent / skill → opencode command conversion -------------------------
# opencode commands accept YAML frontmatter (description / agent / model)
# plus a markdown body.  Two sources feed into ~/.config/opencode/commands/:
#
#   agents/<name>.md         → strip frontmatter, emit body only
#                              (agents become commands so users can type
#                               /recon-advisor etc.)
#   skills/<name>/SKILL.md   → rewrite frontmatter to keep only `description:`,
#                              emit body (bang-prefix preambles transplant
#                              verbatim — opencode honours them too)
#
# Precedence: skills override agents on filename collision.
# _* files are shared prompt blocks, not standalone commands — skip them.
# Re-runs cleanly: previously-generated files in CMD_DIR are removed first so
# deletions on the host propagate.
sudo -u vagrant mkdir -p "$CMD_DIR"
sudo -u vagrant find "$CMD_DIR" -maxdepth 1 -type f -name '*.md' -delete

# Pass 1 — agents (strip frontmatter, body only)
if [ -d "$AGENTS_SRC" ]; then
    for agent in "$AGENTS_SRC"/*.md; do
        [ -f "$agent" ] || continue
        name=$(basename "$agent" .md)
        case "$name" in _*) continue ;; esac
        awk 'BEGIN{found=0} /^---$/ && found<2 {found++; next} found>=2{print}' \
            "$agent" > "$CMD_DIR/${name}.md"
    done
fi

# Pass 2 — skills (derived; overrides agents — skill is the source of truth)
# The awk keeps the opening `---`, retains only `description:` (plus its YAML
# folded-scalar continuation lines) from the skill frontmatter, emits the
# closing `---`, and passes the body through unchanged.  The body's
# `!`cmd`` bang preambles work in opencode without any rewrite.
if [ -d "$SKILLS_SRC" ]; then
    for skill in "$SKILLS_SRC"/*/SKILL.md; do
        [ -f "$skill" ] || continue
        name=$(basename "$(dirname "$skill")")
        case "$name" in _*) continue ;; esac
        awk '
            BEGIN { state = 0; keep = 0 }
            /^---$/ {
                state++
                if (state <= 2) { print; next }
            }
            state == 1 {
                if (/^[A-Za-z][A-Za-z0-9_-]*:/) {
                    keep = /^description:/
                }
                if (keep) print
                next
            }
            state >= 2 { print }
        ' "$skill" > "$CMD_DIR/${name}.md"
    done
fi

chown -R vagrant:vagrant "$OPENCODE_DIR"

# --- opencode.json --------------------------------------------------------
# Native Anthropic provider, default model claude-sonnet-4-6.  Kept minimal so
# additional providers (LM Studio, Ollama, OpenAI-compat) can be added with a
# few-line edit.  Model can be overridden per session via PT_AI_OPENCODE_MODEL
# (the ./pt-ai opencode wrapper forwards it).
cat > "$OPENCODE_DIR/opencode.json" <<'EOF'
{
  "$schema": "https://opencode.ai/config.json",
  "model": "anthropic/claude-sonnet-4-6"
}
EOF
chown vagrant:vagrant "$OPENCODE_DIR/opencode.json"
