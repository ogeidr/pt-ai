#!/usr/bin/env bash
# tools/build-plugin.sh — generate the pt-ai Claude Code plugin (install Option B)
# from the canonical sources. Vagrant (Option A) and the plugin are two derived
# artifacts of ONE source: agents/, skills/, vagrant/config/claude/hooks/.
#
# Transforms applied (see features/plugin-install-option.md):
#   T1  Bake shared agent blocks (mirror vagrant/provision/02-claude.sh:42-59):
#       append _scope-guard / _findings-store / _untrusted-output to any agent
#       missing them, so static plugin agents carry the same enforcement.
#   T2  Inline skills/_engagement-protocol.md into each engage-* skill (the VM
#       cat's it at /opt/pt-ai/...; that path is absent off-VM and a bang-preamble
#       cannot expand ${CLAUDE_PLUGIN_ROOT}).
#   T3  Rewrite the VM's absolute evidence root /engagements -> CWD-relative
#       "engagements" everywhere except pt-ai-guard.sh. Bang-preambles cannot
#       expand $PWD/~, so a literal relative path is the only portable form.
#   T4  pt-ai-guard.sh is copied verbatim; hooks.json adds a PreToolUse(Read)
#       matcher (authored in the static file, not here).
#
# Usage: tools/build-plugin.sh [OUT_DIR]   (default: <repo>/plugin)
# test/plugin-parity.sh builds to a temp dir and diffs the committed plugin/.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC_AGENTS="$REPO_ROOT/agents"
SRC_SKILLS="$REPO_ROOT/skills"
SRC_HOOKS="$REPO_ROOT/vagrant/config/claude/hooks"
SRC_STATIC="$REPO_ROOT/tools/plugin-static"
PROTOCOL="$SRC_SKILLS/_engagement-protocol.md"

OUT="${1:-$REPO_ROOT/plugin}"
AGENTS_OUT="$OUT/agents"
SKILLS_OUT="$OUT/skills"
HOOKS_OUT="$OUT/hooks"
MANIFEST_OUT="$OUT/.claude-plugin"

SCOPE_GUARD="$SRC_AGENTS/_scope-guard.md"
FINDINGS_STORE="$SRC_AGENTS/_findings-store.md"
UNTRUSTED_OUTPUT="$SRC_AGENTS/_untrusted-output.md"

for f in "$PROTOCOL" "$SCOPE_GUARD" "$FINDINGS_STORE" "$UNTRUSTED_OUTPUT"; do
    [ -r "$f" ] || { echo "build-plugin: missing source $f" >&2; exit 1; }
done

# T3: absolute VM evidence root -> CWD-relative. Applied to emitted markdown and
# the ROE hooks; NOT to pt-ai-guard.sh (its /engagements rm-protection stays
# absolute — see the plugin OPSEC note in the README).
ptrewrite() { sed 's#/engagements#engagements#g'; }

rm -rf "$OUT"
mkdir -p "$AGENTS_OUT" "$SKILLS_OUT" "$HOOKS_OUT" "$MANIFEST_OUT"

# --- T1: agents (bake shared blocks, then T3) ------------------------------
for src in "$SRC_AGENTS"/*.md; do
    fname=$(basename "$src")
    case "$fname" in _*) continue ;; esac   # _scope-guard / _findings-store / _untrusted-output are templates
    tmp="$AGENTS_OUT/$fname.tmp"
    cp "$src" "$tmp"
    if ! grep -qE "Authorization Verification|Scope Enforcement" "$tmp"; then
        printf '\n' >> "$tmp"; cat "$SCOPE_GUARD" >> "$tmp"
    fi
    if ! grep -q "Findings Store" "$tmp"; then
        printf '\n' >> "$tmp"; cat "$FINDINGS_STORE" >> "$tmp"
    fi
    if ! grep -q "Untrusted Tool Output" "$tmp"; then
        printf '\n' >> "$tmp"; cat "$UNTRUSTED_OUTPUT" >> "$tmp"
    fi
    ptrewrite < "$tmp" > "$AGENTS_OUT/$fname"
    rm -f "$tmp"
done

# --- T2 + T3: skills -------------------------------------------------------
# Copy each skill dir; for every .md, inline the shared protocol where the
# engage-* preamble cat's it, then apply the relative-path rewrite. Non-md
# supporting files (scripts, samples) are copied verbatim.
for dir in "$SRC_SKILLS"/*/; do
    name=$(basename "$dir")
    dst="$SKILLS_OUT/$name"
    mkdir -p "$dst"
    (cd "$dir" && find . -type f -print) | while IFS= read -r rel; do
        rel="${rel#./}"
        mkdir -p "$dst/$(dirname "$rel")"
        case "$rel" in
            *.md)
                # T2: replace the whole `!`cat /opt/pt-ai/.../_engagement-protocol.md ...``
                # preamble line with the protocol's literal text. Then strip the VM
                # absolute path from any remaining prose mention of the protocol file
                # (e.g. the /engagement orchestrator describes it), then T3.
                sed -e '\#cat /opt/pt-ai/skills/_engagement-protocol.md# {
                    r '"$PROTOCOL"'
                    d
                }' "$dir/$rel" \
                    | sed 's#/opt/pt-ai/skills/_engagement-protocol.md#_engagement-protocol.md#g' \
                    | ptrewrite > "$dst/$rel"
                ;;
            *)
                cp "$dir/$rel" "$dst/$rel"
                ;;
        esac
    done
done

# --- hooks -----------------------------------------------------------------
# pt-ai-guard.sh: single-source security gate, copied VERBATIM (its absolute
# /engagements rm-protection must not be rewritten). ROE hooks: T3-rewritten.
cp "$SRC_HOOKS/pt-ai-guard.sh" "$HOOKS_OUT/pt-ai-guard.sh"
for h in roe-session-start.sh roe-prompt-check.sh; do
    ptrewrite < "$SRC_HOOKS/$h" > "$HOOKS_OUT/$h"
done
chmod 0755 "$HOOKS_OUT"/*.sh

# --- static manifests (hand-authored, version-controlled) ------------------
cp "$SRC_STATIC/plugin.json"  "$MANIFEST_OUT/plugin.json"
cp "$SRC_STATIC/hooks.json"   "$HOOKS_OUT/hooks.json"
cp "$SRC_STATIC/README.md"    "$OUT/README.md"

# --- build-time invariants (fail the build, not the user) ------------------
# Nothing may reference the VM-only /opt/pt-ai path.
if grep -rIl '/opt/pt-ai' "$OUT" >/dev/null 2>&1; then
    echo "build-plugin: FAIL — /opt/pt-ai leaked into the plugin:" >&2
    grep -rIn '/opt/pt-ai' "$OUT" >&2; exit 1
fi
# The absolute evidence root may survive ONLY in pt-ai-guard.sh (its rm-protection
# stays absolute) and the hand-authored README (which contrasts VM vs plugin paths).
leak=$(grep -rIl '/engagements' "$OUT" 2>/dev/null | grep -vE '/hooks/pt-ai-guard\.sh$|/README\.md$' || true)
if [ -n "$leak" ]; then
    echo "build-plugin: FAIL — absolute /engagements leaked (should be CWD-relative):" >&2
    echo "$leak" >&2; exit 1
fi

echo "build-plugin: wrote $OUT"
echo "  agents: $(find "$AGENTS_OUT" -name '*.md' | wc -l | tr -d ' ')  skills: $(find "$SKILLS_OUT" -name SKILL.md | wc -l | tr -d ' ')  hooks: $(ls "$HOOKS_OUT" | wc -l | tr -d ' ')"
