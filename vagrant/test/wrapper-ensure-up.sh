#!/usr/bin/env bash
# vagrant/test/wrapper-ensure-up.sh — static regression guard for the pt-ai
# wrapper's VM-readiness fix. No VM required: it only inspects vagrant/pt-ai.
#
# Background: `./pt-ai claude` (and opencode/ssh) call `vagrant ssh` directly.
# Against a halted / saved / not-created machine that prints an opaque
# "not yet ready for SSH" error. The fix is `_ensure_up`, which probes SSH and
# boots on demand. This test pins that wiring so a future refactor can't quietly
# drop it and bring the error back.
#
# Run: bash vagrant/test/wrapper-ensure-up.sh
# Exit 0 = all green. Exit 1 = a check failed.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
WRAPPER="$HERE/../pt-ai"

fail=0
pass(){ printf '  \033[32mPASS\033[0m %s\n' "$1"; }
bad(){  printf '  \033[31mFAIL\033[0m %s\n' "$1"; fail=$((fail+1)); }

[ -f "$WRAPPER" ] || { echo "wrapper-ensure-up: FAIL — $WRAPPER not found" >&2; exit 1; }

echo "== wrapper-ensure-up (static, VM-free) =="

# 0) The wrapper must still be valid POSIX sh (the fix must not break parsing).
if sh -n "$WRAPPER" 2>/dev/null; then pass "pt-ai parses (sh -n)"; else bad "pt-ai fails sh -n"; fi

# Print a function's body: from `NAME() {` to the first `}` in column 0. Every
# function in this file closes with a bare `}` at column 0, so this slices cleanly.
func_body(){ awk -v fn="$1" '
  $0 ~ "^"fn"\\(\\) \\{" {inf=1}
  inf {print}
  inf && /^\}/ {exit}
' "$WRAPPER"; }

# 1) The helper exists.
if grep -q '^_ensure_up() {' "$WRAPPER"; then pass "_ensure_up is defined"; else bad "_ensure_up is missing"; fi

# 2) The helper has the probe-then-boot shape (honest SSH probe + auto-up), not
#    a status-string guess or a no-op stub.
body="$(func_body _ensure_up)"
if printf '%s' "$body" | grep -q '_vagrant ssh'; then pass "_ensure_up probes over SSH"; else bad "_ensure_up has no SSH probe"; fi
if printf '%s' "$body" | grep -q 'cmd_up';       then pass "_ensure_up boots on demand (cmd_up)"; else bad "_ensure_up never boots (no cmd_up)"; fi

# 3) Every interactive entry point invokes the guard — this is the actual
#    regression surface (the original bug was these calling `vagrant ssh` raw).
for fn in cmd_ssh cmd_claude cmd_opencode; do
    if func_body "$fn" | grep -q '_ensure_up'; then
        pass "$fn calls _ensure_up"
    else
        bad "$fn does NOT call _ensure_up (raw 'vagrant ssh' will show the not-ready error)"
    fi
done

echo
if [ "$fail" -eq 0 ]; then echo "wrapper-ensure-up: OK"; exit 0; fi
echo "wrapper-ensure-up: FAIL ($fail check(s))" >&2; exit 1
