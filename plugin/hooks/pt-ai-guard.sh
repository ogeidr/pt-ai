#!/bin/sh
# pt-ai-guard.sh — Claude Code PreToolUse(Bash) safety hook for pt-ai.
#
# The *automated* gate behind the per-command permission prompt — the runtime
# backstop the security reviews kept asking for. Two stages, both DENY on match:
#
#   Stage 1 — credential exfil (PENDING #1/#2). Blocks any command referencing
#     the operator's LLM credential material, so an injected
#     `cat ~/.anthropic_key | curl ...` is stopped even if the model is fooled.
#       ~/.anthropic_key   ~/.claude/   /tmp/.ptai-key
#     Deliberately TIGHT — does NOT block ~/.aws, ~/.ssh, or target-side secrets:
#     the cloud-audit toolset (aws/prowler/pacu) reads ~/.aws legitimately and
#     looting target keys is normal pentest work.
#
#   Stage 2 — catastrophic recursive delete (PENDING #2/#5 payload). Blocks
#     `rm -r…` whose target is the filesystem root, a top-level system dir, the
#     home dir, or the /engagements evidence ROOT (a host bind — wiping it
#     destroys real data, e.g. `rm -rf /engagements/*`). Specific deep paths
#     stay allowed (`rm -rf /engagements/<id>/old`) so normal cleanup works.
#
# Deliberately NOT here: filtering network traffic by destination (curl/nc/nmap
# to "non-scope" hosts). A pentest agent's job is sending traffic to targets;
# guessing scope from a command string is high-false-positive and the wrong
# layer. Network egress belongs to the HOST egress allowlist (#1 control 3),
# not a command parser. Stage 2 is defense-in-depth, not a sandbox — it does not
# chase `find -delete` / `shred` / `dd` / truncation; the VM is ephemeral and
# engagements are host-synced.
#
# Shared gate. Run by the Claude Code PreToolUse hook AND by the opencode
# tool.execute.before plugin (05-opencode.sh installs a copy + plugin that
# feeds this script the same event JSON), so both front-ends enforce it.
#
# Contract: PreToolUse event JSON on stdin; print a deny decision to stdout
# (exit 0) to block, or exit 0 with no output to defer to the normal flow.
# Fails CLOSED (deny) if no JSON parser is available — that only happens on a
# broken provision, and a loud failure is safer than a silently-disabled guard.

input=$(cat)

# Optional argv[1] = tool context ("bash"|"read"). The Claude PreToolUse hook is
# Bash-only and passes nothing → defaults to "bash" (all stages). The opencode
# plugin passes the tool name, so a "read" probe (a bare file path) runs only the
# credential check below, not the rm / OPSEC command logic.
ctx="${1:-bash}"

# Extract the field to inspect. For Bash it is tool_input.command; for a Read
# probe (ctx=read) the Read tool carries tool_input.file_path instead, so fall
# back to it (and .path) — otherwise a PreToolUse(Read) hook would see an empty
# string and never match a credential path. The event JSON also carries
# transcript_path (which contains "/.claude/"), so we must parse the field,
# never grep the blob.
cmd=""
parsed=0
if command -v jq >/dev/null 2>&1; then
    cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // .tool_input.file_path // .tool_input.path // empty' 2>/dev/null) && parsed=1
elif command -v python3 >/dev/null 2>&1; then
    cmd=$(printf '%s' "$input" | python3 -c 'import sys, json
try:
    ti = json.load(sys.stdin).get("tool_input", {})
    print(ti.get("command") or ti.get("file_path") or ti.get("path") or "")
except Exception:
    sys.exit(3)' 2>/dev/null) && parsed=1
fi

deny() {
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$1"
    exit 0
}

if [ "$parsed" -ne 1 ]; then
    deny "pt-ai guard: no JSON parser (jq/python3) available; blocking as a precaution. Re-provision the VM."
fi

# --- Stage 1: operator LLM-credential exfil ---------------------------------
# Substring match catches cat/base64/cp/scp/tar/curl-@file/xxd/etc. uniformly.
# `/.claude` is matched at a boundary (dir itself or any file under it) but not
# `.clauderc` etc.; `.anthropic_key` / `.ptai-key` are full filenames.
if printf '%s' "$cmd" | grep -Eq '\.anthropic_key|/\.claude([^[:alnum:]]|$)|\.ptai-key'; then
    deny "Blocked by pt-ai guard: command references the operator Anthropic/Claude credential (~/.anthropic_key, ~/.claude/, or /tmp/.ptai-key). Agents never need to read these. If a target-side path coincidentally matches, rename it or handle it outside the agent."
fi

# Stages 2-3 apply to real commands only; a read-tool probe is a bare file path
# (no rm, no scanner), so skip them for ctx=read.
if [ "$ctx" != "read" ]; then

# --- Stage 2: catastrophic recursive delete of a protected path -------------
# Split the command into clauses (on ; & | newline) and, per clause, require ALL
# of: an `rm` word, a recursive flag, and a protected target token. Splitting
# first avoids cross-clause false positives (e.g. `rm -rf /tmp/x; cat /etc/x`).
# Boundaries allow a leading/trailing space or double-quote (single-quoted globs
# don't expand, so they are harmless); residual quoting tricks can evade — this
# is a guard, not a jail.
TARGETS='(^|[[:space:]"])(/|/\*|/engagements(/\*|/)?|~/?\*?|\$\{?HOME\}?/?\*?|/home/vagrant(/\*|/)?|/(bin|boot|dev|etc|lib|lib64|opt|proc|root|run|sbin|srv|sys|usr|var)(/\*|/)?)([[:space:]"]|$)'
hit=$(printf '%s\n' "$cmd" | tr ';&|\n' '\n\n\n\n' | while IFS= read -r clause; do
    printf '%s' "$clause" | grep -Eq '(^|[[:space:]]|/)rm([[:space:]]|$)'  || continue
    printf '%s' "$clause" | grep -Eq '(-[[:alnum:]]*[rR]|--recursive)'     || continue
    printf '%s' "$clause" | grep -Eq "$TARGETS"                            || continue
    echo HIT
done)
if [ -n "$hit" ]; then
    deny "Blocked by pt-ai guard: recursive delete targeting a protected path (filesystem root, a system dir, home, or the /engagements evidence root — a host bind). Delete a specific path under /engagements/<id>/ instead, or do bulk cleanup from the host."
fi

# --- Stage 3: OPSEC ceiling (PENDING #14) -----------------------------------
# Refuse a command noisier than the engagement's OPSEC ceiling. Ceiling source,
# in order: /engagements/.opsec_ceiling (operator-settable mid-engagement),
# $PT_AI_OPSEC_LIMIT, then MODERATE. Heuristic classifier: a signature list bumps
# to LOUD, passive recon to QUIET, everything else MODERATE. Shared by both
# front-ends (the Claude hook and the opencode plugin both run this script).
ceiling=""
if [ -r /engagements/.opsec_ceiling ]; then
    ceiling=$(tr -d '[:space:]' < /engagements/.opsec_ceiling 2>/dev/null)
fi
[ -z "$ceiling" ] && ceiling="${PT_AI_OPSEC_LIMIT:-MODERATE}"
ceiling=$(printf '%s' "$ceiling" | tr '[:lower:]' '[:upper:]')
_rank() { case "$1" in QUIET) echo 0 ;; LOUD) echo 2 ;; *) echo 1 ;; esac; }

noise="MODERATE"
case "$cmd" in
    *nikto*|*masscan*|*responder*|*sqlmap*|*wpscan*|*nuclei*|*enum4linux*|*hydra*|*medusa*|*ncrack*|*patator*|*crackmapexec*|*netexec*|*" nxc "*|*--script*|*" -sS"*|*" -sU"*|*--min-rate*)
        noise="LOUD" ;;
    *whois*|*" dig "*|*nslookup*|*" host "*|*subfinder*|*theHarvester*|*" amass "*|*crt.sh*)
        noise="QUIET" ;;
esac
if [ "$(_rank "$noise")" -gt "$(_rank "$ceiling")" ]; then
    deny "Blocked by pt-ai guard: OPSEC ceiling is $ceiling but this command classifies as $noise. Use a quieter alternative, or raise the ceiling for this step (e.g. 'echo $noise > /engagements/.opsec_ceiling', or export PT_AI_OPSEC_LIMIT=$noise)."
fi

fi  # end: ctx != read

# Nothing matched — defer to the normal permission flow.
exit 0
