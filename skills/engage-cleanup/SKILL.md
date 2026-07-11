---
name: engage-cleanup
description: >
  Run the post-engagement Cleanup & deconfliction step of an operator-gated
  penetration-test engagement by delegating to cleanup-deconfliction with a
  per-delegation scope envelope. Invoke after /engage-exploit completes, to inventory
  and remove tester-introduced artifacts before reporting. Claude Code only — the
  automated fan-out needs the Task tool, which opencode lacks.
disable-model-invocation: false
allowed-tools: Bash, Read, Write, Task
---

## Current scope for this engagement

!`cat /engagements/scope.md 2>/dev/null || echo "No scope declared yet. Run /scope-declare then /engagement before this phase."`

## Engagement delegation protocol (shared, authoritative)

!`cat /opt/pt-ai/skills/_engagement-protocol.md 2>/dev/null || echo "⚠ Shared engagement protocol missing at /opt/pt-ai/skills/_engagement-protocol.md — STOP and re-provision before delegating."`

## This phase

You are the **Cleanup & deconfliction** step (post-exploitation, before reporting, in
the 0–9 lifecycle in `docs/AGENT-GUIDE.md`). Follow the shared protocol above for
state re-resolution, the authorized-agent check, the delegation envelope, conflict
resolution, and findings propagation.

**Entry gate:** an `"phase":"exploitation","status":"complete"` line exists in
`ENGAGEMENT_DIR/gates.jsonl`:
```sh
grep -q '"phase":"exploitation","status":"complete"' "<ENGAGEMENT_DIR>/gates.jsonl" && echo GO || echo "NO-GO"
```
NO-GO → STOP and tell the operator to complete exploitation with `/engage-exploit`
first. This step runs after post-exploitation and does not block `/engage-detect`;
detection engineering may proceed in parallel.

**Agent (if on the authorized list):** `cleanup-deconfliction`. It is **advisory** —
it reads `ENGAGEMENT_DIR/findings.jsonl` and the evidence directory and produces two
outputs: an operator removal checklist and a client-facing deconfliction log. It
never deletes or reverts anything itself; each removal is an operator action taken
under Claude Code's approval prompt. Do not delegate any agent that composes
destructive commands here.

**On completion:**

1. Present the removal checklist and the deconfliction log to the operator, and
   confirm which items the operator actually removed.
2. Append the completion line (operator approves the Bash call):
   ```sh
   printf '%s\n' '{"engagement":"<id>","phase":"cleanup","status":"complete","ts":"'"$(date -u +%Y-%m-%dT%H:%M:%SZ)"'","by":"engage-cleanup"}' >> "<ENGAGEMENT_DIR>/gates.jsonl"
   ```
3. Tell the operator the next phase is **Detection engineering** (`/engage-detect`)
   if not already done, then **Reporting** (`/engage-report`). Do not auto-advance.
