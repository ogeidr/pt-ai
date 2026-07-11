---
name: engage-vuln
description: >
  Run the Vulnerability-assessment phase (Phase 3) of an operator-gated
  penetration-test engagement by delegating to vuln-scanner then poc-validator with
  a per-delegation scope envelope. Invoke after /engage-recon completes. Claude Code
  only — the automated fan-out needs the Task tool, which opencode does not provide.
disable-model-invocation: false
allowed-tools: Bash, Read, Write, Task
---

## Current scope for this engagement

!`cat /engagements/scope.md 2>/dev/null || echo "No scope declared yet. Run /scope-declare then /engagement before this phase."`

## Engagement delegation protocol (shared, authoritative)

!`cat /opt/pt-ai/skills/_engagement-protocol.md 2>/dev/null || echo "⚠ Shared engagement protocol missing at /opt/pt-ai/skills/_engagement-protocol.md — STOP and re-provision before delegating."`

## This phase

You are the **Vulnerability assessment** phase (Phase 3 of the 0–9 lifecycle in
`docs/AGENT-GUIDE.md`). Follow the shared protocol above for state re-resolution,
the authorized-agent check, the delegation envelope, conflict resolution, and
findings propagation.

**Entry gate:** a `"phase":"recon","status":"complete"` line exists in
`ENGAGEMENT_DIR/gates.jsonl`:
```sh
grep -q '"phase":"recon","status":"complete"' "<ENGAGEMENT_DIR>/gates.jsonl" && echo GO || echo "NO-GO"
```
NO-GO → STOP and tell the operator to complete recon with `/engage-recon` first.

**Agents (if on the authorized list):** `vuln-scanner` → `poc-validator`, plus
`sast-sca` when the engagement covers source code, dependencies, or images. Delegate
`vuln-scanner` to assess in-scope surface (and `sast-sca` to review pasted or
readable source/dependency inventories — advisory, no scanning of targets), then
`poc-validator` to confirm or demote candidate findings. Apply the conflict-resolution
rules (PoC wins) from the shared protocol. This phase is assessment, not exploitation
— no exploit delivery.

Read `ENGAGEMENT_DIR/findings.jsonl` to build the summary.

**On completion:**

1. Present a vuln summary (confirmed vs theoretical findings) to the operator.
2. Append the completion line (operator approves the Bash call):
   ```sh
   printf '%s\n' '{"engagement":"<id>","phase":"vuln","status":"complete","ts":"'"$(date -u +%Y-%m-%dT%H:%M:%SZ)"'","by":"engage-vuln"}' >> "<ENGAGEMENT_DIR>/gates.jsonl"
   ```
3. Tell the operator the next phase is **Exploitation**, which is behind a **hard
   gate** — run `/engage-exploit`. Do not auto-advance and do not record any
   exploitation approval here; only the operator may approve exploitation.
