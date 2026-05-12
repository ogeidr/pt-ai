#!/usr/bin/env bash
# 03-network.sh: Network configuration for a pentesting VM.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

# --- IP forwarding (required for pivoting/routing) ------------------------
grep -q "^net.ipv4.ip_forward" /etc/sysctl.conf \
    && sed -i 's/^.*net.ipv4.ip_forward.*/net.ipv4.ip_forward=1/' /etc/sysctl.conf \
    || echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf

grep -q "^net.ipv6.conf.all.forwarding" /etc/sysctl.conf \
    && sed -i 's/^.*net.ipv6.conf.all.forwarding.*/net.ipv6.conf.all.forwarding=1/' /etc/sysctl.conf \
    || echo "net.ipv6.conf.all.forwarding=1" >> /etc/sysctl.conf

sysctl -p

# --- iptables: open policy (pentesting needs full flexibility) ------------
iptables  -P INPUT   ACCEPT
iptables  -P FORWARD ACCEPT
iptables  -P OUTPUT  ACCEPT
iptables  -F
ip6tables -P INPUT   ACCEPT
ip6tables -P FORWARD ACCEPT
ip6tables -P OUTPUT  ACCEPT
ip6tables -F

# --- VPN + proxy tools ----------------------------------------------------
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
