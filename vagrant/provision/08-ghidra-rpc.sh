#!/usr/bin/env bash
# 08-ghidra-rpc.sh: ghidra-rpc — a persistent, agent-driven RPC daemon over
# Ghidra (cellebrite-labs/ghidra-rpc), embedding Ghidra in-process via PyGhidra.
#
# This runs ALONGSIDE 07-ghidrasql.sh (it does NOT replace it) so the two tools
# can be A/B tested against the same /engagements binary:
#   - ghidrasql  : read-only SQL/HTTP surface over the Ghidra program DB.
#   - ghidra-rpc : agent-native verb CLI (decompile / xrefs-to / rename-function
#                  / set-comment / patch …) returning JSON, backed by a warm
#                  PyGhidra daemon that keeps the analysis session in memory.
#
# Shared state: both tools use the SAME Ghidra install (/opt/ghidra_<ver>_PUBLIC)
# and, on aarch64, the SAME self-built native decompiler. Whichever provisioner
# runs first performs the download/build; this one reuses it via the same
# idempotent presence checks (so enabling both does not double the work, and
# enabling only this one is fully self-contained).
#
# Provisioning here is pure Python: PyGhidra + `uv tool install`. No C++/CMake
# build, no Gradle extension, no libxsql/upstream source patches.
#
# What does NOT go away: the aarch64 native decompiler. The official Ghidra
# release ships no `os/linux_arm_64/decompile`, so on Apple Silicon we build it
# from the decompiler source bundled in the release (step 4) — a Ghidra-
# distribution problem shared by any tool that decompiles on ARM.
#
# Idempotent: every expensive step is gated on a presence check so `./pt-ai
# provision` re-runs are cheap.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
# shellcheck source=/dev/null
. /vagrant/provision/_lib.sh

# Independent opt-out (the Vagrantfile already drops this step when the var is
# set; this guard also covers a direct `./pt-ai provision` re-run with it
# exported). ghidrasql has its own separate PTAI_SKIP_GHIDRASQL.
if [ -n "${PTAI_SKIP_GHIDRA_RPC:-}" ]; then
    echo "[08-ghidra-rpc] PTAI_SKIP_GHIDRA_RPC set — skipping" >&2
    exit 0
fi
if ! $IS_APT; then
    echo "[08-ghidra-rpc] non-apt distro — skipping (needs apt build deps)" >&2
    exit 0
fi

# --- Pinned, overridable versions ----------------------------------------
# ghidra-rpc supports Ghidra 11+. Kept identical to 07-ghidrasql.sh's pin so the
# two tools share one install. PyGhidra is not affected by the libghidra-specific
# 12.1 regression that forced the original pin. Override via the VM environment:
# GHIDRA_VERSION / GHIDRA_RELEASE_TAG / GHIDRA_ZIP must agree with each other.
GHIDRA_VERSION="${GHIDRA_VERSION:-12.0.4}"
GHIDRA_RELEASE_TAG="${GHIDRA_RELEASE_TAG:-Ghidra_12.0.4_build}"
GHIDRA_ZIP="${GHIDRA_ZIP:-ghidra_12.0.4_PUBLIC_20260303.zip}"
# SHA-256 of GHIDRA_ZIP from the NSA release page — keep in sync with 07-ghidrasql.sh.
GHIDRA_SHA256="${GHIDRA_SHA256:-c3b458661d69e26e203d739c0c82d143cc8a4a29d9e571f099c2cf4bda62a120}"
GHIDRA_URL="https://github.com/NationalSecurityAgency/ghidra/releases/download/${GHIDRA_RELEASE_TAG}/${GHIDRA_ZIP}"
GHIDRA_INSTALL_DIR="/opt/ghidra_${GHIDRA_VERSION}_PUBLIC"

GHIDRA_RPC_REPO="${GHIDRA_RPC_REPO:-https://github.com/cellebrite-labs/ghidra-rpc.git}"
GHIDRA_RPC_REF="${GHIDRA_RPC_REF:-main}"   # pin to a tag/commit for reproducible builds

SRC_DIR="/opt/pt-ai/src"                    # build workspace, persisted in the VM
PROFILE_D="/etc/profile.d/pt-ai-ghidra-rpc.sh"
VAGRANT_USER="vagrant"
VAGRANT_HOME="/home/${VAGRANT_USER}"
UV_BIN="/usr/local/bin/uv"

ARCH="$(uname -m)"

log() { printf '\n[08-ghidra-rpc] %s\n' "$*"; }

# Retry a flaky, network-bound command a few times before giving up.
#   retry <attempts> <delay_seconds> [--] cmd...
retry() {
    local attempts="$1" delay="$2"; shift 2
    [ "${1:-}" = "--" ] && shift
    local n=1
    until "$@"; do
        if [ "$n" -ge "$attempts" ]; then
            echo "[08-ghidra-rpc] failed after $attempts attempts: $*" >&2
            return 1
        fi
        echo "[08-ghidra-rpc] attempt $n/$attempts failed; retrying in ${delay}s…" >&2
        sleep "$delay"; n=$((n + 1))
    done
}

# --- 1. Build/runtime dependencies ---------------------------------------
# openjdk-21 satisfies Ghidra's Java 17+ requirement. python3/python3-dev cover
# jpype1 if it has to build from source on this arch (manylinux wheels usually
# spare us). bison/flex/build-essential are needed ONLY for the aarch64 native
# decompiler build (step 4) — cheap and harmless elsewhere, and a no-op if
# 07-ghidrasql.sh already built it.
log "Installing dependencies"
apt-get update -y
apt-get install -y --no-install-recommends \
    openjdk-21-jdk python3 python3-dev git unzip curl ca-certificates \
    bison flex build-essential

# JAVA_HOME, resolved from the actual javac the JDK installed (arch-agnostic).
JAVA_HOME="$(dirname "$(dirname "$(readlink -f "$(command -v javac)")")")"
export JAVA_HOME
log "JAVA_HOME=$JAVA_HOME ($(java -version 2>&1 | head -1))"

# --- 2. uv (standalone; installs ghidra-rpc and can manage Python 3.11+) --
# Install uv system-wide to /usr/local/bin so it's on PATH for everyone. The
# installer's UV_INSTALL_DIR controls the target; UV_NO_MODIFY_PATH stops it
# editing shell profiles (we manage PATH ourselves in step 6).
if [ ! -x "$UV_BIN" ]; then
    log "Installing uv"
    retry 3 10 -- bash -c \
        'curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR=/usr/local/bin UV_NO_MODIFY_PATH=1 sh'
fi
test -x "$UV_BIN" || { echo "FATAL: uv not installed at $UV_BIN" >&2; exit 1; }
log "uv: $($UV_BIN --version 2>&1)"

# --- 3. Ghidra distribution (shared with 07-ghidrasql.sh) ----------------
if [ ! -x "$GHIDRA_INSTALL_DIR/support/analyzeHeadless" ]; then
    log "Downloading Ghidra ${GHIDRA_VERSION}"
    tmp="$(mktemp -d)"
    curl -fL --retry 3 --retry-delay 5 --retry-connrefused "$GHIDRA_URL" -o "$tmp/ghidra.zip"
    if ! echo "${GHIDRA_SHA256}  ${tmp}/ghidra.zip" | sha256sum -c - ; then
        log "FATAL: Ghidra checksum mismatch — refusing to install"; rm -rf "$tmp"; exit 1
    fi
    unzip -q "$tmp/ghidra.zip" -d /opt
    # The zip extracts to /opt/ghidra_<ver>_PUBLIC; normalize if the inner dir
    # name differs from our expected path (build-date suffixes, etc.).
    if [ ! -d "$GHIDRA_INSTALL_DIR" ]; then
        extracted="$(find /opt -maxdepth 1 -type d -name 'ghidra_*_PUBLIC' | sort | tail -1)"
        [ -n "$extracted" ] && mv "$extracted" "$GHIDRA_INSTALL_DIR"
    fi
    rm -rf "$tmp"
else
    log "Ghidra already present at $GHIDRA_INSTALL_DIR — reusing"
fi
test -x "$GHIDRA_INSTALL_DIR/support/analyzeHeadless" || {
    echo "FATAL: Ghidra not present at $GHIDRA_INSTALL_DIR" >&2; exit 1; }

# --- 4. Native decompiler for aarch64 (shared, idempotent) ---------------
# Identical to the ghidrasql provisioner — a Ghidra-distribution gap, not tool-
# specific. The release ships os/{linux_x86_64,mac_*,win_*}/decompile but NOT
# linux_arm_64, and bundles NO `support/buildNatives` (that lives in the source
# repo). The only in-distribution path is the decompiler's own Makefile under
# src/decompile/cpp. If 07-ghidrasql.sh already built it, this is a no-op.
#
# Two aarch64 gotchas in that Makefile (it predates ARM support — has a literal
# "TODO support arm64" comment):
#   * ARCH_TYPE falls to `-m32` for any non-x86_64 arch  -> override ARCH_TYPE=
#   * OSDIR is left empty, so `install_ghidraopt` copies to a broken path
#     -> build the `ghidra_opt` target and copy the binary ourselves.
# The runtime `decompile` binary IS the optimized `ghidra_opt` executable.
DECOMP_DIR="$GHIDRA_INSTALL_DIR/Ghidra/Features/Decompiler"
ARM_NATIVE="$DECOMP_DIR/os/linux_arm_64/decompile"

if [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then
    if [ -x "$ARM_NATIVE" ]; then
        log "aarch64 native decompiler already present — skipping build"
    else
        log "aarch64 detected and no linux_arm_64 decompiler — building from source"
        CPP_DIR="$DECOMP_DIR/src/decompile/cpp"
        # ARCH_TYPE= blanks the bogus -m32; native g++ builds a 64-bit aarch64 binary.
        make -C "$CPP_DIR" -j"$(nproc)" ARCH_TYPE= ghidra_opt
        mkdir -p "$DECOMP_DIR/os/linux_arm_64"
        cp -f "$CPP_DIR/ghidra_opt" "$ARM_NATIVE"
        chmod +x "$ARM_NATIVE"
        if [ -x "$ARM_NATIVE" ]; then
            log "aarch64 decompiler built: $ARM_NATIVE"
        else
            echo "WARNING: could not produce linux_arm_64/decompile. ghidra-rpc will" >&2
            echo "         start, but decompiler-backed commands (decompile, …) will" >&2
            echo "         fail. See provision/08-ghidra-rpc.sh notes." >&2
        fi
    fi
else
    log "x86_64 — native decompiler is prebuilt in the release, no build needed"
fi

# --- 5. Clone + install ghidra-rpc ---------------------------------------
# Built and installed as the vagrant user (the agent runs as vagrant, and the
# daemon must run under the same user that owns the engagement projects).
mkdir -p "$SRC_DIR"
chown "$VAGRANT_USER:$VAGRANT_USER" "$SRC_DIR"
RPC_SRC="$SRC_DIR/ghidra-rpc"
if [ -d "$RPC_SRC/.git" ]; then
    sudo -u "$VAGRANT_USER" git -C "$RPC_SRC" fetch -q --all || true
    sudo -u "$VAGRANT_USER" git -C "$RPC_SRC" checkout -q "$GHIDRA_RPC_REF" || true
    sudo -u "$VAGRANT_USER" git -C "$RPC_SRC" pull -q --ff-only || true
else
    retry 3 10 -- sudo -u "$VAGRANT_USER" git clone -- "$GHIDRA_RPC_REPO" "$RPC_SRC"
    sudo -u "$VAGRANT_USER" git -C "$RPC_SRC" checkout -q "$GHIDRA_RPC_REF" || true
fi

# `uv tool install --reinstall` is idempotent and picks up any new source. uv
# provisions a compatible Python 3.11+ itself if the system one is too old, and
# resolves pyghidra/click/jpype1 automatically. Entry points land in the vagrant
# user's ~/.local/bin.
log "Installing ghidra-rpc with uv (this resolves pyghidra/jpype1)"
retry 3 20 -- sudo -u "$VAGRANT_USER" env \
    "GHIDRA_INSTALL_DIR=$GHIDRA_INSTALL_DIR" \
    "PATH=/usr/local/bin:/usr/bin:/bin" \
    bash -lc "uv tool install --reinstall '$RPC_SRC'"

# Surface the two entry points on the system PATH so the in-VM agent (and the
# host `./pt-ai ghidra` wrapper) reach them without depending on ~/.local/bin.
for ep in ghidra-rpc ghidra-rpcd; do
    if [ -x "$VAGRANT_HOME/.local/bin/$ep" ]; then
        ln -sf "$VAGRANT_HOME/.local/bin/$ep" "/usr/local/bin/$ep"
    fi
done
test -x /usr/local/bin/ghidra-rpc || {
    echo "FATAL: ghidra-rpc entry point not installed" >&2; exit 1; }

# --- 6. Environment glue --------------------------------------------------
# ghidra-rpc's daemon refuses to start without GHIDRA_INSTALL_DIR. Export it
# (and JAVA_HOME) and make sure the uv tool bin is on PATH for login shells.
# A separate profile.d file from ghidrasql's; both export the same values
# (harmless). GHIDRA_RPC_PROJECT is intentionally NOT set here — it is per-
# engagement, supplied by `./pt-ai ghidra start --project …` (or by the agent).
cat > "$PROFILE_D" <<EOF
# pt-ai: ghidra-rpc / Ghidra environment
export GHIDRA_INSTALL_DIR="$GHIDRA_INSTALL_DIR"
export JAVA_HOME="$JAVA_HOME"
case ":\$PATH:" in
    *":\$HOME/.local/bin:"*) ;;
    *) export PATH="\$HOME/.local/bin:\$PATH" ;;
esac
EOF
chmod 644 "$PROFILE_D"

apt-get clean
rm -rf /var/lib/apt/lists/*
log "ghidra-rpc ready: $(/usr/local/bin/ghidra-rpc --version 2>&1 | head -1 || echo '(installed; run --version inside the VM)')"
