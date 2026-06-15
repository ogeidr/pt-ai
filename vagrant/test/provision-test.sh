#!/usr/bin/env bash
# provision-test.sh — single-file harness that provisions the pt-ai VM on Kali
# and/or Debian, then asserts the result and writes logs.
#
# It runs in two modes from ONE file:
#   * HOST mode  (default): drives `vagrant` via the ./pt-ai wrapper, then
#     re-invokes itself INSIDE the guest over ssh to verify the deployment.
#   * GUEST mode (--assert): runs the in-guest assertions. The host calls this
#     as `/vagrant/test/provision-test.sh --assert` (vagrant syncs vagrant/ to
#     /vagrant, so the same file is present in the guest).
#
# WHAT IT VERIFIES
#   1. kali    — default toolset path; the Kali-only steps must RUN.
#   2. debian  — apt-family non-Kali; the framework layer must provision while
#                the Kali-only steps SKIP.
#
# SAFETY / ISOLATION
#   All Vagrant state lives under test/.vagrant-test/ (VAGRANT_DOTFILE_PATH), so
#   your normal `./pt-ai` VM, its OAuth credentials, and snapshots are NOT touched
#   and NOT destroyed. Cases run sequentially against this isolated machine
#   (destroyed between cases unless KEEP=1). Tip: `./pt-ai halt` first.
#
# USAGE
#   ./test/provision-test.sh [kali|debian|both]      (default: both)
#
# ENV OVERRIDES (host mode)
#   TEST_PROVIDER       vagrant provider               (default: vmware_desktop)
#   TEST_KALI_BOX       Kali box name                  (default: kali-arm64)
#   TEST_DEBIAN_BOX     Debian box name                (default: bento/debian-13)
#   TEST_DEBIAN_GHIDRA  1=full incl. ghidrasql + ghidra-rpc, 0=skip (default: 1)
#   KEEP                1=leave test VM running         (default: destroy each)
# ENV (guest mode)
#   EXPECT_GHIDRASQL    1|0  whether ghidrasql should be installed (default: 1)
#   EXPECT_GHIDRA_RPC   1|0  whether ghidra-rpc should be installed (default: 1)
#
# OUTPUT
#   test/results/<case>-provision.log   full `./pt-ai up` output
#   test/results/<case>-assert.log      in-guest assertion output
#   test/results/summary.txt            one PASS/FAIL line per case
set -uo pipefail

# ======================================================================
# GUEST MODE — in-guest assertions (dispatched before any host setup)
# ======================================================================
if [ "${1:-}" = "--assert" ]; then
    # Load the provisioned environment so claude/opencode/pipx CLIs and the
    # Ghidra env are on PATH even under a non-login `ssh -c` shell. /usr/sbin is
    # added because Debian keeps a regular user's PATH free of sbin.
    [ -r /etc/profile.d/pt-ai.sh ]            && . /etc/profile.d/pt-ai.sh
    [ -r /etc/profile.d/pt-ai-ghidrasql.sh ]  && . /etc/profile.d/pt-ai-ghidrasql.sh
    [ -r /etc/profile.d/pt-ai-ghidra-rpc.sh ] && . /etc/profile.d/pt-ai-ghidra-rpc.sh
    export PATH="$HOME/.npm-global/bin:$HOME/.local/bin:/usr/sbin:/sbin:$PATH"

    EXPECT_GHIDRASQL="${EXPECT_GHIDRASQL:-1}"
    EXPECT_GHIDRA_RPC="${EXPECT_GHIDRA_RPC:-1}"

    pass=0; fail=0
    ok(){ printf '  \033[32mPASS\033[0m %s\n' "$1"; pass=$((pass+1)); }
    no(){ printf '  \033[31mFAIL\033[0m %s\n' "$1"; fail=$((fail+1)); }
    # check "desc" cmd...  -> PASS when cmd succeeds
    check(){ local d="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$d"; else no "$d"; fi; }
    # checkn "desc" cmd... -> PASS when cmd FAILS (for "must be absent" cases)
    checkn(){ local d="$1"; shift; if "$@" >/dev/null 2>&1; then no "$d"; else ok "$d"; fi; }

    pkg_installed(){ dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q 'install ok installed'; }
    has_kali_source(){ grep -rq kali-rolling /etc/apt/sources.list /etc/apt/sources.list.d/ 2>/dev/null; }
    kali_uu_origin(){ grep -q 'origin=Kali' /etc/apt/apt.conf.d/50unattended-upgrades 2>/dev/null; }

    ID=""; PRETTY=""
    if [ -r /etc/os-release ]; then . /etc/os-release; PRETTY="${PRETTY_NAME:-}"; fi
    IS_KALI=false; [ "${ID:-}" = "kali" ] && IS_KALI=true

    echo "== pt-ai deployment assertions =="
    echo "Guest: ${PRETTY:-unknown}  (ID=${ID:-?})  EXPECT_GHIDRASQL=$EXPECT_GHIDRASQL  EXPECT_GHIDRA_RPC=$EXPECT_GHIDRA_RPC"
    echo

    echo "[framework layer — required on every box]"
    check  "apt-get present"                        command -v apt-get
    check  "node is v20+"                           bash -c 'node --version | grep -qE "^v2[0-9]"'
    check  "claude CLI runs"                         bash -c 'claude --version'
    check  "opencode present"                        command -v opencode
    check  "CLAUDE.md present"                        test -f "$HOME/.claude/CLAUDE.md"
    check  "CLAUDE.md carries evidence path rules"   grep -q "Evidence path rules" "$HOME/.claude/CLAUDE.md"
    check  "agents dir populated"                    bash -c 'ls "$HOME"/.claude/agents/*.md >/dev/null 2>&1'
    check  "recon-advisor references /engagements"   grep -q "/engagements" "$HOME/.claude/agents/recon-advisor.md"
    checkn "recon-advisor has no legacy /work/ path" grep -q "/work/" "$HOME/.claude/agents/recon-advisor.md"
    check  "opencode subagents generated"            bash -c 'ls "$HOME"/.config/opencode/agents/*.md >/dev/null 2>&1'
    check  "opencode subagent carries scope guard"   grep -qE "Authorization Verification|Scope Enforcement" "$HOME/.config/opencode/agents/recon-advisor.md"
    check  "advisory subagent denies bash"           grep -q "bash: deny" "$HOME/.config/opencode/agents/report-generator.md"
    checkn "Tier-2 subagent does not deny bash"      grep -q "bash: deny" "$HOME/.config/opencode/agents/recon-advisor.md"
    check  "opencode discovers skills (claude-compat symlink)" test -e "$HOME/.claude/skills/full-recon/SKILL.md"
    checkn "legacy opencode commands dir absent"     test -d "$HOME/.config/opencode/commands"
    check  "/engagements exists and is writable"     bash -c 't=/engagements/.ptai-write-test.$$; test -d /engagements && touch "$t" && rm -f "$t"'
    check  "ip_forward enabled"                      bash -c '[ "$(cat /proc/sys/net/ipv4/ip_forward 2>/dev/null)" = 1 ]'
    check  "SSH password auth disabled"              grep -qE '^PasswordAuthentication no' /etc/ssh/sshd_config
    check  "SSH root login disabled"                 grep -qE '^PermitRootLogin no' /etc/ssh/sshd_config
    check  "unattended-upgrades installed"           pkg_installed unattended-upgrades
    check  "aws CLI v2 present"                      bash -c 'aws --version 2>&1 | grep -q aws-cli/2'
    check  "trufflehog present"                      command -v trufflehog
    check  "prowler present"                         command -v prowler
    # New 06-cloud installers — cross-box (binary/apt-repo), so verify they landed.
    check  "gitleaks present (GitHub-release binary)" command -v gitleaks
    check  "kubeaudit present (GitHub-release binary)" command -v kubeaudit
    check  "gcloud present (vendor apt repo)"        command -v gcloud
    check  "_lib.sh present and apt-detected"        bash -c '. /vagrant/provision/_lib.sh; [ "$IS_APT" = true ]'

    echo
    if $IS_KALI; then
        echo "[Kali-only steps — must be PRESENT on Kali]"
        check  "kali-rolling apt source present"     has_kali_source
        check  "kali-linux-default installed"        pkg_installed kali-linux-default
        check  "unattended-upgrades pinned to Kali"  kali_uu_origin
        check  "_lib.sh reports IS_KALI=true"        bash -c '. /vagrant/provision/_lib.sh; [ "$IS_KALI" = true ]'
    else
        echo "[non-Kali apt box — Kali-only steps must be ABSENT]"
        checkn "no kali-rolling apt source"          has_kali_source
        checkn "kali-linux-default NOT installed"    pkg_installed kali-linux-default
        checkn "no Kali origin in unattended-upgrades" kali_uu_origin
        check  "_lib.sh reports IS_KALI=false"       bash -c '. /vagrant/provision/_lib.sh; [ "$IS_KALI" = false ]'
    fi

    if [ "$EXPECT_GHIDRASQL" = 1 ]; then
        echo
        echo "[ghidrasql]"
        check "ghidrasql binary present" test -x /usr/local/bin/ghidrasql
        check "ghidrasql --help runs"    bash -c '/usr/local/bin/ghidrasql --help'
    fi

    if [ "$EXPECT_GHIDRA_RPC" = 1 ]; then
        echo
        echo "[ghidra-rpc]"
        check "ghidra-rpc binary present" test -x /usr/local/bin/ghidra-rpc
        check "ghidra-rpc --version runs" bash -c '/usr/local/bin/ghidra-rpc --version'
    fi

    echo
    echo "== result: $pass passed, $fail failed =="
    [ "$fail" -eq 0 ]
    exit
fi

# ======================================================================
# HOST MODE — provision each box, then run the guest assertions
# ======================================================================
here=$(cd "$(dirname "$0")" && pwd)
VAGRANT_DIR=$(cd "$here/.." && pwd)
RESULTS="$here/results"
SELF_IN_GUEST="/vagrant/test/$(basename "$0")"
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
# Ghidra-skip are passed via the same env vars the wrapper forwards. The single
# skip/expect parameter governs BOTH Ghidra-backed tools (ghidrasql + ghidra-rpc).
run_case(){ # name box skip_ghidra expect_ghidra
  local name="$1" box="$2" skip="$3" expect="$4"
  local plog="$RESULTS/${name}-provision.log"
  local alog="$RESULTS/${name}-assert.log"

  say "CASE $name — box=$box provider=$PROVIDER skip_ghidra='${skip:-0}'"

  # Clean slate for the ISOLATED test machine only (never the user's VM).
  PTAI_BOX="$box" VAGRANT_PROVIDER="$PROVIDER" ./pt-ai destroy >/dev/null 2>&1 || true

  say "$name: provisioning (this takes a while) → ${name}-provision.log"
  PTAI_BOX="$box" VAGRANT_PROVIDER="$PROVIDER" \
      PTAI_SKIP_GHIDRASQL="$skip" PTAI_SKIP_GHIDRA_RPC="$skip" \
      ./pt-ai up 2>&1 | tee "$plog"
  local up_rc=${PIPESTATUS[0]}
  if [ "$up_rc" -ne 0 ]; then
    record "FAIL  $name  provisioning failed (rc=$up_rc) — see ${name}-provision.log"
    [ "$KEEP" = 1 ] || PTAI_BOX="$box" VAGRANT_PROVIDER="$PROVIDER" ./pt-ai destroy >/dev/null 2>&1 || true
    return 1
  fi

  say "$name: running in-guest assertions → ${name}-assert.log"
  PTAI_BOX="$box" VAGRANT_PROVIDER="$PROVIDER" \
      ./pt-ai ssh -c "EXPECT_GHIDRASQL=$expect EXPECT_GHIDRA_RPC=$expect bash $SELF_IN_GUEST --assert" 2>&1 | tee "$alog"
  local as_rc=${PIPESTATUS[0]}

  if [ "$as_rc" -eq 0 ]; then
    record "PASS  $name  provisioned + all assertions passed"
  else
    record "FAIL  $name  assertions failed (rc=$as_rc) — see ${name}-assert.log"
  fi

  [ "$KEEP" = 1 ] || {
    say "$name: destroying isolated test VM"
    PTAI_BOX="$box" VAGRANT_PROVIDER="$PROVIDER" ./pt-ai destroy >/dev/null 2>&1 || true
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
#     ./pt-ai VM is untouched.
#   * the best-effort destroy clears any leftover *isolated* test machine.
say "preflight: pruning stale Vagrant state"
vagrant global-status --prune >/dev/null 2>&1 || true
VAGRANT_PROVIDER="$PROVIDER" ./pt-ai destroy >/dev/null 2>&1 || true

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
