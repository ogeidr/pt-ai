#!/usr/bin/env bash
# 07-ghidrasql.sh: ghidrasql — a SQL/HTTP interface over Ghidra program databases
# (0xeb/ghidrasql + 0xeb/libghidra), driving Ghidra headless under the hood.
#
# Why this is its own provisioner and not a tools.txt line:
#   - ghidrasql is a C++ CMake build, libghidra is a Gradle Ghidra extension, and
#     Ghidra itself is a 1 GB+ JDK app — none of which live in the Kali apt set.
#   - On aarch64 (Apple Silicon Kali) the official Ghidra release ships NO native
#     decompiler (`os/linux_arm_64/decompile` is absent), so we build it from the
#     decompiler source bundled in the release. This is the hard part and the
#     reason ARM "doesn't work by default". On x86_64 the native is prebuilt and
#     the build step is skipped.
#
# Idempotent: every expensive step is gated on a presence check so `./pt-ai
# provision` re-runs are cheap.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
# shellcheck source=/dev/null
. /vagrant/provision/_lib.sh

# Opt-out for the heaviest, most distro-fragile provisioner. The Vagrantfile
# already drops this step when PTAI_SKIP_GHIDRASQL is set; this guard also
# covers a direct `./pt-ai provision` re-run with the flag exported.
if [ -n "${PTAI_SKIP_GHIDRASQL:-}" ]; then
    echo "[07-ghidrasql] PTAI_SKIP_GHIDRASQL set — skipping" >&2
    exit 0
fi
if ! $IS_APT; then
    echo "[07-ghidrasql] non-apt distro — skipping (needs apt build deps)" >&2
    exit 0
fi

# --- Pinned, overridable versions ----------------------------------------
# Pinned to 12.0.4 — a known-good version libghidra documents as supported.
# (No longer a hard requirement: the empty db_info / funcs=0 we once saw on 12.1
# was the range-sentinel bug — UINT64_MAX decoding to -1 on the JVM host — now
# fixed upstream in ghidrasql#7 + libghidra#16 and verified on 12.1.2. We keep
# 12.0.4 only because bumping requires a matching GHIDRA_SHA256 + retest, not
# because newer breaks.) Override via the VM environment if needed: GHIDRA_VERSION
# / GHIDRA_RELEASE_TAG / GHIDRA_ZIP must agree with each other.
GHIDRA_VERSION="${GHIDRA_VERSION:-12.0.4}"
GHIDRA_RELEASE_TAG="${GHIDRA_RELEASE_TAG:-Ghidra_12.0.4_build}"
GHIDRA_ZIP="${GHIDRA_ZIP:-ghidra_12.0.4_PUBLIC_20260303.zip}"
# SHA-256 of GHIDRA_ZIP from the NSA release page — bump together with the version.
GHIDRA_SHA256="${GHIDRA_SHA256:-c3b458661d69e26e203d739c0c82d143cc8a4a29d9e571f099c2cf4bda62a120}"
GHIDRA_URL="https://github.com/NationalSecurityAgency/ghidra/releases/download/${GHIDRA_RELEASE_TAG}/${GHIDRA_ZIP}"
GHIDRA_INSTALL_DIR="/opt/ghidra_${GHIDRA_VERSION}_PUBLIC"

GRADLE_VERSION="${GRADLE_VERSION:-8.10}"   # Kali apt gradle is too old for Ghidra (needs 8+)
GRADLE_HOME="/opt/gradle-${GRADLE_VERSION}"
GRADLE_URL="https://services.gradle.org/distributions/gradle-${GRADLE_VERSION}-bin.zip"
# SHA-256 from services.gradle.org/distributions/gradle-${GRADLE_VERSION}-bin.zip.sha256
GRADLE_SHA256="${GRADLE_SHA256:-5b9c5eb3f9fc2c94abaea57d90bd78747ca117ddbbf96c859d3741181a12bf2a}"

LIBGHIDRA_REPO="${LIBGHIDRA_REPO:-https://github.com/0xeb/libghidra.git}"
GHIDRASQL_REPO="${GHIDRASQL_REPO:-https://github.com/0xeb/ghidrasql.git}"

SRC_DIR="/opt/pt-ai/src"                    # build workspace, persisted in the VM
BIN_DST="/usr/local/bin/ghidrasql"
PROFILE_D="/etc/profile.d/pt-ai-ghidrasql.sh"
VAGRANT_USER="vagrant"

ARCH="$(uname -m)"

log() { printf '\n[07-ghidrasql] %s\n' "$*"; }

# Retry a flaky, network-bound command a few times before giving up. Gradle and
# CMake keep their caches between attempts, so a re-run resumes where the network
# dropped (transient connection-refused/timeouts to gradle/maven/github).
#   retry <attempts> <delay_seconds> [--] cmd...
retry() {
    local attempts="$1" delay="$2"; shift 2
    [ "${1:-}" = "--" ] && shift
    local n=1
    until "$@"; do
        if [ "$n" -ge "$attempts" ]; then
            echo "[07-ghidrasql] failed after $attempts attempts: $*" >&2
            return 1
        fi
        echo "[07-ghidrasql] attempt $n/$attempts failed; retrying in ${delay}s…" >&2
        sleep "$delay"; n=$((n + 1))
    done
}

# --- 1. Build/runtime dependencies ---------------------------------------
log "Installing build dependencies"
apt-get update -y
# bison/flex/make/g++ are needed only for the aarch64 native decompiler build,
# but they are cheap and harmless on x86_64 too.
apt-get install -y --no-install-recommends \
    openjdk-21-jdk cmake build-essential git unzip curl ca-certificates \
    bison flex make protobuf-compiler libprotobuf-dev

# JAVA_HOME, resolved from the actual javac the JDK installed (arch-agnostic).
JAVA_HOME="$(dirname "$(dirname "$(readlink -f "$(command -v javac)")")")"
export JAVA_HOME
log "JAVA_HOME=$JAVA_HOME ($(java -version 2>&1 | head -1))"

# --- 2. Gradle 8+ (manual; apt's is too old for Ghidra) ------------------
if [ ! -x "$GRADLE_HOME/bin/gradle" ]; then
    log "Installing Gradle ${GRADLE_VERSION}"
    tmp="$(mktemp -d)"
    curl -fsSL --retry 3 --retry-delay 5 --retry-connrefused "$GRADLE_URL" -o "$tmp/gradle.zip"
    if ! echo "${GRADLE_SHA256}  ${tmp}/gradle.zip" | sha256sum -c - ; then
        log "FATAL: Gradle checksum mismatch — refusing to install"; rm -rf "$tmp"; exit 1
    fi
    unzip -q "$tmp/gradle.zip" -d /opt
    rm -rf "$tmp"
fi
ln -sf "$GRADLE_HOME/bin/gradle" /usr/local/bin/gradle
log "gradle: $(/usr/local/bin/gradle --version | awk '/^Gradle/{print $2}')"

# --- 3. Ghidra distribution ----------------------------------------------
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
fi
test -x "$GHIDRA_INSTALL_DIR/support/analyzeHeadless" || {
    echo "FATAL: Ghidra not present at $GHIDRA_INSTALL_DIR" >&2; exit 1; }

# Hand the whole tree to the vagrant user up front: the extension install (step
# 6) runs as vagrant and writes Ghidra/Extensions/ back into this directory.
chown -R "$VAGRANT_USER:$VAGRANT_USER" "$GHIDRA_INSTALL_DIR"

# --- 4. Native decompiler for aarch64 ------------------------------------
# The release ships os/{linux_x86_64,mac_*,win_*}/decompile but NOT linux_arm_64,
# and bundles NO `support/buildNatives` (that lives in the source repo). The only
# in-distribution path is the decompiler's own Makefile under src/decompile/cpp.
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
            echo "WARNING: could not produce linux_arm_64/decompile. ghidrasql will" >&2
            echo "         run, but decompiler-backed tables (pseudocode, decomp_*)" >&2
            echo "         will fail. See provision/07-ghidrasql.sh notes." >&2
        fi
    fi
else
    log "x86_64 — native decompiler is prebuilt in the release, no build needed"
fi

# --- 5. Clone libghidra + ghidrasql --------------------------------------
mkdir -p "$SRC_DIR"
chown "$VAGRANT_USER:$VAGRANT_USER" "$SRC_DIR"
clone_or_pull() {  # $1 repo url, $2 dest dir
    # Pass args to git directly (no shell-string interpolation).
    if [ -d "$2/.git" ]; then
        # We patch the ghidrasql tree in place (step 5b), which leaves it dirty. A
        # dirty tree makes --ff-only fail and the `|| true` swallows it, pinning us
        # to the old commit forever. Reset to HEAD first so upstream fixes actually
        # land, then re-patch below. Untracked build/ artifacts are kept (no clean)
        # so incremental builds stay fast.
        sudo -u "$VAGRANT_USER" git -C "$2" reset --hard -q HEAD
        sudo -u "$VAGRANT_USER" git -C "$2" pull --ff-only || true
    else
        retry 3 10 -- sudo -u "$VAGRANT_USER" git clone --depth 1 -- "$1" "$2"
    fi
}
clone_or_pull "$LIBGHIDRA_REPO" "$SRC_DIR/libghidra"
clone_or_pull "$GHIDRASQL_REPO" "$SRC_DIR/ghidrasql"

# libxsql is fetched by ghidrasql's own CMake FetchContent (step 7). Upstream now
# pins it to a release *tag* (ghidrasql#5), which a GIT_SHALLOW fetch resolves
# fine — so the full pre-clone workaround we used to carry (for an un-shallow-able
# bare commit) is no longer needed.

# --- 5b. Patch ghidrasql for GCC 15 --------------------------------------
# Kali's GCC 15 / libstdc++ 15 no longer transitively pulls in <algorithm>, so
# ghidrasql's use of std::find_if etc. fails to compile ("'find_if' is not a
# member of 'std'"). Inject the include into the files that use those algorithms
# (idempotent; a redundant include is harmless). Upstream bug; minimal local fix.
log "Patching ghidrasql sources for GCC 15 (<algorithm> include)"
while IFS= read -r f; do
    [ -n "$f" ] || continue
    grep -q '#include <algorithm>' "$f" || sed -i '1i #include <algorithm>' "$f"
done < <(grep -rlE 'std::(find_if|find|sort|stable_sort|transform|count|count_if|min_element|max_element|remove|remove_if|unique|any_of|all_of|none_of|for_each|lower_bound|upper_bound)' \
    "$SRC_DIR/ghidrasql/src" 2>/dev/null || true)

# NOTE: two patches we used to carry here are now upstream and have been removed:
#   - headless OpenProgram (issue #1): db_info is fixed differently upstream (#9
#     resolves the active program from the revision server-side; the headless path
#     deliberately keeps auto_open_program=false), so our client-side OpenProgram
#     would diverge from — and risk conflicting with — that design.
#   - range-sentinel UINT64_MAX->INT64_MAX (issue #2): merged verbatim in #7
#     (client) + libghidra#16 (host); our sed is now a no-op.
# Both land automatically via the git pull above; do not re-add them.

# --- 6. Build the libghidra Ghidra extension -----------------------------
# Prefer a bundled gradle wrapper if the repo ships one; else system gradle.
# Note: PATH is set unquoted so the inner shell expands its own $PATH (a quoted
# '...:$PATH' would become a literal and strip /usr/bin -> uname/xargs not found).
log "Building libghidra Ghidra extension"
# Retried: dependency resolution against maven central is the step most prone to
# transient connection-refused; gradle's cache persists so re-runs resume.
retry 3 30 -- sudo -u "$VAGRANT_USER" bash -c "
    set -e
    export JAVA_HOME='$JAVA_HOME'
    export PATH=$GRADLE_HOME/bin:\$PATH
    cd '$SRC_DIR/libghidra/ghidra-extension'
    GRADLE_CMD=gradle; [ -x ./gradlew ] && GRADLE_CMD=./gradlew
    \$GRADLE_CMD installExtension -PGHIDRA_INSTALL_DIR='$GHIDRA_INSTALL_DIR'
"
test -d "$GHIDRA_INSTALL_DIR/Ghidra/Extensions/LibGhidraHost" || {
    echo "FATAL: LibGhidraHost extension did not install" >&2; exit 1; }

# --- 7. Build ghidrasql (C++/CMake) --------------------------------------
# Incremental by default — recompiles only what the GCC-15 patch above changed
# (protobuf/abseil stay cached) and is near-instant when nothing changed. libxsql,
# cpp-httplib and protobuf are pinned *inside* ghidrasql's own CMakeLists via
# FetchContent and fetched into build/_deps.
BUILT_BIN="$SRC_DIR/ghidrasql/build/bin/ghidrasql"

# Dep-skew guard. The build/ tree is reused across provisions for speed, but the
# FetchContent pins live in the ghidrasql *source*. When `git pull` advances
# ghidrasql (e.g. #16: libxsql v1.0.8 -> v1.0.10), a reused build/_deps keeps the
# OLD libxsql while the updated headers expect the new one — e.g.
# "'xsql::ScriptStatementResult' is not a member of 'xsql'" (the symbol's
# transitive include only exists in libxsql v1.0.7+). A fresh FetchContent of the
# current pin compiles cleanly, so force a clean configure whenever the source rev
# changed — or on first build, when the stamp is absent — and keep the fast
# incremental path otherwise.
SRC_REV="$(sudo -u "$VAGRANT_USER" git -C "$SRC_DIR/ghidrasql" rev-parse HEAD 2>/dev/null || echo unknown)"
STAMP="$SRC_DIR/ghidrasql/build/.ptai-built-rev"
if [ ! -f "$STAMP" ] || [ "$(cat "$STAMP" 2>/dev/null)" != "$SRC_REV" ]; then
    log "ghidrasql source changed (or first build) — clearing build/ to re-pin FetchContent deps"
    rm -rf "$SRC_DIR/ghidrasql/build"
fi

log "Building ghidrasql"
# Retried: CMake FetchContent pulls libxsql/protobuf/abseil from the network;
# build is incremental so retries are cheap and only re-fetch what failed.
retry 3 20 -- sudo -u "$VAGRANT_USER" bash -c "
    set -e
    export JAVA_HOME='$JAVA_HOME'
    cd '$SRC_DIR/ghidrasql'
    cmake -B build -DGHIDRASQL_LIBGHIDRA_DIR=../libghidra/cpp \
          -DCMAKE_BUILD_TYPE=Release
    cmake --build build -j\$(nproc)
"
test -x "$BUILT_BIN" || { echo "FATAL: ghidrasql binary not built" >&2; exit 1; }
ln -sf "$BUILT_BIN" "$BIN_DST"
# Record the source rev this build/ tree was produced from, so the next provision
# only does a clean rebuild when ghidrasql actually advanced (see the guard above).
printf '%s\n' "$SRC_REV" | sudo -u "$VAGRANT_USER" tee "$STAMP" >/dev/null

# --- 8. Environment glue --------------------------------------------------
# Export GHIDRA_INSTALL_DIR so the common headless-launch path needs no --ghidra.
# CAVEAT (upstream-documented): this auto-fills --ghidra and conflicts with
# --url attach mode. For `ghidrasql --url ...`, run `env -u GHIDRA_INSTALL_DIR`.
cat > "$PROFILE_D" <<EOF
# pt-ai: ghidrasql / Ghidra environment
export GHIDRA_INSTALL_DIR="$GHIDRA_INSTALL_DIR"
export JAVA_HOME="$JAVA_HOME"
EOF
chmod 644 "$PROFILE_D"

apt-get clean
rm -rf /var/lib/apt/lists/*
log "ghidrasql ready: $($BIN_DST --help 2>&1 | head -1 || echo '(built; run --help inside the VM)')"
