#!/usr/bin/env bash
# test/plugin-suite.sh — Tier-1 (mechanical) plugin test aggregator. VM-free:
# needs only bash + jq (or python3). Runs the four mechanical checks and writes
# a one-line-per-check summary, mirroring vagrant/test/provision-test.sh.
#
#   parity   — committed plugin/ == a fresh tools/build-plugin.sh (also exercises the build)
#   hooks    — pt-ai-guard.sh denies/allows correctly (credential/rm/OPSEC/Read)
#   validate — manifests/frontmatter/exec-bits/guard-verbatim/counts/shared-blocks
#   cvss     — severity-calibrate's CVSS v3.1 math vs FIRST's published reference
#              scores. Bundled-script logic, so it belongs in the per-push tier
#              rather than behind a 30-60 min VM provision; also the cheapest
#              signal on awk portability (set AWK=mawk/gawk to pin one).
#
# This is what CI runs (.github/workflows/plugin-suite.yml). It does NOT install
# the plugin or touch ~/.claude — that is Tier 2 (test/plugin-functional.sh, in-VM).
#
# Exit 0 = all green. Exit 1 = a check failed (CI-gateable).
set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
RESULTS="$here/results"
SUMMARY="$RESULTS/summary.txt"
mkdir -p "$RESULTS"
: > "$SUMMARY"

pass=0; fail=0
record(){ echo "$1" | tee -a "$SUMMARY"; }

# --- preflight: a JSON parser is mandatory --------------------------------
# Without jq/python3 the guard fails CLOSED, so plugin-hooks' allow-cases would
# fail for the wrong reason. Gate loudly instead of emitting confusing results.
if ! command -v jq >/dev/null 2>&1 && ! command -v python3 >/dev/null 2>&1; then
    record "ABORT  preflight  no jq/python3 on PATH — the guard needs a JSON parser"
    echo "plugin-suite: ABORT — install jq or python3" >&2
    exit 1
fi
command -v jq >/dev/null 2>&1 || record "WARN   preflight  jq absent; falling back to python3"

echo "== plugin-suite (Tier 1 — mechanical, VM-free) =="

run(){ # run <name> <script...>
    local name="$1"; shift
    local log="$RESULTS/${name}.log"
    if bash "$@" >"$log" 2>&1; then
        printf '  \033[32mPASS\033[0m %s\n' "$name"; record "PASS  $name"; pass=$((pass+1))
    else
        printf '  \033[31mFAIL\033[0m %s  (see results/%s.log)\n' "$name" "$name"; record "FAIL  $name  (see results/${name}.log)"; fail=$((fail+1))
        sed 's/^/      | /' "$log"
    fi
}

run parity   "$here/plugin-parity.sh"
run hooks    "$here/plugin-hooks.sh"
run validate "$here/plugin-validate.sh"
# skills/ is the single source; plugin/skills is its build output, and parity
# above proves the two identical — so testing the source copy covers both.
run cvss     "$here/../skills/severity-calibrate/scripts/cvss.test.sh"

echo
echo "== summary ($pass passed, $fail failed) — $SUMMARY =="
if [ "$fail" -eq 0 ]; then echo "plugin-suite: OK"; exit 0; fi
echo "plugin-suite: FAIL" >&2; exit 1
