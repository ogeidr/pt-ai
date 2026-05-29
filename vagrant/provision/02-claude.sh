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

# --- CLAUDE.md — VM environment context ----------------------------------
# Loaded automatically by Claude Code for every session.  Tells Claude what
# is installed and how to use it so the user never has to explain it.
cat > "$CLAUDE_DIR/CLAUDE.md" <<'EOF'
# pt-ai Kali VM

Engagement workspace: `/engagements/`

Cloud-audit toolset (pre-installed, on PATH):
- `aws`         — AWS CLI v2
- `prowler`     — multi-cloud security posture scanner (AWS/Azure/GCP/K8s)
- `scout`       — Scout Suite multi-cloud auditor (entry point: `scout`)
- `trufflehog`  — secrets scanner (git/filesystem/S3/GCS/etc.)
- `pacu`        — AWS exploitation framework
- `kube-hunter` — Kubernetes attack-surface scanner (pipx; `kube-hunter --active` for active scan)
EOF
chown vagrant:vagrant "$CLAUDE_DIR/CLAUDE.md"

# --- Shell environment ----------------------------------------------------
# profile.d for interactive-shell extras (PS1).
cat > /etc/profile.d/pt-ai.sh <<'EOF'
# ~/.local/bin holds pipx-installed CLIs (prowler, scoutsuite — see 06-cloud.sh).
export PATH="$HOME/.npm-global/bin:$HOME/.local/bin:$PATH"
export PS1='\[\033[01;31m\][kali-ptai]\[\033[00m\] \[\033[01;34m\]\w\[\033[00m\]\$ '
# Persistent API key — written by './kali key store' on the host.
[ -f "$HOME/.anthropic_key" ] && . "$HOME/.anthropic_key"
EOF
chmod 644 /etc/profile.d/pt-ai.sh
