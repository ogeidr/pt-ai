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
    if [ ! -d '$NPM_GLOBAL/lib/node_modules/@anthropic-ai/claude-code' ]; then
        npm install -g @anthropic-ai/claude-code@latest
    fi
"

# Add user npm bin to PATH for all sessions.
if ! grep -q '\.npm-global/bin' "$VAGRANT_HOME/.bashrc" 2>/dev/null; then
    echo 'export PATH="$HOME/.npm-global/bin:$PATH"' >> "$VAGRANT_HOME/.bashrc"
fi

# --- pt-ai agents/skills --------------------------------------------------
mkdir -p "$CLAUDE_DIR"

# Agents: copy source files into ~/.claude/agents/ and append _scope-guard.md
# to any agent that is missing both scope sentinels.  This guarantees every
# agent enforces scope even if the manual copy step was forgotten when the
# agent was authored.  Re-provisioning regenerates the directory from source.
SCOPE_GUARD="/opt/pt-ai/agents/_scope-guard.md"
AGENTS_DST="$CLAUDE_DIR/agents"
rm -rf "$AGENTS_DST"
mkdir -p "$AGENTS_DST"
for src in /opt/pt-ai/agents/*.md; do
    fname=$(basename "$src")
    [[ "$fname" == _* ]] && continue   # exclude _scope-guard.md and any future _*.md helpers
    dst="$AGENTS_DST/$fname"
    cp "$src" "$dst"
    if ! grep -qE "Authorization Verification|Scope Enforcement" "$dst"; then
        printf '\n' >> "$dst"
        cat "$SCOPE_GUARD" >> "$dst"
    fi
done

# Skills: symlink as before (scope enforcement handled via bang preambles).
ln -sfn /opt/pt-ai/skills "$CLAUDE_DIR/skills"
chown -R vagrant:vagrant "$CLAUDE_DIR"

# --- CLAUDE.md — VM environment context ----------------------------------
# Loaded automatically by Claude Code for every session.  Tells Claude what
# is installed and how to use it so the user never has to explain it.
cat > "$CLAUDE_DIR/CLAUDE.md" <<'EOF'
# pt-ai pentest VM

Engagement workspace: `/engagements/` (host-synced — always use absolute paths here)

## Evidence path rules (MANDATORY)
- ALL evidence files must use absolute paths under `/engagements/`.
- Never use relative filenames — CWD can drift during a session and evidence will be lost.
- Run `/scope-declare` first. It writes `/engagements/scope.md` and creates the
  per-engagement subdirectory `/engagements/{safe_id}/`.
- Derive the evidence directory for any session: read the "Evidence directory:" line
  from `/engagements/scope.md`, e.g.:
  ```sh
  ENGAGEMENT_DIR=$(grep -m1 'Evidence directory:' /engagements/scope.md | sed 's/.*Evidence directory: //')
  mkdir -p "$ENGAGEMENT_DIR"
  ```
- Save all tool output to `$ENGAGEMENT_DIR/{tool}_{target}_{YYYYMMDD_HHMMSS}.{ext}`.
- Before the first scan, verify the mount: `test -d /engagements && test -w /engagements`.

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
# Persistent API key — written by './pt-ai key store' on the host.
[ -f "$HOME/.anthropic_key" ] && . "$HOME/.anthropic_key"
EOF
chmod 644 /etc/profile.d/pt-ai.sh
