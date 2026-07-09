#!/usr/bin/env bash
# test/plugin-validate.sh — structural validation of the committed plugin/ tree.
# Catches what build + parity do not: malformed manifests, broken frontmatter, a
# non-executable hook, a drifted guard, or a wrong component count. Runs against
# the COMMITTED plugin/ (no rebuild), so it is meaningful even on a bare checkout.
#
# Exit 0 = all checks pass. Exit 1 = at least one failed.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PLUGIN="$REPO_ROOT/plugin"
SRC_AGENTS="$REPO_ROOT/agents"
SRC_SKILLS="$REPO_ROOT/skills"
SRC_GUARD="$REPO_ROOT/vagrant/config/claude/hooks/pt-ai-guard.sh"

pass=0; fail=0
ok(){ printf '  \033[32mPASS\033[0m %s\n' "$1"; pass=$((pass+1)); }
no(){ printf '  \033[31mFAIL\033[0m %s\n' "$1"; fail=$((fail+1)); }

echo "== plugin-validate =="

[ -d "$PLUGIN" ] || { no "plugin/ tree missing (run tools/build-plugin.sh)"; echo; echo "plugin-validate: FAIL"; exit 1; }

# --- manifests are valid JSON ---------------------------------------------
for j in "$PLUGIN/.claude-plugin/plugin.json" "$PLUGIN/hooks/hooks.json" "$REPO_ROOT/.claude-plugin/marketplace.json"; do
    if [ -r "$j" ] && jq empty "$j" >/dev/null 2>&1; then ok "valid JSON: ${j#$REPO_ROOT/}"
    else no "invalid/missing JSON: ${j#$REPO_ROOT/}"; fi
done

# --- component counts derived from source (not hardcoded) ------------------
exp_agents=$(find "$SRC_AGENTS" -maxdepth 1 -name '*.md' ! -name '_*' | wc -l | tr -d ' ')
got_agents=$(find "$PLUGIN/agents" -maxdepth 1 -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
[ "$got_agents" = "$exp_agents" ] && ok "agent count $got_agents == source $exp_agents" || no "agent count $got_agents != source $exp_agents"

exp_skills=$(find "$SRC_SKILLS" -maxdepth 2 -name SKILL.md | wc -l | tr -d ' ')
got_skills=$(find "$PLUGIN/skills" -maxdepth 2 -name SKILL.md 2>/dev/null | wc -l | tr -d ' ')
[ "$got_skills" = "$exp_skills" ] && ok "skill count $got_skills == source $exp_skills" || no "skill count $got_skills != source $exp_skills"

# --- frontmatter opens with --- on every agent + skill ---------------------
fm_bad=0
for f in "$PLUGIN"/agents/*.md "$PLUGIN"/skills/*/SKILL.md; do
    [ -r "$f" ] || continue
    IFS= read -r first < "$f"
    [ "$first" = "---" ] || { no "frontmatter missing: ${f#$PLUGIN/}"; fm_bad=1; }
done
[ "$fm_bad" -eq 0 ] && ok "all agents + skills open with '---' frontmatter"

# --- hook scripts present + executable -------------------------------------
hk_bad=0
for s in pt-ai-guard.sh roe-session-start.sh roe-prompt-check.sh; do
    [ -x "$PLUGIN/hooks/$s" ] || { no "hook not executable/missing: hooks/$s"; hk_bad=1; }
done
[ "$hk_bad" -eq 0 ] && ok "all 3 hook scripts present + executable"

# --- guard shipped byte-identical to its single source ---------------------
if diff -q "$SRC_GUARD" "$PLUGIN/hooks/pt-ai-guard.sh" >/dev/null 2>&1; then
    ok "pt-ai-guard.sh byte-identical to source (verbatim copy)"
else
    no "pt-ai-guard.sh differs from source — must be a verbatim copy"
fi

# --- no VM-only paths leaked (independent of the build's own invariant) -----
if grep -rIl '/opt/pt-ai' "$PLUGIN" >/dev/null 2>&1; then
    no "/opt/pt-ai path leaked into plugin/"; else ok "no /opt/pt-ai paths in plugin/"; fi
absleak=$(grep -rIl '/engagements' "$PLUGIN" 2>/dev/null | grep -vE '/hooks/pt-ai-guard\.sh$|/README\.md$' || true)
[ -z "$absleak" ] && ok "no stray absolute /engagements (CWD-relative)" || no "absolute /engagements in: $absleak"

echo
if [ "$fail" -eq 0 ]; then echo "plugin-validate: OK ($pass checks)"; exit 0; fi
echo "plugin-validate: FAIL ($fail failed, $pass passed)" >&2; exit 1
