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
#   T5  Rewrite bundled-script paths in skill sh-blocks from the VM absolute
#       /opt/pt-ai/skills/... to ${CLAUDE_PLUGIN_ROOT}/skills/... (the plugin's
#       own file-location convention, same as hooks.json). Applied AFTER T2 has
#       removed the protocol bang-preambles, so it only touches sh-block script
#       calls (e.g. severity-calibrate's cvss.sh), never a bang-preamble.
#
# Precondition: vagrant/config/claude/hooks/ must be clean in git. Those files are
# executed by the HOST after the build, so an uncommitted change there halts the
# build (reviews/PENDING.md #21). Override with PTAI_ALLOW_DIRTY_HOOKS=1 for your
# own in-progress edits.
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

# --- tamper tripwire on the hook sources (reviews/PENDING.md #21) -----------
# All three files in vagrant/config/claude/hooks/ are copied into plugin/hooks/
# below, where the HOST's Claude Code executes them on every Bash and Read tool
# call. Until #21 fix 4, that directory sat inside the guest's READ-WRITE /vagrant
# share, making "guest writes a file -> host executes it" a two-step chain with no
# human in the middle. The guest can no longer write it — vagrant/config is now a
# one-way root-owned rsync push — so this is DEFENCE IN DEPTH, not the boundary.
# It still earns its keep: it catches host-side accidents and any future
# re-widening of the share, and it makes shipping a hook change an explicit,
# reviewable act.
#
# Why git is a sound check against a guest-side threat: the guest reaches neither
# this script (tools/) nor .git/ — both are siblings of vagrant/ and were never in
# the share — so it could never disable the tripwire or forge a clean status.
#
# It is a tripwire, not a boundary: it detects an unreviewed change, it does not
# prevent one. Commit the change (which makes it reviewable), or set
# PTAI_ALLOW_DIRTY_HOOKS=1 to build anyway.
if [ "${PTAI_ALLOW_DIRTY_HOOKS:-0}" = "1" ]; then
    echo "build-plugin: WARNING — hook tamper check SKIPPED (PTAI_ALLOW_DIRTY_HOOKS=1)" >&2
elif ! command -v git >/dev/null 2>&1 || ! git -C "$REPO_ROOT" rev-parse --git-dir >/dev/null 2>&1; then
    # No git, or not a checkout (e.g. a tarball build). The threat model needs a
    # guest attached to a repo, so this is not fatal — but say so rather than
    # letting the caller assume they were protected.
    echo "build-plugin: WARNING — no git checkout; hook tamper check NOT performed" >&2
else
    hook_dirty=$(git -C "$REPO_ROOT" status --porcelain -- vagrant/config/claude/hooks/ 2>/dev/null || true)
    if [ -n "$hook_dirty" ]; then
        echo "build-plugin: FAIL — hook sources differ from the committed tree:" >&2
        printf '%s\n' "$hook_dirty" >&2
        echo "  These are copied into plugin/hooks/ and executed by the HOST on every" >&2
        echo "  tool call. Review the diff, then either commit it or re-run with" >&2
        echo "  PTAI_ALLOW_DIRTY_HOOKS=1 if the change is yours and intentional." >&2
        exit 1
    fi
fi

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
# Copy each skill dir; for every .md, inline each shared _*.md sibling where a
# bang-preamble cat's it (protocol, disasm-common, …), then apply the
# relative-path rewrite. Non-md supporting files (scripts, samples) are copied
# verbatim. Build the inline/relativize sed programs once from the _*.md set:
INLINE_SED=()
RELPATH_SED=()
for sf in "$SRC_SKILLS"/_*.md; do
    bn=$(basename "$sf")
    INLINE_SED+=( -e '\#cat /opt/pt-ai/skills/'"$bn"'#{
        r '"$sf"'
        d
    }' )
    RELPATH_SED+=( -e 's#/opt/pt-ai/skills/'"$bn"'#'"$bn"'#g' )
done
for dir in "$SRC_SKILLS"/*/; do
    name=$(basename "$dir")
    dst="$SKILLS_OUT/$name"
    mkdir -p "$dst"
    (cd "$dir" && find . -type f -print) | while IFS= read -r rel; do
        rel="${rel#./}"
        mkdir -p "$dst/$(dirname "$rel")"
        case "$rel" in
            *.md)
                # T2: replace each `!`cat /opt/pt-ai/.../_<shared>.md ...`` preamble line
                # with that file's literal text. Then strip the VM absolute path from any
                # remaining prose mention of a shared file (e.g. the /engagement
                # orchestrator describes the protocol). Then T5 (sh-block script paths ->
                # ${CLAUDE_PLUGIN_ROOT}) and T3.
                sed "${INLINE_SED[@]}" "$dir/$rel" \
                    | sed "${RELPATH_SED[@]}" \
                    | sed 's#/opt/pt-ai/skills#${CLAUDE_PLUGIN_ROOT}/skills#g' \
                    | ptrewrite > "$dst/$rel"
                ;;
            *)
                cp "$dir/$rel" "$dst/$rel"
                ;;
        esac
    done
done
# Bundled skill scripts are invoked directly by their SKILL.md (not via `sh`), so the
# exec bit is load-bearing. `cp` above preserves it, but a checkout with
# core.fileMode=false does not — and plugin-parity's `diff -ru` is mode-blind, so
# nothing else would notice. `find -exec` rather than a glob: under `set -e` an
# unmatched glob would abort the build the day no skill ships a script.
find "$SKILLS_OUT" -type f -name '*.sh' -exec chmod 0755 {} +

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
