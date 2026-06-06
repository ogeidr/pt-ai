#!/usr/bin/env bash
# run-tests.sh — end-to-end deployment test for the pt-ai VM across two boxes:
#   1. kali    — default toolset path; the Kali-only steps must RUN.
#   2. debian  — apt-family non-Kali; the framework layer must provision while
#                the Kali-only steps SKIP.
#
# SAFETY / ISOLATION
#   All Vagrant state for this test lives under test/.vagrant-test/ (via
#   VAGRANT_DOTFILE_PATH), so your normal `./kali` VM, its OAuth credentials,
#   and snapshots are NOT touched and NOT destroyed. The two cases run
#   sequentially against this isolated machine (destroyed between cases unless
#   KEEP=1). Tip: `./kali halt` your working VM first to avoid contention.
#
# USAGE
#   ./test/run-tests.sh [kali|debian|both]      (default: both)
#
# ENV OVERRIDES
#   TEST_PROVIDER       vagrant provider              (default: vmware_desktop)
#   TEST_KALI_BOX       Kali box name                 (default: kali-arm64)
#   TEST_DEBIAN_BOX     Debian box name               (default: bento/debian-13)
#   TEST_DEBIAN_GHIDRA  1=full incl. ghidrasql, 0=skip (default: 1)
#   KEEP                1=leave test VM running        (default: destroy each)
#
# OUTPUT
#   test/results/<case>-provision.log   full `./kali up` output
#   test/results/<case>-assert.log      in-guest assertion output
#   test/results/summary.txt            one PASS/FAIL line per case
set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd)
VAGRANT_DIR=$(cd "$here/.." && pwd)
RESULTS="$here/results"
export VAGRANT_DOTFILE_PATH="$here/.vagrant-test"

PROVIDER="${TEST_PROVIDER:-vmware_desktop}"
KALI_BOX="${TEST_KALI_BOX:-kali-arm64}"
DEBIAN_BOX="${TEST_DEBIAN_BOX:-bento/debian-13}"
DEBIAN_GHIDRA="${TEST_DEBIAN_GHIDRA:-1}"
KEEP="${KEEP:-0}"
WHICH="${1:-both}"

mkdir -p "$RESULTS"
cd "$VAGRANT_DIR"

say(){ printf '\n\033[1m[%s] %s\033[0m\n' "$(date +%H:%M:%S)" "$*"; }
SUMMARY="$RESULTS/summary.txt"
: > "$SUMMARY"
record(){ printf '%s\n' "$1" | tee -a "$SUMMARY"; }

# Reuse the kali wrapper so it is itself exercised end-to-end. Box / provider /
# ghidrasql-skip are passed via the same env vars the wrapper forwards.
run_case(){ # name box skip_ghidra expect_ghidra
  local name="$1" box="$2" skip="$3" expect="$4"
  local plog="$RESULTS/${name}-provision.log"
  local alog="$RESULTS/${name}-assert.log"

  say "CASE $name — box=$box provider=$PROVIDER skip_ghidrasql='${skip:-0}'"

  # Clean slate for the ISOLATED test machine only (never the user's VM).
  PTAI_BOX="$box" VAGRANT_PROVIDER="$PROVIDER" ./kali destroy >/dev/null 2>&1 || true

  say "$name: provisioning (this takes a while) → ${name}-provision.log"
  PTAI_BOX="$box" VAGRANT_PROVIDER="$PROVIDER" PTAI_SKIP_GHIDRASQL="$skip" \
      ./kali up 2>&1 | tee "$plog"
  local up_rc=${PIPESTATUS[0]}
  if [ "$up_rc" -ne 0 ]; then
    record "FAIL  $name  provisioning failed (rc=$up_rc) — see ${name}-provision.log"
    [ "$KEEP" = 1 ] || PTAI_BOX="$box" VAGRANT_PROVIDER="$PROVIDER" ./kali destroy >/dev/null 2>&1 || true
    return 1
  fi

  say "$name: running in-guest assertions → ${name}-assert.log"
  PTAI_BOX="$box" VAGRANT_PROVIDER="$PROVIDER" \
      ./kali ssh -c "EXPECT_GHIDRASQL=$expect bash /vagrant/test/assert.sh" 2>&1 | tee "$alog"
  local as_rc=${PIPESTATUS[0]}

  if [ "$as_rc" -eq 0 ]; then
    record "PASS  $name  provisioned + all assertions passed"
  else
    record "FAIL  $name  assertions failed (rc=$as_rc) — see ${name}-assert.log"
  fi

  [ "$KEEP" = 1 ] || {
    say "$name: destroying isolated test VM"
    PTAI_BOX="$box" VAGRANT_PROVIDER="$PROVIDER" ./kali destroy >/dev/null 2>&1 || true
  }
  return "$as_rc"
}

command -v vagrant >/dev/null 2>&1 || { echo "ERROR: vagrant not installed" >&2; exit 2; }

# --- preflight: clear stale Vagrant state from interrupted runs -----------
# A run killed mid-provision (e.g. a network drop) can leave a phantom entry in
# Vagrant's global machine index plus a half-initialised test dotfile. Clean
# both up front so "start over" is automatic.
#   * `global-status --prune` only drops index entries whose machine state is
#     already gone — it never destroys a valid, running machine, so your normal
#     ./kali VM is untouched.
#   * the best-effort destroy clears any leftover *isolated* test machine.
say "preflight: pruning stale Vagrant state"
vagrant global-status --prune >/dev/null 2>&1 || true
VAGRANT_PROVIDER="$PROVIDER" ./kali destroy >/dev/null 2>&1 || true

do_kali=0; do_debian=0
case "$WHICH" in
  kali)   do_kali=1 ;;
  debian) do_debian=1 ;;
  both)   do_kali=1; do_debian=1 ;;
  *) echo "usage: $0 [kali|debian|both]" >&2; exit 2 ;;
esac

rc=0

if [ "$do_kali" = 1 ]; then
  if ! vagrant box list 2>/dev/null | grep -q "$KALI_BOX"; then
    echo "ERROR: Kali box '$KALI_BOX' not registered. Build it first: ./box/build.sh" >&2
    exit 2
  fi
  run_case kali "$KALI_BOX" "" 1 || rc=1
fi

if [ "$do_debian" = 1 ]; then
  if [ "$DEBIAN_GHIDRA" = 1 ]; then dskip=""; dexp=1; else dskip="1"; dexp=0; fi
  run_case debian "$DEBIAN_BOX" "$dskip" "$dexp" || rc=1
fi

say "SUMMARY"
cat "$SUMMARY"
exit "$rc"
