#!/usr/bin/env bash
# 06-cloud.sh: Cloud audit tooling — AWS CLI v2, prowler, scoutsuite, trufflehog.
# These four sit outside the Kali apt set: AWS CLI v2 ships only as an official
# bundle; trufflehog is a Go binary distributed via release script; prowler and
# scoutsuite are PEP 668–protected Python CLIs best installed via pipx.
# pacu and kube-hunter (apt) live in config/tools.txt alongside the rest.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
# shellcheck source=/dev/null
. /vagrant/provision/_lib.sh

if ! $IS_APT; then
    echo "[06-cloud] non-apt distro — skipping cloud tooling (needs apt pipx/unzip)" >&2
    exit 0
fi

apt-get update -y
# python3-dev + build-essential let pipx build C-extension deps (e.g. kube-hunter
# -> netifaces needs Python.h + a compiler). Kali ships these implicitly; a clean
# Debian/Ubuntu base does not, so install them here for portability across boxes.
apt-get install -y --no-install-recommends pipx unzip python3-dev build-essential

# --- AWS CLI v2 -----------------------------------------------------------
# Arch-aware; official bundle to /usr/local/aws-cli with `aws` symlinked into
# /usr/local/bin.  --update is safe whether or not it's already installed but
# we still gate on "is v2 present" so we don't re-download ~50 MB every run.
if ! aws --version 2>/dev/null | grep -q "aws-cli/2"; then
    arch=$(uname -m)
    case "$arch" in
        x86_64)  awszip="awscli-exe-linux-x86_64.zip" ;;
        aarch64) awszip="awscli-exe-linux-aarch64.zip" ;;
        *) echo "AWS CLI v2: unsupported arch $arch" >&2; exit 1 ;;
    esac
    tmp=$(mktemp -d)
    curl -fsSL "https://awscli.amazonaws.com/${awszip}" -o "$tmp/awscliv2.zip"
    unzip -q "$tmp/awscliv2.zip" -d "$tmp"
    "$tmp/aws/install" --update
    rm -rf "$tmp"
fi

# --- trufflehog -----------------------------------------------------------
# Official install script; binary lands in /usr/local/bin (system-wide).
if ! command -v trufflehog >/dev/null 2>&1; then
    curl -sSfL https://raw.githubusercontent.com/trufflesecurity/trufflehog/main/scripts/install.sh \
        | sh -s -- -b /usr/local/bin
fi

# --- prowler + scoutsuite (pipx, per-user) --------------------------------
# pipx isolates each CLI in its own venv under ~/.local/share/pipx/, sidesteps
# PEP 668 ("externally-managed-environment"), and lets the vagrant user update
# them without root.  PATH for ~/.local/bin is set in /etc/profile.d/pt-ai.sh
# (see 02-claude.sh).
sudo -u vagrant bash -c '
    set -e
    pipx ensurepath >/dev/null
    [ -d "$HOME/.local/share/pipx/venvs/prowler" ]      || pipx install prowler
    [ -d "$HOME/.local/share/pipx/venvs/scoutsuite" ]   || pipx install scoutsuite
    # kube-hunter is archived upstream (2021) and its netifaces dep is the most
    # fragile to build — keep it best-effort so it can never block provisioning.
    [ -d "$HOME/.local/share/pipx/venvs/kube-hunter" ]  || pipx install kube-hunter \
        || echo "Warning: kube-hunter install failed — skipping" >&2
'

apt-get clean
rm -rf /var/lib/apt/lists/*
