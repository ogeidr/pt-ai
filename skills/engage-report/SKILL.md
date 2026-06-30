---
name: engage-report
description: >
  Run the Reporting and compliance phase (Phases 8–9) of an operator-gated
  penetration-test engagement: run /severity-calibrate over the findings store, then
  delegate report-generator (+stig-analyst). Invoke after /engage-detect completes.
  Claude Code only — the automated fan-out needs the Task tool, which opencode lacks.
disable-model-invocation: false
allowed-tools: Bash, Read, Write, Task
---

## Current scope for this engagement

!`cat /engagements/scope.md 2>/dev/null || echo "No scope declared yet. Run /scope-declare then /engagement before this phase."`

## Engagement delegation protocol (shared, authoritative)

!`cat /opt/pt-ai/skills/_engagement-protocol.md 2>/dev/null || echo "⚠ Shared engagement protocol missing at /opt/pt-ai/skills/_engagement-protocol.md — STOP and re-provision before delegating."`

## This phase

You are the **Reporting & compliance** phase (Phases 8–9 of the 0–9 lifecycle in
`docs/AGENT-GUIDE.md`). Follow the shared protocol above for state re-resolution,
the authorized-agent check, the delegation envelope, conflict resolution, and
findings propagation.

**Entry gate:** a `"phase":"detection","status":"complete"` line exists in
`ENGAGEMENT_DIR/gates.jsonl`, and the operator approves starting reporting:
```sh
grep -q '"phase":"detection","status":"complete"' "<ENGAGEMENT_DIR>/gates.jsonl" && echo GO || echo "NO-GO"
```
NO-GO → STOP and tell the operator to complete detection with `/engage-detect`
first.

**Step 1 — Calibrate first (do not skip).** Run the `/severity-calibrate` skill over
the findings store. It marks each finding's exploitation state and recomputes
severity from the CVSS temporal score (deflate-only) so unexploited/version-only
findings are not over-rated. `/severity-calibrate` is a **skill**, invoked directly
— it is not delegated via `Task`.

**Step 2 — Generate the report.** Delegate `report-generator` (if on the authorized
list) to read the collapsed, calibrated store and render the deliverable, showing
the calibrated `severity`/`cvss_temporal` and the Theoretical-vs-Confirmed labels.
Add `stig-analyst` when the engagement type calls for STIG/compliance output. An
uncalibrated report re-rates findings off the worst-case CVE base — calibrate first.

**On completion:**

1. Present the deliverable location and a findings rollup to the operator.
2. Append the completion line (operator approves the Bash call):
   ```sh
   printf '%s\n' '{"engagement":"<id>","phase":"reporting","status":"complete","ts":"'"$(date -u +%Y-%m-%dT%H:%M:%SZ)"'","by":"engage-report"}' >> "<ENGAGEMENT_DIR>/gates.jsonl"
   ```
3. The engagement lifecycle is complete.
