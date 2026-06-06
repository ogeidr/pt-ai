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

apt-get clean
rm -rf /var/lib/apt/lists/*
