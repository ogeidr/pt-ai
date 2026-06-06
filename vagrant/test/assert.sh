#!/usr/bin/env bash
# assert.sh — in-guest deployment assertions for the pt-ai VM.
#
# Run INSIDE the VM (run-tests.sh invokes it via `./kali ssh -c`). It detects
# the distro from /etc/os-release and verifies two things:
#   * the generic pt-ai framework layer — must be present on EVERY box;
#   * the Kali toolset layer — PRESENT on Kali, ABSENT on non-Kali apt boxes.
#
# Exits non-zero if any check fails.
#
# Env:
#   EXPECT_GHIDRASQL=1|0   whether ghidrasql should be installed (default 1)

set -uo pipefail   # deliberately NOT -e: every check must run

# Load the provisioned environment so claude/opencode/pipx CLIs and the Ghidra
# env are on PATH even under a non-login `ssh -c` shell.
[ -r /etc/profile.d/pt-ai.sh ]           && . /etc/profile.d/pt-ai.sh
[ -r /etc/profile.d/pt-ai-ghidrasql.sh ] && . /etc/profile.d/pt-ai-ghidrasql.sh
export PATH="$HOME/.npm-global/bin:$HOME/.local/bin:$PATH"

EXPECT_GHIDRASQL="${EXPECT_GHIDRASQL:-1}"

pass=0; fail=0
ok(){ printf '  \033[32mPASS\033[0m %s\n' "$1"; pass=$((pass+1)); }
no(){ printf '  \033[31mFAIL\033[0m %s\n' "$1"; fail=$((fail+1)); }
# check "desc" cmd...     -> PASS when cmd succeeds
check(){ local d="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$d"; else no "$d"; fi; }
# checkn "desc" cmd...    -> PASS when cmd FAILS (for "must be absent" cases)
checkn(){ local d="$1"; shift; if "$@" >/dev/null 2>&1; then no "$d"; else ok "$d"; fi; }

pkg_installed(){ dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q 'install ok installed'; }
has_kali_source(){ grep -rq kali-rolling /etc/apt/sources.list /etc/apt/sources.list.d/ 2>/dev/null; }
kali_uu_origin(){ grep -q 'origin=Kali' /etc/apt/apt.conf.d/50unattended-upgrades 2>/dev/null; }

# --- distro detection ----------------------------------------------------
ID=""; PRETTY=""
if [ -r /etc/os-release ]; then . /etc/os-release; PRETTY="${PRETTY_NAME:-}"; fi
IS_KALI=false; [ "${ID:-}" = "kali" ] && IS_KALI=true

echo "== pt-ai deployment assertions =="
echo "Guest: ${PRETTY:-unknown}  (ID=${ID:-?})  EXPECT_GHIDRASQL=$EXPECT_GHIDRASQL"
echo

echo "[framework layer — required on every box]"
check  "apt-get present"                       command -v apt-get
check  "node is v20+"                          bash -c 'node --version | grep -qE "^v2[0-9]"'
check  "claude CLI runs"                        bash -c 'claude --version'
check  "opencode present"                       command -v opencode
check  "CLAUDE.md present"                       test -f "$HOME/.claude/CLAUDE.md"
check  "CLAUDE.md carries evidence path rules"  grep -q "Evidence path rules" "$HOME/.claude/CLAUDE.md"
check  "agents dir populated"                   bash -c 'ls "$HOME"/.claude/agents/*.md >/dev/null 2>&1'
check  "recon-advisor references /engagements"  grep -q "/engagements" "$HOME/.claude/agents/recon-advisor.md"
checkn "recon-advisor has no legacy /work/ path" grep -q "/work/" "$HOME/.claude/agents/recon-advisor.md"
check  "opencode commands derived"              bash -c 'ls "$HOME"/.config/opencode/commands/*.md >/dev/null 2>&1'
check  "/engagements exists and is writable"    bash -c 't=/engagements/.ptai-write-test.$$; test -d /engagements && touch "$t" && rm -f "$t"'
check  "ip_forward enabled"                     bash -c '[ "$(sysctl -n net.ipv4.ip_forward 2>/dev/null)" = 1 ]'
check  "SSH password auth disabled"             grep -qE '^PasswordAuthentication no' /etc/ssh/sshd_config
check  "SSH root login disabled"                grep -qE '^PermitRootLogin no' /etc/ssh/sshd_config
check  "unattended-upgrades installed"          pkg_installed unattended-upgrades
check  "aws CLI v2 present"                     bash -c 'aws --version 2>&1 | grep -q aws-cli/2'
check  "trufflehog present"                     command -v trufflehog
check  "prowler present"                        command -v prowler
check  "_lib.sh present and apt-detected"       bash -c '. /vagrant/provision/_lib.sh; [ "$IS_APT" = true ]'

echo
if $IS_KALI; then
  echo "[Kali-only steps — must be PRESENT on Kali]"
  check  "kali-rolling apt source present"        has_kali_source
  check  "kali-linux-default installed"           pkg_installed kali-linux-default
  check  "unattended-upgrades pinned to Kali"     kali_uu_origin
  check  "_lib.sh reports IS_KALI=true"           bash -c '. /vagrant/provision/_lib.sh; [ "$IS_KALI" = true ]'
else
  echo "[non-Kali apt box — Kali-only steps must be ABSENT]"
  checkn "no kali-rolling apt source"             has_kali_source
  checkn "kali-linux-default NOT installed"        pkg_installed kali-linux-default
  checkn "no Kali origin in unattended-upgrades"   kali_uu_origin
  check  "_lib.sh reports IS_KALI=false"          bash -c '. /vagrant/provision/_lib.sh; [ "$IS_KALI" = false ]'
fi

if [ "$EXPECT_GHIDRASQL" = 1 ]; then
  echo
  echo "[ghidrasql]"
  check "ghidrasql binary present" test -x /usr/local/bin/ghidrasql
  check "ghidrasql --help runs"    bash -c '/usr/local/bin/ghidrasql --help'
fi

echo
echo "== result: $pass passed, $fail failed =="
[ "$fail" -eq 0 ]
