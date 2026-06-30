---
name: engage-detect
description: >
  Run the Detection-engineering phase (Phase 7) of an operator-gated
  penetration-test engagement by delegating to detection-engineer and threat-modeler
  with a per-delegation scope envelope. Invoke after /engage-exploit completes.
  Claude Code only — the automated fan-out needs the Task tool, which opencode lacks.
disable-model-invocation: false
allowed-tools: Bash, Read, Write, Task
---

## Current scope for this engagement

!`cat /engagements/scope.md 2>/dev/null || echo "No scope declared yet. Run /scope-declare then /engagement before this phase."`

## Engagement delegation protocol (shared, authoritative)

!`cat /opt/pt-ai/skills/_engagement-protocol.md 2>/dev/null || echo "⚠ Shared engagement protocol missing at /opt/pt-ai/skills/_engagement-protocol.md — STOP and re-provision before delegating."`

## This phase

You are the **Detection engineering** phase (Phase 7 of the 0–9 lifecycle in
`docs/AGENT-GUIDE.md`). Follow the shared protocol above for state re-resolution,
the authorized-agent check, the delegation envelope, conflict resolution, and
findings propagation.

**Entry gate:** an `"phase":"exploitation","status":"complete"` line exists in
`ENGAGEMENT_DIR/gates.jsonl`:
```sh
grep -q '"phase":"exploitation","status":"complete"' "<ENGAGEMENT_DIR>/gates.jsonl" && echo GO || echo "NO-GO"
```
NO-GO → STOP and tell the operator to complete exploitation with `/engage-exploit`
first.

**Agents (if on the authorized list):** `detection-engineer`, `threat-modeler`.
Turn the confirmed exploitation chains into detections/mitigations and update the
threat model. Read `ENGAGEMENT_DIR/findings.jsonl` to ground the work in what was
actually confirmed.

**On completion:**

1. Present a detection summary (detections authored, gaps) to the operator.
2. Append the completion line (operator approves the Bash call):
   ```sh
   printf '%s\n' '{"engagement":"<id>","phase":"detection","status":"complete","ts":"'"$(date -u +%Y-%m-%dT%H:%M:%SZ)"'","by":"engage-detect"}' >> "<ENGAGEMENT_DIR>/gates.jsonl"
   ```
3. Tell the operator the next phase is **Reporting** — run `/engage-report`. Do not
   auto-advance.
