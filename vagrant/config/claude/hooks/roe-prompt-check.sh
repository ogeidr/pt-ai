#!/bin/sh
# roe-prompt-check.sh — Claude Code UserPromptSubmit hook (PENDING #19).
#
# Injects ground-truth ROE presence (read from disk, not the conversation) on every
# prompt, so the scope-guard can't be talked or injected into "you already
# authorized". NON-BLOCKING by design: it adds context, never erases the prompt.
# A hard block-until-ROE would deadlock bootstrap (the operator could not even set
# up the engagement). The hard action-gate remains the scope-guard prompt + the
# PreToolUse credential/delete/OPSEC guard (pt-ai-guard.sh).

roe_present() {
    for f in /engagements/roe.txt /engagements/*/roe.txt; do
        [ -r "$f" ] && return 0
    done
    return 1
}

if roe_present; then
    msg="A committed ROE artifact is present on disk; proceed within the declared scope."
else
    msg="No committed ROE artifact on disk (/engagements/roe.txt). A committed ROE is preferred, but operator-confirmed authorization for the declared scope is sufficient to proceed; without either, stay in advisory mode."
fi

# additionalContext only (no decision:block). msg contains no quotes/backslashes,
# so it is safe to embed directly in the JSON string.
printf '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"%s"}}\n' "$msg"
exit 0
