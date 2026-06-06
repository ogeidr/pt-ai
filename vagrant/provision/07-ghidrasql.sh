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
# Pinned to 12.0.4 — the version libghidra documents as supported. On Ghidra 12.1
# the libghidra host opens the program but its Program-derived fields come back
# empty (db_info shows program_name=active-program, language_id/md5 blank, and
# funcs returns 0 rows) — a program open/activation behavior change in 12.1.
# Override via the VM environment if needed: GHIDRA_VERSION / GHIDRA_RELEASE_TAG /
# GHIDRA_ZIP must agree with each other.
GHIDRA_VERSION="${GHIDRA_VERSION:-12.0.4}"
GHIDRA_RELEASE_TAG="${GHIDRA_RELEASE_TAG:-Ghidra_12.0.4_build}"
GHIDRA_ZIP="${GHIDRA_ZIP:-ghidra_12.0.4_PUBLIC_20260303.zip}"
GHIDRA_URL="https://github.com/NationalSecurityAgency/ghidra/releases/download/${GHIDRA_RELEASE_TAG}/${GHIDRA_ZIP}"
GHIDRA_INSTALL_DIR="/opt/ghidra_${GHIDRA_VERSION}_PUBLIC"

GRADLE_VERSION="${GRADLE_VERSION:-8.10}"   # Kali apt gradle is too old for Ghidra (needs 8+)
GRADLE_HOME="/opt/gradle-${GRADLE_VERSION}"
GRADLE_URL="https://services.gradle.org/distributions/gradle-${GRADLE_VERSION}-bin.zip"

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
    log "Ghidra SHA-256: $(sha256sum "$tmp/ghidra.zip" | awk '{print $1}') (cross-check against the release page)"
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
        sudo -u "$VAGRANT_USER" git -C "$2" pull --ff-only || true
    else
        retry 3 10 -- sudo -u "$VAGRANT_USER" git clone --depth 1 -- "$1" "$2"
    fi
}
clone_or_pull "$LIBGHIDRA_REPO" "$SRC_DIR/libghidra"
clone_or_pull "$GHIDRASQL_REPO" "$SRC_DIR/ghidrasql"

# ghidrasql's CMakeLists pins libxsql at a bare commit with GIT_SHALLOW TRUE,
# which CMake FetchContent cannot check out (a shallow fetch only retrieves the
# branch tip, not an arbitrary commit -> "fatal: invalid reference"). Pre-clone
# libxsql FULL at exactly that commit and feed it to FetchContent via
# FETCHCONTENT_SOURCE_DIR_LIBXSQL (step 7), which bypasses the download/checkout.
# Read the pinned commit straight from ghidrasql's CMakeLists so we track upstream.
LIBXSQL_DIR="$SRC_DIR/libxsql"
LIBXSQL_COMMIT="$(awk '/FetchContent_Declare\(libxsql/{f=1} f&&/GIT_TAG/{print $2; exit}' \
    "$SRC_DIR/ghidrasql/CMakeLists.txt" 2>/dev/null)"
[ -n "$LIBXSQL_COMMIT" ] || LIBXSQL_COMMIT="ea11622"
log "Pre-fetching libxsql @ $LIBXSQL_COMMIT (full clone — shallow can't pin a bare commit)"
if [ ! -d "$LIBXSQL_DIR/.git" ]; then
    retry 3 10 -- sudo -u "$VAGRANT_USER" bash -c "git clone https://github.com/0xeb/libxsql.git '$LIBXSQL_DIR'"
fi
retry 3 10 -- sudo -u "$VAGRANT_USER" bash -c "cd '$LIBXSQL_DIR' && git fetch -q --all && git checkout -q '$LIBXSQL_COMMIT'"

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

# --- 5c. Patch ghidrasql headless mode to open the active program --------
# Upstream bug: in headless one-shot/server mode the CLI hardcodes
# `source_opts.auto_open_program = false` and never sets program_path, so the
# client never issues OpenProgram against the host it just launched. The host
# DOES bind the loaded program (HostState.currentProgram), but the client's
# query layer returns empty rows (funcs=0, db_info shows program_name
# "active-program", language_id/md5 blank). The --url connect path sets
# program_path + auto_open_program and works — we mirror that here, defaulting
# the active program to the imported binary's project path so the documented
# `--binary ... -q` form works (and an explicit --program/--initial-program
# still wins via selected_program_arg). Idempotent: the old line is gone after
# patching. See https://github.com/0xeb/ghidrasql (run_headless_live_*).
log "Patching ghidrasql headless mode to open the active program"
python3 - "$SRC_DIR/ghidrasql/src/cli/main.cpp" <<'PYEOF'
import sys
p = sys.argv[1]
s = open(p).read()
old = "    source_opts.auto_open_program = false;\n"
new = (
    "    std::string selected_program = selected_program_arg(args);\n"
    "    if (selected_program.empty() && !args.binary_paths.empty()) {\n"
    "        std::string base = args.binary_paths.front();\n"
    "        auto slash = base.find_last_of('/');\n"
    "        if (slash != std::string::npos) base = base.substr(slash + 1);\n"
    "        selected_program = \"/\" + base;\n"
    "    }\n"
    "    source_opts.auto_open_program = !selected_program.empty();\n"
    "    source_opts.program_path = selected_program;\n"
    "    source_opts.project_path = args.project;\n"
    "    source_opts.project_name = args.project_name;\n"
)
if old in s:
    s = s.replace(old, new)
    open(p, "w").write(s)
    print("  patched %d site(s)" % s.count("source_opts.auto_open_program = !selected_program.empty();"))
else:
    print("  already patched (or upstream changed) — skipping")
PYEOF

# --- 5d. Patch ghidrasql "all addresses" sentinel ------------------------
# The client passes kAllAddressesMax = UINT64_MAX as the range upper bound for
# every range-filtered table (funcs, names, instructions, strings, xrefs, ...).
# Over protobuf uint64 -> Java long that value is -1, so the host's
# `if (endOffset <= 0) endOffset = getMaxAddress().getOffset()` kicks in. For
# binaries with unresolved externals Ghidra puts an EXTERNAL block in a space
# that sorts AFTER ram with a tiny offset, so getMaxAddress().getOffset() is a
# few bytes and EVERY real function is filtered out (rows=0) while non-range
# tables like `segments` work. Using INT64_MAX keeps it a large *positive* long
# on the host, so the upper bound stays unbounded and nothing is filtered.
# One-line, client-side; fixes all range tables without rebuilding the extension.
log "Patching ghidrasql address-range sentinel (UINT64_MAX -> INT64_MAX)"
sed -i \
  's#kAllAddressesMax = std::numeric_limits<std::uint64_t>::max();#kAllAddressesMax = static_cast<std::uint64_t>(std::numeric_limits<std::int64_t>::max());#' \
  "$SRC_DIR/ghidrasql/src/lib/src/source_libghidra.cpp"

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
# FETCHCONTENT_SOURCE_DIR_LIBXSQL points CMake at our pre-cloned libxsql (its
# pinned commit can't be shallow-checked-out). Always (re)build — incremental, so
# it recompiles only what the patches above changed (protobuf/abseil stay cached)
# and is near-instant when nothing changed. This guarantees source patches apply.
BUILT_BIN="$SRC_DIR/ghidrasql/build/bin/ghidrasql"
log "Building ghidrasql"
# Retried: CMake FetchContent pulls protobuf/abseil from the network; build is
# incremental so retries are cheap and only re-fetch what failed.
retry 3 20 -- sudo -u "$VAGRANT_USER" bash -c "
    set -e
    export JAVA_HOME='$JAVA_HOME'
    cd '$SRC_DIR/ghidrasql'
    cmake -B build -DGHIDRASQL_LIBGHIDRA_DIR=../libghidra/cpp \
          -DFETCHCONTENT_SOURCE_DIR_LIBXSQL='$LIBXSQL_DIR' \
          -DCMAKE_BUILD_TYPE=Release
    cmake --build build -j\$(nproc)
"
test -x "$BUILT_BIN" || { echo "FATAL: ghidrasql binary not built" >&2; exit 1; }
ln -sf "$BUILT_BIN" "$BIN_DST"

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
