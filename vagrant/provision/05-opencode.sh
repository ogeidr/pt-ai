#!/usr/bin/env bash
# 05-opencode.sh: Install opencode CLI; expose pt-ai skills (Claude-compat) and
# convert pt-ai agents to opencode subagents; write opencode.json (Anthropic).
#
# opencode runs inside the VM, so it shells out to Kali tools directly — no MCP
# bridge needed (same architectural advantage Claude Code already enjoys here).
# Auth reuses the existing ANTHROPIC_API_KEY plumbing (./pt-ai key store / session
# forwarding).  OAuth-only users (Pro/Max) either add an API key or use a local
# model (./pt-ai local-model — durable config merged below) — opencode does not
# consume Claude Code's ~/.claude/ OAuth tokens.
set -euo pipefail

VAGRANT_HOME="/home/vagrant"
NPM_GLOBAL="$VAGRANT_HOME/.npm-global"
OPENCODE_DIR="$VAGRANT_HOME/.config/opencode"
AGENTS_SRC="/opt/pt-ai/agents"
AGENTS_DST="$OPENCODE_DIR/agents"

# --- opencode CLI ---------------------------------------------------------
# Installed as the vagrant user under the same npm-global prefix as Claude Code
# so self-updates work without root.
# Unconditional @latest: every `./pt-ai provision` pulls the newest release, so
# the provisioner — not just opencode's self-updater — keeps the CLI current.
sudo -u vagrant bash -c "
    npm config set prefix '$NPM_GLOBAL'
    npm install -g opencode-ai@latest
"

# --- skills: nothing to convert ------------------------------------------
# opencode discovers ~/.claude/skills/<name>/SKILL.md natively (Claude-compat
# path) and 02-claude.sh symlinks /opt/pt-ai/skills there. 02 runs before 05
# (numbered ordering), so the symlink is already in place and every pt-ai skill
# is a model-invoked opencode skill for free — bundles, names, and descriptions
# carry over unchanged; opencode ignores the extra frontmatter fields.
# We deliberately do NOT also symlink ~/.config/opencode/skills: opencode would
# then scan the same target via two roots and flag duplicate skill names.

# --- agents → opencode subagents -----------------------------------------
# opencode does not read ~/.claude/agents/, so each /opt/pt-ai/agents/<name>.md
# is rewritten to ~/.config/opencode/agents/<name>.md with opencode frontmatter:
#   description: carried verbatim from the source (drives @mention delegation)
#   mode: subagent
#   permission.bash: deny — emitted only for advisory agents (no Bash in the
#                           source `tools:` list), preserving the advisory vs
#                           Tier-2 boundary Claude enforces via tool grants.
# The same shared blocks 02-claude.sh injects are appended here (same source
# files, same grep-guarded conditions) so opencode agents carry the scope guard,
# findings store, and untrusted-output rules. _* files are shared blocks, not
# standalone agents — skip them. rm -rf first so host-side deletions propagate
# on re-provision (mirrors 02). Files are written as root and chowned to vagrant
# by the existing `chown -R` below.
SCOPE_GUARD="$AGENTS_SRC/_scope-guard.md"
FINDINGS_STORE="$AGENTS_SRC/_findings-store.md"
UNTRUSTED_OUTPUT="$AGENTS_SRC/_untrusted-output.md"

# Native skills + subagents replace the old flatten-to-commands output; clear
# any stale generated commands from a previous provision.
rm -rf "$OPENCODE_DIR/commands"
rm -rf "$AGENTS_DST"
mkdir -p "$AGENTS_DST"

if [ -d "$AGENTS_SRC" ]; then
    for src in "$AGENTS_SRC"/*.md; do
        [ -f "$src" ] || continue
        name=$(basename "$src" .md)
        case "$name" in _*) continue ;; esac
        dst="$AGENTS_DST/${name}.md"

        # Does the source frontmatter grant Bash? Advisory agents omit it.
        bash_perm=""
        if ! awk '
            /^---$/ { n++; if (n>=2) exit; next }
            n==1 && /^[[:space:]]*-[[:space:]]*Bash[[:space:]]*$/ { found=1 }
            n==1 && /^tools:.*Bash/ { found=1 }
            END { exit !found }
        ' "$src"; then
            bash_perm=$'permission:\n  bash: deny\n'
        fi

        # Carry the `description:` block verbatim (folded-scalar lines included):
        # from the description line until the next top-level key or end of frontmatter.
        desc=$(awk '
            /^---$/ { n++; if (n>=2) exit; next }
            n==1 {
                if (/^description:/) { grab=1; print; next }
                if (grab && /^[A-Za-z][A-Za-z0-9_-]*:/) { grab=0 }
                if (grab) print
            }
        ' "$src")

        {
            printf -- '---\n'
            printf '%s\n' "$desc"
            printf 'mode: subagent\n'
            [ -n "$bash_perm" ] && printf '%s' "$bash_perm"
            printf -- '---\n'
            awk 'BEGIN{n=0} /^---$/ && n<2 {n++; next} n>=2{print}' "$src"
        } > "$dst"

        # Inject shared blocks (same conditions as 02-claude.sh).
        if ! grep -qE "Authorization Verification|Scope Enforcement" "$dst"; then
            printf '\n' >> "$dst"; cat "$SCOPE_GUARD" >> "$dst"
        fi
        if ! grep -q "Findings Store" "$dst"; then
            printf '\n' >> "$dst"; cat "$FINDINGS_STORE" >> "$dst"
        fi
        if ! grep -q "Untrusted Tool Output" "$dst"; then
            printf '\n' >> "$dst"; cat "$UNTRUSTED_OUTPUT" >> "$dst"
        fi
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
  "model": "anthropic/claude-sonnet-4-6",
  "permission": {
    "read": {
      "~/.anthropic_key": "deny",
      "*/.anthropic_key": "deny",
      "**/.anthropic_key": "deny",
      "~/.claude/**": "deny",
      "**/.claude/**": "deny",
      "/tmp/.ptai-key": "deny",
      "**/.ptai-key": "deny"
    },
    "bash": {
      "*": "allow",
      "*anthropic_key*": "deny",
      "*/.claude/*": "deny",
      "*/.claude": "deny",
      "*.ptai-key*": "deny"
    }
  }
}
EOF
chown vagrant:vagrant "$OPENCODE_DIR/opencode.json"

# --- optional: durable local-model provider (LM Studio / Ollama) -----------
# Default-off: only fires when the operator created config/opencode/local-model.json
# (see local-model.json.example), e.g. via `./pt-ai local-model use <id>`. Merges a
# `local` provider + sets it as the default model. Idempotent: opencode.json is
# regenerated fresh above, so this overwrite-set converges to the same result every
# provision — which is what lets a local-model setup survive provision and destroy/up.
LOCAL_MODEL_CFG="/vagrant/config/opencode/local-model.json"
if [ -f "$LOCAL_MODEL_CFG" ]; then
    lm_url=$(jq -r '.url // empty' "$LOCAL_MODEL_CFG")
    lm_model=$(jq -r '.model // empty' "$LOCAL_MODEL_CFG")
    if [ -n "$lm_url" ] && [ -n "$lm_model" ]; then
        lm_tmp=$(mktemp)
        jq --arg u "$lm_url" --arg m "$lm_model" \
           '.provider.local={npm:"@ai-sdk/openai-compatible",options:{baseURL:$u},models:{($m):{name:$m}}} | .model=("local/"+$m)' \
           "$OPENCODE_DIR/opencode.json" > "$lm_tmp" && mv "$lm_tmp" "$OPENCODE_DIR/opencode.json"
        chown vagrant:vagrant "$OPENCODE_DIR/opencode.json"
        echo "opencode: merged local-model provider ($lm_model @ $lm_url)"
    else
        echo "WARN: $LOCAL_MODEL_CFG present but missing .url/.model — skipping local-model merge" >&2
    fi
fi

# --- runtime safety guard (parity with the Claude PreToolUse hook) ---------
# opencode does not read ~/.claude/, so the credential-exfil / catastrophic-rm
# gate 02-claude.sh installs for Claude Code is wired here too — closing the
# "Claude-front-end only" gap for PENDING #1/#2/#5. Two layers, like Claude:
#   1. opencode.json `permission` denies (static, above) — covers the read tool.
#   2. a tool.execute.before plugin that reuses the SAME pt-ai-guard.sh, so bash
#      gets the precise, fail-closed gate (not just coarse globs).
# The guard script is the single source of truth (lives in config/claude/hooks/);
# we install a copy into opencode's dir so this path is self-contained.
# Sources come from the default synced folder mounted at /vagrant (the repo's
# vagrant/ dir) — the same mount 02-claude.sh reads its config from, NOT the
# narrower /opt/pt-ai/{agents,skills} folders.
GUARD_SRC="/vagrant/config/claude/hooks/pt-ai-guard.sh"
PLUGIN_SRC="/vagrant/config/opencode/plugins/pt-ai-guard.js"
if [ -f "$GUARD_SRC" ] && [ -f "$PLUGIN_SRC" ]; then
    sudo -u vagrant mkdir -p "$OPENCODE_DIR/plugins"
    sudo -u vagrant cp "$GUARD_SRC" "$OPENCODE_DIR/pt-ai-guard.sh"
    sudo -u vagrant chmod +x "$OPENCODE_DIR/pt-ai-guard.sh"
    sudo -u vagrant cp "$PLUGIN_SRC" "$OPENCODE_DIR/plugins/pt-ai-guard.js"
    chown -R vagrant:vagrant "$OPENCODE_DIR/plugins" "$OPENCODE_DIR/pt-ai-guard.sh"
else
    echo "WARN: pt-ai-guard sources missing; opencode runtime guard NOT installed" >&2
fi
