---
name: engagement
description: >
  Initialize an operator-gated penetration-test engagement and print the per-phase
  skill sequence. Confirms scope, authorization, and the authorized agent set, then
  records the init state in gates.jsonl. Run /scope-declare first; then run the
  /engage-* phase skills in order. Claude Code only — the per-phase fan-out needs the
  Task tool, which opencode does not provide.
disable-model-invocation: false
allowed-tools: Bash, Read, Write
---

## Active engagement pointer

!`cat /engagements/scope.md 2>/dev/null || echo "No scope declared yet. Run /scope-declare before /engagement."`

## What this skill is (and is not)

You are the **engagement initializer and overview**. You do **not** run the phases
yourself — each phase is a separate operator-invoked skill (`/engage-recon`,
`/engage-vuln`, `/engage-exploit`, `/engage-detect`, `/engage-report`) that does its
own `Task` fan-out and reconstructs state from disk. Making each phase boundary an
explicit human action (invoking the next skill) is what hardens the recon →
exploitation gate.

This engagement is **operator-gated, not autonomous.** Every phase transition is an
operator decision, and every Bash command a subagent composes still hits Claude
Code's per-command permission prompt and the `pt-ai-guard.sh` hook. Those remain the
hard boundary; the phase skills add disciplined, state-backed sequencing on top.

The cross-phase delegation rules (scope envelope, cold-context handling, conflict
resolution, findings propagation, `gates.jsonl` format) live in one authoritative
file — `/opt/pt-ai/skills/_engagement-protocol.md` — which every phase skill loads in
its preamble. Do not duplicate them here.

---

## Step 1 — Initialize the engagement

1. **Resolve scope.** Read `/engagements/scope.md` (the pointer shown above). If it
   says no scope is declared, STOP and tell the operator to run `/scope-declare`.
   Extract the `Evidence directory:` value — call it `ENGAGEMENT_DIR`. Then read the
   canonical record `ENGAGEMENT_DIR/scope.md` to get the engagement id, type, scope
   summary, and authorization status. Do not proceed unless authorization is `yes`.

2. **Confirm the authorized agent set (PENDING #3 — Session-Init record).** Present
   the agents appropriate to the engagement type and ask the operator to confirm or
   restrict them. Anything not on the confirmed list is refused for the rest of the
   session — the phase skills re-read this list from the init line below. Defaults by
   type (trim to what the RoE actually covers):
   - external / internal / web → `recon-advisor, osint-collector, web-hunter, vuln-scanner, poc-validator, attack-planner, exploit-chainer, privesc-advisor, detection-engineer, severity-calibrate, report-generator`
   - cloud → add `cloud-security`; AD-heavy → add `ad-attacker, credential-tester`
   - **High-authorization vectors are OFF by default** and require their own explicit
     written authorization before you add them: `social-engineer`, `wireless-pentester`,
     `mobile-pentester`, `exploit-guide`.

3. **Record init state.** Append one line to `ENGAGEMENT_DIR/gates.jsonl` (operator
   will approve the Bash call). Use the concrete path you resolved:
   ```sh
   printf '%s\n' '{"engagement":"<id>","phase":"init","status":"declared","authorized_agents":["recon-advisor","..."],"scope":"<summary>","ts":"'"$(date -u +%Y-%m-%dT%H:%M:%SZ)"'","by":"engagement"}' >> "<ENGAGEMENT_DIR>/gates.jsonl"
   ```

4. **Show the plan.** Present the phase sequence below and tell the operator to run
   `/engage-recon` to begin Phase 2. Do not auto-advance.

---

## Phase sequence (operator invokes each in order)

Phase numbers mirror the 0–9 lifecycle in `docs/AGENT-GUIDE.md`. Phases 0–1 (threat
modeling, planning & scoping) are pre-engagement — handled before this skill via
`/scope-declare` and the planning agents. Each phase skill checks its own entry gate
from `gates.jsonl`, fans out, appends its completion line, and names the next skill.

| Skill | Phase | Agents (if authorized) | Entry gate |
|---|---|---|---|
| `/engagement` *(here)* | Step 1 init | — | scope declared + authorization = yes |
| `/engage-recon` | 2. Reconnaissance | recon-advisor, osint-collector, web-hunter (may invoke `/full-recon`) | init recorded |
| `/engage-vuln` | 3. Vulnerability assessment | vuln-scanner → poc-validator | recon complete |
| `/engage-exploit` | 4–6. Exploitation + post-ex | attack-planner, exploit-chainer, privesc-advisor (+ad/cloud/cred) | **HARD GATE** (recon complete + exploitation approved, read from disk) |
| `/engage-detect` | 7. Detection engineering | detection-engineer, threat-modeler | post-ex complete |
| `/engage-report` | 8–9. Reporting & compliance | **/severity-calibrate** → report-generator (+stig-analyst) | detection complete + operator approves |

`/engage-exploit` is **operator-invocation only** (`disable-model-invocation: true`)
and reads the gate fresh from `gates.jsonl`, so the recon → exploitation transition
cannot be reached without an operator-recorded approval line — even from a cold
session.

---

## Limits (state them; do not paper over)

- **Claude Code only.** opencode has no Task tool; there is no automated fan-out
  there — run the phase skills as manual one-agent-at-a-time playbooks.
- The envelope and gates are **state-backed discipline, not a sandbox.** The hard
  boundary remains the per-command permission prompt + `pt-ai-guard.sh` + (when
  shipped) the host egress allowlist. The engagement is operator-gated by design.
