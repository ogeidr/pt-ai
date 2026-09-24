#!/usr/bin/env bash
# 09-ripwire.sh: install ripwire — a local, offline source-navigation CLI for the
# whitebox / source-assisted workflow. It parses a source tree and prints a ranked
# symbol map, hit lists and single function bodies, so an agent can find its way
# around a client codebase without reading whole files.
#
# It is NOT a vulnerability scanner and nothing here should imply that it is: it
# ranks by architectural centrality (PageRank), which is a different quantity from
# attack surface. On DVWA the top-ranked symbols are vendored library internals,
# not the vulnerable endpoints. See features/ripwire-integration.md §0.3.
#
# Light next to 07/08: one prebuilt binary, no build, no Java. Opt out with
# PTAI_SKIP_RIPWIRE=1.
set -euo pipefail
. /vagrant/provision/_lib.sh

# Independent opt-out, mirroring 07/08. The Vagrantfile already drops this step
# when the var is set; this guard also covers a direct `./pt-ai provision` re-run
# with it exported.
if [ -n "${PTAI_SKIP_RIPWIRE:-}" ]; then
    echo "[09-ripwire] PTAI_SKIP_RIPWIRE set — skipping" >&2
    exit 0
fi

if ! $IS_APT; then
    echo "[09-ripwire] non-apt distro — skipping" >&2
    exit 0
fi

log() { printf '\n[09-ripwire] %s\n' "$*"; }

RIPWIRE_VERSION="${RIPWIRE_VERSION:-0.5.0}"
RIPWIRE_DIR="/opt/ripwire-${RIPWIRE_VERSION}"
BIN_DST="/usr/local/bin/ripwire"

# SHA-256 of each release tarball, taken from the .sha256 asset published beside it
# AND recomputed locally before pinning (features/ripwire-integration.md §8.2).
# Bump these together with RIPWIRE_VERSION — a stale pin must fail the install,
# never be skipped.
#
# The `${VAR:-default}` override is reachable ONLY when this script is run directly
# in the guest. A Vagrant shell provisioner does not inherit the host environment,
# so `RIPWIRE_SHA256_arm64=... ./pt-ai provision` on the host is silently INERT —
# it does not weaken the pin, and it does not test it either. (Contrast
# PTAI_SKIP_RIPWIRE, which the Vagrantfile reads in host-side Ruby and which does
# work that way. Same shape, opposite reachability.) The same is true of every
# other *_SHA256 in provision/. To exercise the gate, run the script in-guest:
#   ./pt-ai ssh -c 'sudo RIPWIRE_SHA256_arm64=<wrong> bash /vagrant/provision/09-ripwire.sh'
RIPWIRE_SHA256_arm64="${RIPWIRE_SHA256_arm64:-efe049b1645045e96751a51b1bc321b2d8653aa1f6ab5d7c2390eb3d49716bf0}"
RIPWIRE_SHA256_x64="${RIPWIRE_SHA256_x64:-f06e9d7e55032e8e5c397405ed72a19d6e70767d28c8c617a925de4401779f50}"

case "$(uname -m)" in
    x86_64)        rw_arch=x64;   rw_sha="$RIPWIRE_SHA256_x64" ;;
    aarch64|arm64) rw_arch=arm64; rw_sha="$RIPWIRE_SHA256_arm64" ;;
    *)
        # Upstream publishes x64 and arm64 only. Warn and leave the box usable
        # rather than failing the whole provision for an optional analysis tool —
        # the same call 01-tools.sh makes for kerbrute. The skill's availability
        # preamble degrades to a message when the binary is absent.
        echo "[09-ripwire] no upstream build for $(uname -m) — skipping" >&2
        exit 0 ;;
esac

# The ELF is dynamically linked against the normal C++ runtime — "zero
# dependencies" upstream means deps are vendored at BUILD time, not that this is a
# static binary. Verified NEEDED: libstdc++.so.6, libgcc_s.so.1, libm, libpthread,
# libc; max GLIBC_2.17 (arm64) / 2.26 (x64), GLIBCXX_3.4.22. libstdc++6 is present
# on a stock Kali/Debian, but "present in practice" is not a dependency
# declaration — ask for it explicitly so a slim base image fails here, loudly,
# instead of at first use.
if ! dpkg-query -W -f='${Status}' libstdc++6 2>/dev/null | grep -q 'install ok installed'; then
    log "installing libstdc++6 (runtime dependency)"
    apt-get install -y libstdc++6 || echo "[09-ripwire] Warning: could not install libstdc++6" >&2
fi

# Version check, not mere presence: a stale binary from an older pin must be
# replaced rather than silently kept (cf. 06-cloud.sh's aws-cli/2 guard).
if [ -x "$BIN_DST" ] && "$BIN_DST" --version 2>/dev/null | grep -q "ripwire ${RIPWIRE_VERSION}"; then
    log "ripwire ${RIPWIRE_VERSION} already installed — nothing to do"
    exit 0
fi

RIPWIRE_TGZ="ripwire-${RIPWIRE_VERSION}-linux-${rw_arch}.tar.gz"
RIPWIRE_URL="https://github.com/redhat-et/ripwire/releases/download/v${RIPWIRE_VERSION}/${RIPWIRE_TGZ}"

log "Downloading ripwire ${RIPWIRE_VERSION} (${rw_arch})"
tmp="$(mktemp -d)"
curl -fsSL --retry 3 --retry-delay 5 --retry-connrefused "$RIPWIRE_URL" -o "$tmp/rw.tgz"
if ! echo "${rw_sha}  ${tmp}/rw.tgz" | sha256sum -c - ; then
    log "FATAL: ripwire checksum mismatch — refusing to install"; rm -rf "$tmp"; exit 1
fi

rm -rf "$RIPWIRE_DIR"
mkdir -p "$RIPWIRE_DIR"
# One versioned root dir in the tarball; --strip-components=1 lands its contents
# directly in RIPWIRE_DIR.
tar xzf "$tmp/rw.tgz" -C "$RIPWIRE_DIR" --strip-components=1
rm -rf "$tmp"

# Only the BINARY goes on PATH. The tarball also ships hooks/ and skills/ — both
# deliberately unused. Its hooks register on PreToolUse, the same event as
# pt-ai-guard.sh, and its skills/install.sh symlinks into ~/.claude/skills, which
# here IS /opt/pt-ai/skills — a root-owned one-way rsync tree from the host.
# See features/ripwire-integration.md §3. The extracted tree is kept rather than
# pruned to the binary because Apache-2.0 §4 requires retaining the LICENSE that
# ships beside it.
install -m 0755 "$RIPWIRE_DIR/ripwire" "$BIN_DST"

log "ripwire ready: $("$BIN_DST" --version 2>/dev/null | head -1)"
