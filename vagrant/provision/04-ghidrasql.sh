#!/usr/bin/env bash
# 04-ghidrasql.sh: Install Ghidra + ghidrasql (binary analysis via SQL for AI agents).
# Ref: https://github.com/0xeb/ghidrasql/blob/main/install-prompt.md
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

GRADLE_VERSION="8.14"
GRADLE_DIR="/opt/gradle-${GRADLE_VERSION}"
BUILD_DIR="/opt/ghidrasql-build"
GHIDRA_LINK="/opt/ghidra"
GHIDRASQL_BIN="/usr/local/bin/ghidrasql"

# ---------------------------------------------------------------------------
# 1. System dependencies
# ---------------------------------------------------------------------------
apt-get update -y
apt-get install -y --no-install-recommends \
    openjdk-21-jdk \
    cmake \
    build-essential \
    unzip

# Gate: Java 21 — check the directory directly; provisioner PATH is unreliable
JAVA_HOME="/usr/lib/jvm/java-21-openjdk-$(dpkg --print-architecture)"
test -x "$JAVA_HOME/bin/java" \
    || { echo "ERROR: JDK 21 not found at $JAVA_HOME" >&2; exit 1; }
export JAVA_HOME
export PATH="$JAVA_HOME/bin:$PATH"

# Gate: CMake ≥ 3.20
cmake_minor=$(cmake --version | awk 'NR==1{split($3,a,".");print a[1]*100+a[2]}')
[ "$cmake_minor" -ge 320 ] \
    || { echo "ERROR: CMake $(cmake --version | head -1) is < 3.20" >&2; exit 1; }

# ---------------------------------------------------------------------------
# 2. Gradle 8 (apt version is typically too old)
# ---------------------------------------------------------------------------
if [ ! -x "$GRADLE_DIR/bin/gradle" ]; then
    curl -fsSL \
        "https://services.gradle.org/distributions/gradle-${GRADLE_VERSION}-bin.zip" \
        -o /tmp/gradle.zip
    unzip -q /tmp/gradle.zip -d /opt
    rm /tmp/gradle.zip
fi
export PATH="$GRADLE_DIR/bin:$PATH"
gradle --version | grep -qE "^Gradle 8" \
    || { echo "ERROR: Gradle 8 not available" >&2; exit 1; }

# ---------------------------------------------------------------------------
# 3. Ghidra — download latest 12.1+ release from GitHub
# ---------------------------------------------------------------------------
if [ ! -x "$GHIDRA_LINK/support/analyzeHeadless" ]; then
    RELEASE_JSON=$(curl -fsSL \
        -H "User-Agent: pt-ai-provisioner" \
        -H "Accept: application/vnd.github+json" \
        https://api.github.com/repos/NationalSecurityAgency/ghidra/releases/latest)

    # Asset name is ghidra_X.Y.Z_PUBLIC_YYYYMMDD.zip — contains "PUBLIC" and ends with .zip
    GHIDRA_URL=$(echo "$RELEASE_JSON" \
        | jq -r '.assets[]
                 | select(.name | (contains("PUBLIC") and endswith(".zip")))
                 | .browser_download_url' \
        | head -1)

    if [ -z "$GHIDRA_URL" ] || [ "$GHIDRA_URL" = "null" ]; then
        echo "ERROR: Could not parse Ghidra download URL. API response summary:" >&2
        echo "$RELEASE_JSON" \
            | jq '{message, tag_name, assets: [.assets[]?.name]}' 2>/dev/null \
            || echo "$RELEASE_JSON" | head -10 >&2
        exit 1
    fi

    GHIDRA_ZIP=$(basename "$GHIDRA_URL")

    echo "==> Downloading $GHIDRA_ZIP (~500 MB) ..."
    curl -fL "$GHIDRA_URL" -o "/tmp/$GHIDRA_ZIP"

    unzip -q "/tmp/$GHIDRA_ZIP" -d /opt
    rm "/tmp/$GHIDRA_ZIP"

    # Find the extracted directory (name includes the date so don't assume it)
    GHIDRA_EXTRACTED=$(find /opt -maxdepth 1 -type d -name 'ghidra_*PUBLIC*' | sort | tail -1)
    if [ -z "$GHIDRA_EXTRACTED" ]; then
        echo "ERROR: could not find extracted Ghidra directory under /opt" >&2
        exit 1
    fi
    ln -sfn "$GHIDRA_EXTRACTED" "$GHIDRA_LINK"
fi

export GHIDRA_INSTALL_DIR="$GHIDRA_LINK"

# Gate
test -x "$GHIDRA_INSTALL_DIR/support/analyzeHeadless" \
    || { echo "ERROR: Ghidra analyzeHeadless not found" >&2; exit 1; }
ls "$GHIDRA_INSTALL_DIR/Ghidra/Framework" >/dev/null \
    || { echo "ERROR: Ghidra/Framework missing" >&2; exit 1; }

# ---------------------------------------------------------------------------
# 4. Clone / update repos
# ---------------------------------------------------------------------------
mkdir -p "$BUILD_DIR"

for repo in libghidra ghidrasql; do
    if [ ! -d "$BUILD_DIR/$repo/.git" ]; then
        git clone "https://github.com/0xeb/${repo}.git" "$BUILD_DIR/$repo"
    else
        git -C "$BUILD_DIR/$repo" pull --ff-only
    fi
done

# ---------------------------------------------------------------------------
# 5. Build and install LibGhidraHost Ghidra extension
# ---------------------------------------------------------------------------
if [ ! -d "$GHIDRA_INSTALL_DIR/Ghidra/Extensions/LibGhidraHost" ]; then
    cd "$BUILD_DIR/libghidra/ghidra-extension"
    # Use repo wrapper if available, otherwise fall back to system gradle
    GRADLE_CMD="./gradlew"
    [ -x "$GRADLE_CMD" ] || GRADLE_CMD="gradle"
    $GRADLE_CMD installExtension -PGHIDRA_INSTALL_DIR="$GHIDRA_INSTALL_DIR"
    cd "$BUILD_DIR"

    # Gate
    test -d "$GHIDRA_INSTALL_DIR/Ghidra/Extensions/LibGhidraHost" \
        || { echo "ERROR: LibGhidraHost extension not installed" >&2; exit 1; }
fi

# ---------------------------------------------------------------------------
# 6. Build ghidrasql
# ---------------------------------------------------------------------------
if [ ! -x "$GHIDRASQL_BIN" ]; then
    # GCC 14 requires explicit <algorithm> for std::find_if; upstream missing it.
    SOURCE_CPP="$BUILD_DIR/ghidrasql/src/lib/src/source.cpp"
    if ! grep -q '#include <algorithm>' "$SOURCE_CPP"; then
        { printf '#include <algorithm>\n'; cat "$SOURCE_CPP"; } > "${SOURCE_CPP}.tmp"
        mv "${SOURCE_CPP}.tmp" "$SOURCE_CPP"
    fi

    cd "$BUILD_DIR/ghidrasql"
    cmake -B build \
        -DGHIDRASQL_LIBGHIDRA_DIR="$BUILD_DIR/libghidra/cpp" \
        -DCMAKE_BUILD_TYPE=Release
    cmake --build build -j"$(nproc)"

    # Gate
    test -x build/bin/ghidrasql \
        || { echo "ERROR: ghidrasql binary not produced" >&2; exit 1; }

    install -m 755 build/bin/ghidrasql "$GHIDRASQL_BIN"
    cd "$BUILD_DIR"
fi

# ---------------------------------------------------------------------------
# 7. Persist environment
# ---------------------------------------------------------------------------
cat > /etc/profile.d/ghidrasql.sh <<EOF
export GHIDRA_INSTALL_DIR=$GHIDRA_LINK
export PATH="$GRADLE_DIR/bin:\$PATH"
EOF
chmod 644 /etc/profile.d/ghidrasql.sh

apt-get clean
rm -rf /var/lib/apt/lists/*

echo "==> ghidrasql ready: $($GHIDRASQL_BIN --help 2>&1 | head -1)"
