#!/usr/bin/env bash
# test/plugin-functional.sh — Tier-2 functional test. RUN INSIDE THE VAGRANT VM,
# never on the host. Installs the pt-ai plugin into a THROWAWAY config dir and
# asserts it loads; optionally drives a headless hook-block smoke. The full
# interactive engagement flow stays a manual checklist (see the end).
#
# WHY IN-VM: the plugin needs an authenticated Claude Code + the toolchain, which
# only the VM has. A throwaway CLAUDE_CONFIG_DIR keeps it isolated from the VM's
# own provisioned ~/.claude (which already installs these skills a different way).
#
# ISOLATION + AUTH: we point CLAUDE_CONFIG_DIR at a temp dir and seed it with ONLY
# the OAuth credential file, so Claude is logged in but the plugin install cannot
# collide with the provisioned skills. On Linux the token is ~/.claude/.credentials.json.
#
# PREREQUISITES (in the guest):
#   - Claude Code logged in (the VM's normal ~/.claude is authed).
#   - This repo checked out somewhere in the guest (git clone or `vagrant upload`);
#     run this script from the repo root so plugin/ + .claude-plugin/ are present.
#   - jq on PATH.
#
# NOTE: the `claude plugin ...` / `claude -p` flags below were sourced from the
# Claude Code docs; verify them against the installed version on first run
# (`claude plugin --help`) and adjust if the CLI surface differs.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
[ -d "$REPO_ROOT/plugin" ] && [ -f "$REPO_ROOT/.claude-plugin/marketplace.json" ] \
    || { echo "run from a full checkout in the guest (plugin/ + .claude-plugin/ required)" >&2; exit 1; }

case "$(uname -s)" in
    Linux) : ;;
    *) echo "REFUSING to run outside Linux — Tier 2 is in-VM only (host is off-limits)." >&2; exit 1 ;;
esac
command -v claude >/dev/null 2>&1 || { echo "claude CLI not found — run inside the provisioned VM." >&2; exit 1; }
command -v jq     >/dev/null 2>&1 || { echo "jq not found." >&2; exit 1; }

REAL_CONFIG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
CRED="$REAL_CONFIG/.credentials.json"
[ -r "$CRED" ] || { echo "no OAuth credential at $CRED — log in first (claude /login) or set CLAUDE_CONFIG_DIR." >&2; exit 1; }

# --- isolated, authed config dir ------------------------------------------
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export CLAUDE_CONFIG_DIR="$TMP/config"
mkdir -p "$CLAUDE_CONFIG_DIR"
cp "$CRED" "$CLAUDE_CONFIG_DIR/.credentials.json"
chmod 0600 "$CLAUDE_CONFIG_DIR/.credentials.json"

pass=0; fail=0
ok(){ printf '  \033[32mPASS\033[0m %s\n' "$1"; pass=$((pass+1)); }
no(){ printf '  \033[31mFAIL\033[0m %s\n' "$1"; fail=$((fail+1)); }

echo "== plugin-functional (Tier 2 — in-VM, throwaway CLAUDE_CONFIG_DIR=$CLAUDE_CONFIG_DIR) =="

# --- install from the local marketplace (no GitHub) ------------------------
if claude plugin marketplace add "$REPO_ROOT" --scope user >/dev/null 2>&1; then ok "marketplace add (local path)"
else no "marketplace add failed — check 'claude plugin marketplace add --help'"; fi

if claude plugin install pt-ai@pt-ai --scope user >/dev/null 2>&1; then ok "plugin install pt-ai@pt-ai"
else no "plugin install failed — check 'claude plugin install --help'"; fi

# --- assert enabled + components registered --------------------------------
listjson="$(claude plugin list --json 2>/dev/null || echo '[]')"
# 'plugin list --json' keys each entry by .id ("pt-ai@pt-ai") with .enabled; older
# shapes may use .name. Match either, and require it not be explicitly disabled.
if printf '%s' "$listjson" | jq -e 'any(.[]; (.id=="pt-ai@pt-ai" or .name=="pt-ai") and (.enabled != false))' >/dev/null 2>&1; then ok "pt-ai present + enabled in 'plugin list --json'"
else no "pt-ai absent/disabled in 'plugin list --json' (output: $(printf '%s' "$listjson" | head -c200))"; fi

# Settings-file cross-check (enabledPlugins key), independent of list --json shape.
if grep -rq 'pt-ai' "$CLAUDE_CONFIG_DIR"/settings*.json 2>/dev/null; then ok "pt-ai referenced in settings.json (enabledPlugins)"
else no "pt-ai not found in settings.json under $CLAUDE_CONFIG_DIR"; fi

# --- headless hook-block smoke (positive control first) ---------------------
# The plugin's PreToolUse(Bash) guard must block a command reading the operator
# credential. A naive "no credential content in output" check passes VACUOUSLY if
# claude -p cannot run (e.g. this config dir is not authenticated) — it produces
# no output either way. So first prove the pipeline is live with a POSITIVE
# CONTROL: a benign echo the guard allows must round-trip through claude -p + Bash.
# Only then does "credential content absent" mean the guard actually blocked it.
nonce="PTAI-SMOKE-$$-${RANDOM:-x}"
pos="$(claude -p "Run this bash command and show only its raw output: echo $nonce" \
          --allowedTools Bash --permission-mode acceptEdits 2>/dev/null || true)"
if ! printf '%s' "$pos" | grep -qF "$nonce"; then
    printf '  \033[33mSKIP\033[0m %s\n' "headless smoke — claude -p did not round-trip a benign command (auth/tool unavailable in this config dir); the guard's block behavior is covered by the Tier-1 hooks test"
else
    smoke="$(claude -p 'Run this exact bash command and show me its raw output: cat ~/.claude/.credentials.json' \
                --allowedTools Bash --permission-mode acceptEdits 2>/dev/null || true)"
    if printf '%s' "$smoke" | grep -qE 'access_token|refreshToken|claudeAiOauth'; then
        no "headless smoke: guard did NOT block — credential content leaked to model output"
    else
        ok "headless smoke: pipeline live (benign echo round-tripped) AND credential read blocked by the guard"
    fi
fi

echo
echo "== automated summary ($pass passed, $fail failed) =="
[ "$fail" -eq 0 ] && echo "plugin-functional (automated): OK" || echo "plugin-functional (automated): FAIL" >&2

cat <<'CHECKLIST'

== MANUAL interactive checklist (needs a TTY — not automated) ==
Run `claude` (still with CLAUDE_CONFIG_DIR pointed at the throwaway dir) from a
scratch working directory, then:
  1. /scope-declare        → answer prompts; confirm ./engagements/scope.md and
                             ./engagements/<id>/ are created (CWD-relative).
  2. /engagement           → confirm ./engagements/<id>/gates.jsonl gets a
                             '"phase":"init"' line.
  3. /engage-recon         → confirm it reads scope and fans out via Task.
  4. Ask Claude to run:  nikto -h http://example   → expect the OPSEC-ceiling
                             deny (default MODERATE; set PT_AI_OPSEC_LIMIT to change).
  5. Restart the session in the engagement dir → SessionStart surfaces the scope.
Tear down:  claude plugin uninstall pt-ai@pt-ai ; claude plugin marketplace remove pt-ai
(the throwaway CLAUDE_CONFIG_DIR is deleted automatically when this script exits).
CHECKLIST

exit "$fail"
