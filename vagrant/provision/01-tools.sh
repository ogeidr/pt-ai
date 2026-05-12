#!/usr/bin/env bash
# 01-tools.sh: Install Kali toolset.
# Arg $1: path to tools.txt (default: /vagrant/config/tools.txt)
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

TOOLS_FILE="${1:-/vagrant/config/tools.txt}"

apt-get update -y

# Core Kali metapackage — broad coverage without pulling everything
apt-get install -y kali-linux-default || \
    echo "Warning: kali-linux-default partially failed — continuing" >&2

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
