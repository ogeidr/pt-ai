#!/usr/bin/env bash
# 02-claude.sh: Install Claude Code CLI; configure agents/skills for the vagrant user.
set -euo pipefail

VAGRANT_HOME="/home/vagrant"
CLAUDE_DIR="$VAGRANT_HOME/.claude"
NPM_GLOBAL="$VAGRANT_HOME/.npm-global"

# --- Claude Code CLI -------------------------------------------------------
# Install as the vagrant user with a user-local npm prefix so that Claude Code
# can update itself without needing root (global npm is root-owned).
sudo -u vagrant bash -c "
    npm config set prefix '$NPM_GLOBAL'
    if ! '$NPM_GLOBAL/bin/claude' --version >/dev/null 2>&1; then
        npm install -g @anthropic-ai/claude-code@stable
    fi
"

# Add user npm bin to PATH for all sessions.
if ! grep -q '\.npm-global/bin' "$VAGRANT_HOME/.bashrc" 2>/dev/null; then
    echo 'export PATH="$HOME/.npm-global/bin:$PATH"' >> "$VAGRANT_HOME/.bashrc"
fi

# --- pt-ai agents/skills --------------------------------------------------
mkdir -p "$CLAUDE_DIR"
# Synced folders are already mounted at /opt/pt-ai/; link into .claude so
# Claude Code discovers them without duplication.
ln -sfn /opt/pt-ai/agents "$CLAUDE_DIR/agents"
ln -sfn /opt/pt-ai/skills "$CLAUDE_DIR/skills"
chown -R vagrant:vagrant "$CLAUDE_DIR"

# --- Shell environment ----------------------------------------------------
# profile.d for interactive-shell extras (PS1).
cat > /etc/profile.d/pt-ai.sh <<'EOF'
export PATH="$HOME/.npm-global/bin:$PATH"
export PS1='\[\033[01;31m\][kali-ptai]\[\033[00m\] \[\033[01;34m\]\w\[\033[00m\]\$ '
# Persistent API key — written by './kali key store' on the host.
[ -f "$HOME/.anthropic_key" ] && . "$HOME/.anthropic_key"
EOF
chmod 644 /etc/profile.d/pt-ai.sh
