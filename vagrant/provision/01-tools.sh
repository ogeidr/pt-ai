#!/usr/bin/env bash
# 01-tools.sh: Install Kali toolset.
# Arg $1: path to tools.txt (default: /vagrant/config/tools.txt)
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
# shellcheck source=/dev/null
. /vagrant/provision/_lib.sh

TOOLS_FILE="${1:-/vagrant/config/tools.txt}"

if ! $IS_APT; then
    echo "[01-tools] non-apt distro — skipping toolset install (out of scope)" >&2
    exit 0
fi

apt-get update -y

# Core Kali metapackage — Kali guests only (huge/incompatible elsewhere).
if $IS_KALI; then
    apt-get install -y kali-linux-default || \
        echo "Warning: kali-linux-default partially failed — continuing" >&2
fi

# Additional tools from config/tools.txt
if [ -f "$TOOLS_FILE" ]; then
    while IFS= read -r pkg || [ -n "$pkg" ]; do
        [[ -z "$pkg" || "$pkg" == \#* ]] && continue
        apt-get install -y "$pkg" || \
            echo "Warning: failed to install $pkg — skipping" >&2
    done < "$TOOLS_FILE"
fi

# Offensive tools with no apt package on any supported box (verified 2026-06-14).
# Same non-apt patterns 06-cloud.sh uses; kept here because this is the offensive
# toolset's owning script. All best-effort so they can never block provisioning.
#   frida-tools, objection — mobile instrumentation (pipx, per-user)
#   kerbrute               — AD user-enum/spray (Go binary, system-wide)
# pipx normally arrives in 06-cloud (runs later), so ensure it here first.
command -v pipx >/dev/null 2>&1 || apt-get install -y --no-install-recommends pipx
sudo -u vagrant bash -c '
    pipx ensurepath >/dev/null 2>&1 || true
    [ -d "$HOME/.local/share/pipx/venvs/frida-tools" ] || pipx install frida-tools || echo "Warning: frida-tools install failed — skipping" >&2
    [ -d "$HOME/.local/share/pipx/venvs/objection" ]   || pipx install objection   || echo "Warning: objection install failed — skipping" >&2
'
# kerbrute ships a linux binary for amd64 only (no arm64 as of v1.0.3 — the
# aarch64 asset 404s), so install on x86_64 and skip elsewhere quietly: it's an
# upstream gap, not an install failure, so no warning on arm64.
if ! command -v kerbrute >/dev/null 2>&1 && [ "$(uname -m)" = x86_64 ]; then
    curl -fsSL "https://github.com/ropnop/kerbrute/releases/latest/download/kerbrute_linux_amd64" \
        -o /usr/local/bin/kerbrute && chmod 0755 /usr/local/bin/kerbrute \
        || echo "Warning: kerbrute download failed — skipping" >&2
fi

apt-get clean
rm -rf /var/lib/apt/lists/*
