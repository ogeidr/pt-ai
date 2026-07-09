#!/bin/sh
# roe-session-start.sh — Claude Code SessionStart hook (PENDING #19).
#
# Surfaces the committed engagement scope/ROE from disk so authorization is loaded
# from the artifact, not retyped each session. Plain stdout is added to the session
# context by Claude Code. SessionStart cannot block — it only injects context.
#
# The companion UserPromptSubmit hook (roe-prompt-check.sh) re-asserts ROE presence
# per prompt; the hard action-gate is the scope-guard prompt + pt-ai-guard.sh.

if [ -r engagements/scope.md ]; then
    echo "## Engagement scope (loaded from engagements/scope.md)"
    cat engagements/scope.md
    echo
fi

found=0
for f in engagements/roe.txt engagements/*/roe.txt; do
    [ -r "$f" ] || continue
    echo "Authorization (ROE) artifact on file: $f"
    found=1
done

if [ "$found" -eq 0 ]; then
    echo "Note: no committed ROE artifact (engagements/roe.txt or engagements/{id}/roe.txt) is on file yet. A committed ROE is preferred for the audit trail, but the operator's confirmation of authorization for the declared scope is sufficient to proceed; without either, stay in advisory mode."
fi

exit 0
