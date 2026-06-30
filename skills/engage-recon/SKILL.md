---
name: engage-recon
description: >
  Run the Reconnaissance phase (Phase 2) of an operator-gated penetration-test
  engagement by delegating to the recon specialists with a per-delegation scope
  envelope. Invoke after /engagement has initialized the engagement. Claude Code
  only — the automated fan-out needs the Task tool, which opencode does not provide.
disable-model-invocation: false
allowed-tools: Bash, Read, Write, Task
---

## Current scope for this engagement

!`cat /engagements/scope.md 2>/dev/null || echo "No scope declared yet. Run /scope-declare then /engagement before this phase."`

## Engagement delegation protocol (shared, authoritative)

!`cat /opt/pt-ai/skills/_engagement-protocol.md 2>/dev/null || echo "⚠ Shared engagement protocol missing at /opt/pt-ai/skills/_engagement-protocol.md — STOP and re-provision before delegating."`

## This phase

You are the **Reconnaissance** phase (Phase 2 of the 0–9 lifecycle in
`docs/AGENT-GUIDE.md`). Follow the shared protocol above for state re-resolution,
the authorized-agent check, the delegation envelope, conflict resolution, and
findings propagation.

**Entry gate:** the `"phase":"init"` line exists in `ENGAGEMENT_DIR/gates.jsonl`
(written by `/engagement`). If it is missing, STOP and tell the operator to run
`/engagement` first.

**Agents (if on the authorized list):** `recon-advisor`, `osint-collector`,
`web-hunter`. For a broad multi-host or AWS-sourced first pass you may invoke the
`/full-recon` skill and have `recon-advisor` analyze the surface it returns. This is
read-only toward targets — no exploitation.

Independent recon agents may be delegated back-to-back within this phase. Read
`ENGAGEMENT_DIR/findings.jsonl` between delegations to build the summary.

**On completion:**

1. Present a recon summary (attack surface, prioritized targets) to the operator.
2. Append the completion line (operator approves the Bash call):
   ```sh
   printf '%s\n' '{"engagement":"<id>","phase":"recon","status":"complete","ts":"'"$(date -u +%Y-%m-%dT%H:%M:%SZ)"'","by":"engage-recon"}' >> "<ENGAGEMENT_DIR>/gates.jsonl"
   ```
3. Tell the operator the next phase is **Vulnerability assessment** — run
   `/engage-vuln`. Do not auto-advance.
