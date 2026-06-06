#!/usr/bin/env bash
# 03-network.sh: Network configuration for a pentesting VM.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
# shellcheck source=/dev/null
. /vagrant/provision/_lib.sh

# --- IP forwarding (required for pivoting/routing) ------------------------
# Use a dedicated /etc/sysctl.d drop-in: /etc/sysctl.conf does not exist on a
# clean Debian/Ubuntu base (Debian 13 moved defaults to linux-sysctl-defaults),
# and a 99- drop-in is re-applied by systemd-sysctl on every boot and outranks
# the distro defaults. Idempotent (overwrites the drop-in each run).
cat > /etc/sysctl.d/99-pt-ai.conf <<'EOF'
net.ipv4.ip_forward=1
net.ipv6.conf.all.forwarding=1
EOF
sysctl --system >/dev/null 2>&1 || sysctl -p /etc/sysctl.d/99-pt-ai.conf

# --- iptables: open policy (pentesting needs full flexibility) ------------
# Guarded so an out-of-scope box without iptables degrades instead of crashing.
if command -v iptables >/dev/null 2>&1; then
    iptables  -P INPUT   ACCEPT
    iptables  -P FORWARD ACCEPT
    iptables  -P OUTPUT  ACCEPT
    iptables  -F
    ip6tables -P INPUT   ACCEPT
    ip6tables -P FORWARD ACCEPT
    ip6tables -P OUTPUT  ACCEPT
    ip6tables -F
fi

# --- VPN + proxy tools (apt-family only) ----------------------------------
if $IS_APT; then
    apt-get update -y
    apt-get install -y --no-install-recommends \
        openvpn \
        wireguard-tools \
        proxychains-ng \
        iptables-persistent

    # Persist the open policy so it survives reboots
    iptables-save  > /etc/iptables/rules.v4
    ip6tables-save > /etc/iptables/rules.v6

    apt-get clean
    rm -rf /var/lib/apt/lists/*
else
    echo "[03-network] non-apt distro — skipping VPN/proxy tool install" >&2
fi
