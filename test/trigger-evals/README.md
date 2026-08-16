# Trigger evals — disasm skill pair

Trigger-accuracy fixtures for the two competing disassembly skills, `disasm-ghidra-rpc`
(interactive / step-by-step / patch / diff) and `disasm-ghidrasql` (relational / bulk /
ranking / joins / set-based edits). Their descriptions are near-identical except for that
axis, so these sets measure whether each description fires on its own queries and stays off
the other's.

Each file is a list of `{ "query": ..., "should_trigger": bool }`. Every skill's
`should_trigger: false` set includes the *other* skill's ideal queries plus genuine
near-misses (network recon on port 8081 — ghidrasql's own port —, C-source review, runtime
sandboxing, memory-dump carving, pcap extraction, JS "decompile", report/severity, CVE
lookup).

## Running

These use skill-creator's `run_eval`, which registers the skill as a command and fires
`claude -p` per query (nested Claude sessions — consumes real quota). Run **serially**:
`--num-workers 1`. Parallel runs (`--num-workers 10`) are unreliable here and collapse recall
to ~0 (a harness artifact, not a description problem).

```sh
SC="$HOME/.claude/plugins/marketplaces/anthropic-agent-skills/skills/skill-creator"
REPO="$(git rev-parse --show-toplevel)"
# run_eval finds its project root by walking up for a .claude/ dir; run from an isolated
# throwaway dir so it never writes command files into your real ~/.claude.
WORK="$(mktemp -d)"; mkdir -p "$WORK/.claude"; cd "$WORK"

for skill in disasm-ghidra-rpc disasm-ghidrasql; do
  PYTHONPATH="$SC" python3 -m scripts.run_eval \
    --eval-set "$REPO/test/trigger-evals/$skill.json" \
    --skill-path "$REPO/skills/$skill" \
    --runs-per-query 2 --num-workers 1 --timeout 120 --model claude-opus-4-8 --verbose
done
```

`--model` should match the model that actually powers pt-ai sessions so triggering reflects
what users experience.

## Caveat

`run_eval` tests one skill in isolation, so a `false` query that "fires" only means that skill
triggers when it is the *only* one available — not that it wins head-to-head (both skills are
present in reality). Treat the numbers as per-description precision/recall, not a bake-off.

## Baseline (2026-08-05, model claude-opus-4-8, serial, 1 rep)

| skill | recall (should-fire) | precision (near-miss stayed off) |
|---|---|---|
| disasm-ghidrasql | 6/6 | 11/11 |
| disasm-ghidra-rpc | 5/6 | 9/11 |

ghidrasql was clean. ghidra-rpc's one miss was a single-draw flake (the same query fired in a
separate check), and its two false fires were ghidrasql-domain bulk queries that ghidra-rpc's
description already defers ("prefer /disasm-ghidrasql for bulk/relational") and that ghidrasql
wins outright. Conclusion at the time: descriptions in good shape, no wording change applied.
Re-run these if either description is edited.
