# Trigger evals

Trigger-accuracy fixtures for the skills whose descriptions have to win — or deliberately
lose — against a near neighbour.

## The disasm pair

Fixtures for the two competing disassembly skills, `disasm-ghidra-rpc`
(interactive / step-by-step / patch / diff) and `disasm-ghidrasql` (relational / bulk /
ranking / joins / set-based edits). Their descriptions are near-identical except for that
axis, so these sets measure whether each description fires on its own queries and stays off
the other's.

Each file is a list of `{ "query": ..., "should_trigger": bool }`. Every skill's
`should_trigger: false` set includes the *other* skill's ideal queries plus genuine
near-misses (network recon on port 8081 — ghidrasql's own port —, C-source review, runtime
sandboxing, memory-dump carving, pcap extraction, JS "decompile", report/severity, CVE
lookup).

## codemap-ripwire

`codemap-ripwire` (source navigation via ripwire) shares the "analyse a thing the client
gave us" space with the disasm pair, and the split it must hold is **source vs compiled
binary**. Its `should_trigger: false` set therefore carries both disasm skills' ideal
queries plus the same shared near-misses, and two that are specific to it:

- **"does the app leak source maps at /static/js/*.js.map"** — `.map` files are a real
  web-recon target and an established meaning of "source map". The skill was renamed
  *away* from `source-map` for exactly this reason; the query is kept as the regression
  test for that decision.
- **"decompile this obfuscated JavaScript bundle and tell me what the token-signing logic
  does"** — the hardest case in the set, and the one to argue about first. It is JS source,
  which ripwire parses, so a keyword match says fire. It is scored `false` because a
  minified bundle is one enormous line with no symbol structure to rank, and the ask is
  semantic ("what does it do"), not locational ("where is it"). If a run shows this firing
  and the operator judges that acceptable, flip it rather than reword the description.

The skill landed 2026-09-25, so this set is now runnable. It was committed ahead of the
skill on purpose: fixing the target before writing the description stops the eval set being
tuned to whatever the description happens to do.

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

for skill in disasm-ghidra-rpc disasm-ghidrasql codemap-ripwire; do
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
| codemap-ripwire | — | — (skill landed 2026-09-25; not yet run) |

ghidrasql was clean. ghidra-rpc's one miss was a single-draw flake (the same query fired in a
separate check), and its two false fires were ghidrasql-domain bulk queries that ghidra-rpc's
description already defers ("prefer /disasm-ghidrasql for bulk/relational") and that ghidrasql
wins outright. Conclusion at the time: descriptions in good shape, no wording change applied.
Re-run these if either description is edited.

**Re-run the disasm pair when `codemap-ripwire` lands.** A third skill in the same space
can pull their negatives, and the 2026-08-05 numbers above were measured with only two
skills in existence. The line below that table already says to re-run on a description
edit; adding a neighbour is the same kind of change.
