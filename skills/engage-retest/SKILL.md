---
name: engage-retest
description: >
  Run a Remediation-validation (retest) round of a penetration-test engagement,
  behind a state-backed HARD GATE read fresh from gates.jsonl. Delegates
  retest-validator, which hands each re-validation to poc-validator. A retest is a new
  authorization round — invoke only after reporting completed and the operator
  approves the retest. Claude Code only — the automated fan-out needs the Task tool,
  which opencode lacks.
disable-model-invocation: true
allowed-tools: Bash, Read, Write, Task
---

## Current scope for this engagement

!`cat /engagements/scope.md 2>/dev/null || echo "No scope declared yet. Run /scope-declare then /engagement before this phase."`

## Engagement delegation protocol (shared, authoritative)

!`cat /opt/pt-ai/skills/_engagement-protocol.md 2>/dev/null || echo "⚠ Shared engagement protocol missing at /opt/pt-ai/skills/_engagement-protocol.md — STOP and re-provision before delegating."`

## This phase

You are the **Remediation validation (retest)** round of the engagement lifecycle in
`docs/AGENT-GUIDE.md`. A retest re-checks previously reported findings after the
client has remediated them — typically a detached round some time after report
delivery. Follow the shared protocol above for state re-resolution, the
authorized-agent check, the delegation envelope, conflict resolution, and findings
propagation.

This skill is **operator-invocation only** (`disable-model-invocation: true`):
re-running validation against remediated systems is a new authorization round and
must be an explicit human action, never a model-initiated transition.

### The retest HARD GATE

Re-validation re-executes checks (via `poc-validator`) against systems that may have
changed since the original test. Treat it like the exploitation gate: verify state on
disk before delegating — do not rely on memory of this session (a fresh session has
none):

```sh
grep -q '"phase":"reporting","status":"complete"' "<ENGAGEMENT_DIR>/gates.jsonl" && \
grep -q '"phase":"retest","status":"approved"'    "<ENGAGEMENT_DIR>/gates.jsonl" && \
echo GO || echo "NO-GO"
```

- If **NO-GO**: STOP. Confirm reporting completed, present the retest worklist (the
  prior findings to re-validate) and ask the operator for explicit approval of this
  retest round. Only after they approve, append the approval line, then re-check:
  ```sh
  printf '%s\n' '{"engagement":"<id>","phase":"retest","status":"approved","ts":"'"$(date -u +%Y-%m-%dT%H:%M:%SZ)"'","by":"operator"}' >> "<ENGAGEMENT_DIR>/gates.jsonl"
  ```
- **Never** inherit the prior engagement's exploitation approval for the retest. The
  retest approval line must be recorded by an operator decision, not inferred.
  Re-confirm every target against the current declared scope — remediation may have
  changed the environment.

### Delegation (only after GO)

**Agents (if on the authorized list):** `retest-validator` → `poc-validator`.
`retest-validator` reads the prior `ENGAGEMENT_DIR/findings.jsonl`, builds the
finding-by-finding retest worklist, and delegates the least-intrusive re-validation
of each finding to `poc-validator`, which re-runs the confirmation under operator
approval. Each finding is driven to a defensible status (`remediated`, `reported`, or
`accepted_risk`) appended to `findings.jsonl` reusing the original finding id.

**On completion:**

1. Present the retest rollup (fixed vs still-open vs accepted-risk) to the operator.
2. Append the completion line (operator approves the Bash call):
   ```sh
   printf '%s\n' '{"engagement":"<id>","phase":"retest","status":"complete","ts":"'"$(date -u +%Y-%m-%dT%H:%M:%SZ)"'","by":"engage-retest"}' >> "<ENGAGEMENT_DIR>/gates.jsonl"
   ```
3. Tell the operator to re-run `/engage-report` if the retest outcomes should be
   folded into an updated deliverable. Do not auto-advance.
