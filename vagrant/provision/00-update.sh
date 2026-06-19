#!/usr/bin/env bash
# 00-update.sh: Bootstrap apt, upgrade, install base dependencies.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
# shellcheck source=/dev/null
. /vagrant/provision/_lib.sh

# --- Kali rolling sources (Kali guests only; idempotent) ------------------
# Force-adding kali-rolling to a non-Kali apt box injects the wrong archive,
# so this is gated on IS_KALI.
if $IS_KALI && ! grep -rq "kali-rolling" /etc/apt/sources.list /etc/apt/sources.list.d/ 2>/dev/null; then
    echo "deb http://http.kali.org/kali kali-rolling main contrib non-free non-free-firmware" \
        > /etc/apt/sources.list.d/kali-rolling.list
fi

# The VMware NAT DNS (assigned via DHCP) is unreliable — override with public DNS.
# Write to resolv.conf directly for immediate effect; resolv.conf.head persists
# the override across DHCP renewals (prepended by dhcpcd/resolvconf).
printf 'nameserver 8.8.8.8\nnameserver 8.8.4.4\n' > /etc/resolv.conf
printf 'nameserver 8.8.8.8\nnameserver 8.8.4.4\n' > /etc/resolv.conf.head

if ! $IS_APT; then
    echo "[00-update] non-apt distro — skipping package bootstrap (out of scope)" >&2
    exit 0
fi

apt-get update -y

# kali-archive-keyring authenticates the kali-rolling source added above —
# only relevant on Kali (where it is normally already installed anyway).
if $IS_KALI && ! dpkg -l kali-archive-keyring >/dev/null 2>&1; then
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

# Node 20 via NodeSource (supports Kali/Debian/Ubuntu) — packaged node may be older.
# Add the repo manually (keyring + signed-by) instead of piping setup_20.x into
# root bash: apt-GPG then verifies every nodejs package. `nodistro` is the
# distro-agnostic suite, so this works on any apt-family box. Mirrors the gcloud
# keyring add in 06-cloud.sh.
if ! node --version 2>/dev/null | grep -qE "^v(2[0-9]|[3-9][0-9])"; then
    install -d -m 0755 /usr/share/keyrings
    curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
        | gpg --dearmor -o /usr/share/keyrings/nodesource.gpg
    echo "deb [signed-by=/usr/share/keyrings/nodesource.gpg] https://deb.nodesource.com/node_20.x nodistro main" \
        > /etc/apt/sources.list.d/nodesource.list
    apt-get update -y
    apt-get install -y nodejs
fi

# Ensure npm separately: Kali/Debian package npm apart from nodejs (and ship a
# node newer than NodeSource's 20.x, so the block above is skipped and never
# supplies npm). Without this, 02-claude.sh / 05-opencode.sh die on
# `npm: command not found`. On a NodeSource box npm is already bundled, so this
# is a no-op there.
if ! command -v npm >/dev/null 2>&1; then
    apt-get install -y npm
fi


apt-get clean
rm -rf /var/lib/apt/lists/*
