#!/usr/bin/env bash
# _lib.sh — guest capability detection, sourced by every numbered provisioner.
#
# Decouples the Kali toolset layer from the generic pt-ai framework layer
# (Claude Code, opencode, network, hardening, cloud) so any apt-family box can
# build the environment while the default Kali experience stays unchanged.
#
# Exposes two booleans:
#   IS_KALI  true only on a Kali guest (ID=kali in /etc/os-release). Gates the
#            Kali-specific steps: the kali-rolling repo + kali-archive-keyring
#            (00), kali-linux-default (01), Kali-origin unattended-upgrades (04).
#   IS_APT   true when apt-get exists. Apt-family boxes (Kali, Ubuntu, Debian,
#            Parrot, Mint, …) provision fully; non-apt boxes are out of scope —
#            each provisioner skips its package steps and warns instead of
#            crashing.
#
# Use as: `if $IS_KALI; then …` / `if $IS_APT; then …`.

IS_KALI=false
IS_APT=false

if [ -r /etc/os-release ]; then
    # Source in a subshell so os-release's vars (ID/NAME/VERSION/…) don't leak
    # into the provisioner, which runs under `set -u`.
    _ptai_id=$(. /etc/os-release 2>/dev/null && printf '%s' "${ID:-}")
    [ "$_ptai_id" = "kali" ] && IS_KALI=true
    unset _ptai_id
fi

command -v apt-get >/dev/null 2>&1 && IS_APT=true

export IS_KALI IS_APT
