#!/usr/bin/env bash
# 00-update.sh: Bootstrap apt, upgrade, install base dependencies.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

# --- Kali rolling sources (idempotent) ------------------------------------
if ! grep -rq "kali-rolling" /etc/apt/sources.list /etc/apt/sources.list.d/ 2>/dev/null; then
    echo "deb http://http.kali.org/kali kali-rolling main contrib non-free non-free-firmware" \
        > /etc/apt/sources.list.d/kali-rolling.list
fi

# The VMware NAT DNS (assigned via DHCP) is unreliable — override with public DNS.
# Write to resolv.conf directly for immediate effect; resolv.conf.head persists
# the override across DHCP renewals (prepended by dhcpcd/resolvconf).
printf 'nameserver 8.8.8.8\nnameserver 8.8.4.4\n' > /etc/resolv.conf
printf 'nameserver 8.8.8.8\nnameserver 8.8.4.4\n' > /etc/resolv.conf.head

apt-get update -y

# kali-archive-keyring is required before a full update on non-Kali base boxes
if ! dpkg -l kali-archive-keyring >/dev/null 2>&1; then
    apt-get install -y --no-install-recommends kali-archive-keyring || true
    apt-get update -y
fi

apt-get full-upgrade -y

# Base dependencies shared by all provisioners
apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    git \
    jq \
    python3 \
    python3-pip \
    python3-venv

# Node 20 via NodeSource — Kali's packaged node may be older
if ! node --version 2>/dev/null | grep -qE "^v2[0-9]"; then
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
    apt-get install -y nodejs
fi

# Allow ANTHROPIC_API_KEY to pass through SSH when using API key auth.
# OAuth users (Claude Pro) don't need this — it's a no-op if the key isn't sent.
if ! grep -q "AcceptEnv ANTHROPIC_API_KEY" /etc/ssh/sshd_config 2>/dev/null; then
    echo "AcceptEnv ANTHROPIC_API_KEY" >> /etc/ssh/sshd_config
    systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null || true
fi

apt-get clean
rm -rf /var/lib/apt/lists/*
