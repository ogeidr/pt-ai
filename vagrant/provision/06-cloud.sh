#!/usr/bin/env bash
# 06-cloud.sh: Cloud audit tooling that sits OUTSIDE the apt toolset.
#   AWS CLI v2          — official bundle (arch-aware zip)
#   trufflehog          — Go binary via upstream release script
#   gitleaks, kubeaudit — Go binaries via GitHub release (arch-matched tarball)
#   gcloud              — Google's own apt repo (no distro package on Kali/Debian)
#   prowler, scoutsuite — PEP 668–protected Python CLIs, installed via pipx
# Anything cloud/k8s that IS apt-packaged (pacu, kubectl, trivy, azure-cli,
# kube-hunter) lives in config/tools.txt alongside the rest.
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
apt-get install -y --no-install-recommends pipx unzip python3-dev build-essential gnupg

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

# --- gitleaks + kubeaudit (Go binaries via GitHub release) ----------------
# No upstream one-liner installer, so resolve the latest tag and pull the
# arch-matched tarball into /usr/local/bin. Best-effort: a download/API hiccup
# warns but never blocks provisioning.  Note the differing arch tokens.
case "$(uname -m)" in x86_64) gl_arch=x64; ka_arch=amd64 ;; aarch64) gl_arch=arm64; ka_arch=arm64 ;; *) gl_arch=""; ka_arch="" ;; esac

install_gh_binary() { # repo  asset_template  binary_name  (template uses $ver/$arch)
    local repo="$1" tmpl="$2" bin="$3" arch="$4" ver tmp url
    command -v "$bin" >/dev/null 2>&1 && return 0
    [ -n "$arch" ] || { echo "Warning: $bin — unsupported arch, skipping" >&2; return 0; }
    ver=$(curl -fsSL "https://api.github.com/repos/$repo/releases/latest" | jq -r .tag_name | sed 's/^v//')
    [ -n "$ver" ] && [ "$ver" != null ] || { echo "Warning: $bin — could not resolve version, skipping" >&2; return 0; }
    url=$(printf '%s' "$tmpl" | sed "s/{ver}/$ver/g; s/{arch}/$arch/g")
    tmp=$(mktemp -d)
    if curl -fsSL "$url" -o "$tmp/a.tgz" && tar -xzf "$tmp/a.tgz" -C "$tmp" "$bin" 2>/dev/null; then
        install -m 0755 "$tmp/$bin" "/usr/local/bin/$bin"
    else
        echo "Warning: $bin download/extract failed — skipping" >&2
    fi
    rm -rf "$tmp"
}
install_gh_binary "gitleaks/gitleaks" "https://github.com/gitleaks/gitleaks/releases/download/v{ver}/gitleaks_{ver}_linux_{arch}.tar.gz" gitleaks "$gl_arch"
install_gh_binary "Shopify/kubeaudit" "https://github.com/Shopify/kubeaudit/releases/download/v{ver}/kubeaudit_{ver}_linux_{arch}.tar.gz" kubeaudit "$ka_arch"

# --- gcloud (Google Cloud CLI, vendor apt repo) ---------------------------
# az ships in Kali apt (config/tools.txt); gcloud has no distro package, so add
# Google's apt repo — works on both Kali and Debian and stays apt-updatable.
if ! command -v gcloud >/dev/null 2>&1; then
    install -d -m 0755 /usr/share/keyrings
    if curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg; then
        echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" \
            > /etc/apt/sources.list.d/google-cloud-sdk.list
        apt-get update -y
        apt-get install -y google-cloud-cli || echo "Warning: google-cloud-cli install failed — skipping" >&2
    else
        echo "Warning: gcloud apt key fetch failed — skipping" >&2
    fi
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
