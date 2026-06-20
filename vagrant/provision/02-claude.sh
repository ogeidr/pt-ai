#!/usr/bin/env bash
# 02-claude.sh: Install Claude Code CLI; configure agents/skills for the vagrant user.
set -euo pipefail

VAGRANT_HOME="/home/vagrant"
CLAUDE_DIR="$VAGRANT_HOME/.claude"
NPM_GLOBAL="$VAGRANT_HOME/.npm-global"

# --- Claude Code CLI -------------------------------------------------------
# Install as the vagrant user with a user-local npm prefix so that Claude Code
# can update itself without needing root (global npm is root-owned).
# Unconditional @latest: every `./pt-ai provision` pulls the newest release, so
# the provisioner — not just the tool's self-updater — keeps the CLI current.
sudo -u vagrant bash -c "
    npm config set prefix '$NPM_GLOBAL'
    npm install -g @anthropic-ai/claude-code@latest
"

# Add user npm bin to PATH for all sessions.
if ! grep -q '\.npm-global/bin' "$VAGRANT_HOME/.bashrc" 2>/dev/null; then
    echo 'export PATH="$HOME/.npm-global/bin:$PATH"' >> "$VAGRANT_HOME/.bashrc"
fi

# --- pt-ai agents/skills --------------------------------------------------
mkdir -p "$CLAUDE_DIR"

# Agents: copy source files into ~/.claude/agents/ and append the build-time
# templates to any agent missing them:
#   _scope-guard.md       — if the agent lacks both scope sentinels
#   _findings-store.md    — if the agent lacks a "Findings Store" section
#   _untrusted-output.md  — if the agent lacks an "Untrusted Tool Output" section
# This guarantees every agent enforces scope, shares the findings store, and
# treats tool output as untrusted data — even if the manual copy step was
# forgotten when the agent was authored, and for any agent added in the future.
# Re-provisioning regenerates the directory from source (idempotent).
SCOPE_GUARD="/opt/pt-ai/agents/_scope-guard.md"
FINDINGS_STORE="/opt/pt-ai/agents/_findings-store.md"
UNTRUSTED_OUTPUT="/opt/pt-ai/agents/_untrusted-output.md"
AGENTS_DST="$CLAUDE_DIR/agents"
rm -rf "$AGENTS_DST"
mkdir -p "$AGENTS_DST"
for src in /opt/pt-ai/agents/*.md; do
    fname=$(basename "$src")
    [[ "$fname" == _* ]] && continue   # exclude _*.md helpers (scope-guard, findings-store, untrusted-output)
    dst="$AGENTS_DST/$fname"
    cp "$src" "$dst"
    if ! grep -qE "Authorization Verification|Scope Enforcement" "$dst"; then
        printf '\n' >> "$dst"
        cat "$SCOPE_GUARD" >> "$dst"
    fi
    if ! grep -q "Findings Store" "$dst"; then
        printf '\n' >> "$dst"
        cat "$FINDINGS_STORE" >> "$dst"
    fi
    if ! grep -q "Untrusted Tool Output" "$dst"; then
        printf '\n' >> "$dst"
        cat "$UNTRUSTED_OUTPUT" >> "$dst"
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
  mkdir -p "$ENGAGEMENT_DIR/scans" "$ENGAGEMENT_DIR/reports" "$ENGAGEMENT_DIR/exploit"
  ```
- Evidence is organized into category subfolders under `$ENGAGEMENT_DIR/`:
  - `scans/`   — raw tool output: `scans/{tool}_{target}_{YYYYMMDD_HHMMSS}.{ext}`
  - `reports/` — consolidated markdown summaries: `reports/{name}_{YYYYMMDD_HHMMSS}.md`
  - `exploit/` — PoC scripts, attack-chain steps, exploitation artifacts
  - (`re/` and `samples/` are used by the reverse-engineering skills.)
  Control files (`scope.md`, `findings.jsonl`, `gates.jsonl`) stay at the engagement root.
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

# --- Claude settings.json + hooks (runtime guardrails) --------------------
# settings.json adds permission deny-rules and a PreToolUse(Bash) hook that
# blocks any agent command touching the operator's Anthropic/Claude credential —
# the runtime backstop for PENDING.md findings #1 (ambient credential read) and
# #2 (prompt-injection-driven exfil). Claude Code front-end only; opencode reads
# its own config, so the host egress allowlist covers that path.
# Source lives in the repo at vagrant/config/claude/ (mounted at /vagrant).
CLAUDE_SRC="/vagrant/config/claude"
if [ -d "$CLAUDE_SRC" ]; then
    cp "$CLAUDE_SRC/settings.json" "$CLAUDE_DIR/settings.json"
    mkdir -p "$CLAUDE_DIR/hooks"
    cp "$CLAUDE_SRC/hooks/"*.sh "$CLAUDE_DIR/hooks/"
    chmod 0755 "$CLAUDE_DIR/hooks/"*.sh
    chown -R vagrant:vagrant "$CLAUDE_DIR/settings.json" "$CLAUDE_DIR/hooks"
else
    echo "02-claude.sh: WARNING — $CLAUDE_SRC not found; settings.json/hooks not installed" >&2
fi

# --- Shell environment ----------------------------------------------------
# profile.d for interactive-shell extras (PS1).
cat > /etc/profile.d/pt-ai.sh <<'EOF'
# ~/.local/bin holds pipx-installed CLIs (prowler, scoutsuite — see 06-cloud.sh).
export PATH="$HOME/.npm-global/bin:$HOME/.local/bin:$PATH"
export PS1='\[\033[01;31m\][kali-ptai]\[\033[00m\] \[\033[01;34m\]\w\[\033[00m\]\$ '
# OPSEC ceiling default for the runtime guard (PENDING #14): QUIET|MODERATE|LOUD.
# Override per engagement via /engagements/.opsec_ceiling or by exporting this var.
export PT_AI_OPSEC_LIMIT="${PT_AI_OPSEC_LIMIT:-MODERATE}"
# Persistent API key — written by './pt-ai key store' on the host.
[ -f "$HOME/.anthropic_key" ] && . "$HOME/.anthropic_key"
EOF
chmod 644 /etc/profile.d/pt-ai.sh
