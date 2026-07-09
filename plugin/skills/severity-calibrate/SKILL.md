---
name: severity-calibrate
description: >
  Recalibrate finding severity before reporting so unexploited findings stop being
  over-rated. For every finding in the engagement store it records an honest
  exploitation state and computes a CVSS v3.1 TEMPORAL score + vector from the base
  score, deflating severity for theoretical / version-only / unproven findings.
  Deflate-only — it never raises a rating. Run after exploitation + validation and
  immediately before report-generator. Updates engagements/{id}/findings.jsonl
  append-only (one new line per finding, reusing its id). Invoke as the
  reporting-phase calibration pass, or whenever the user asks to fix inflated /
  theoretical severities or finalize findings before a report.
disable-model-invocation: false
allowed-tools: Bash, Read, Write
---

## Current scope for this engagement

!`cat engagements/scope.md 2>/dev/null || echo "No scope declared yet. Run /scope-declare first — there is nothing to calibrate without an engagement."`

## Evidence directory for this engagement

!`grep -m1 'Evidence directory:' engagements/scope.md 2>/dev/null | sed 's/.*Evidence directory: //' || echo "engagements (no scope declared — run /scope-declare first)"`

## Instructions

You finalize finding severity so the report reflects **what was actually observed**, not
the CVE worst case. Two jobs: (1) mark each finding's **exploitation** state honestly, and
(2) attach a **CVSS v3.1 temporal score + vector** and derive `severity` from it — **deflate
only, never inflate**. Do not exploit anything, do not touch targets; this is a desk pass
over the findings store.

### Why this exists

A CVSS **base** score assumes the worst case — it bakes in Exploit Code Maturity = High and
Report Confidence = Confirmed. A version-matched CVE that nobody exploited therefore lands as
`critical` even though nothing was proven. The **temporal** metrics correct exactly that:
multiplying the base by Exploit Code Maturity (E), Remediation Level (RL), and Report
Confidence (RC) produces the *observed* score. You compute that here, before reporting.

### Step 1 — Resolve the store and load the latest state of every finding

```sh
test -d engagements && test -w engagements || { echo "ERROR: engagements not mounted"; exit 1; }
ENGAGEMENT_DIR=$(grep -m1 'Evidence directory:' engagements/scope.md | sed 's/.*Evidence directory: //')
[ -z "$ENGAGEMENT_DIR" ] && ENGAGEMENT_DIR="engagements"
FINDINGS="$ENGAGEMENT_DIR/findings.jsonl"
test -s "$FINDINGS" || { echo "No findings to calibrate at $FINDINGS"; exit 0; }

# Collapse to the latest line per id (the store is append-only; latest wins):
jq -s 'group_by(.id) | map(.[-1])' "$FINDINGS" > /tmp/findings_collapsed.json
jq -r '.[] | "\(.id)\t\(.severity)\t\(.cvss // "-")\t\(.status)\t\(.exploitation // "-")\t\(.cve // [] | join(","))\t\(.title)"' /tmp/findings_collapsed.json
```

Skip any finding whose latest `status` is `false_positive`, `remediated`, or `accepted_risk`
— those are closed; do not re-rate them.

### Step 2 — Pick the three temporal metrics per finding (judgment)

For each open finding choose one value for each metric:

**Exploit Code Maturity (E)** — drive from the finding's `exploitation` (set it if missing):
| exploitation | meaning | E |
|---|---|---|
| `confirmed` | YOU proved it this engagement (poc-validator) | `H` (1.00) |
| `functional` | reliable public exploit exists, not run here | `F` (0.97) |
| `poc` | PoC/exploit-dev only | `P` (0.94) |
| `unproven` | theoretical / version or banner match only (**default for scanner & recon findings**) | `U` (0.91) |

**Report Confidence (RC)** — from `status` + `confidence`:
| state | RC |
|---|---|
| `status:confirmed` (validated) | `C` (1.00) |
| `confidence:moderate`, unvalidated | `R` (0.96) |
| `confidence:speculative` or version-only detection | `U` (0.92) |

**Remediation Level (RL)** — from whether a fix exists:
| state | RL |
|---|---|
| official patch / fixed version exists (typical for an old CVE) | `O` (0.95) |
| temporary fix / vendor mitigation only | `T` (0.96) |
| documented workaround only | `W` (0.97) |
| no fix available / unknown | `U` (1.00) |

When unsure, pick the **least** deflating value (`E:U` is already the floor; for RL/RC prefer
the higher multiplier) — under-deflating is safer than over-deflating.

### Step 3 — Compute the temporal score (exact arithmetic, not mental math)

`TemporalScore = roundup( Base × E × RL × RC )`, where roundup = round **up** to 1 decimal.
Run this per finding with the multipliers you chose — do NOT eyeball it:

```sh
# BASE = the finding's cvss base; E/RL/RC = the multipliers from Step 2
calc_temporal() {  # args: base e rl rc
  awk -v b="$1" -v e="$2" -v rl="$3" -v rc="$4" 'BEGIN{
    t=b*e*rl*rc; c=int(t*10); if (c < t*10 - 1e-9) c++; printf "%.1f\n", c/10
  }'
}
# example: base 9.8, E:U(0.91), RL:U(1.00), RC:U(0.92)
calc_temporal 9.8 0.91 1.00 0.92      # -> 8.3
```

Map the temporal score to the severity band:

| temporal score | severity |
|---|---|
| 0.0 | info |
| 0.1–3.9 | low |
| 4.0–6.9 | medium |
| 7.0–8.9 | high |
| 9.0–10.0 | critical |

Because every multiplier is ≤ 1, the temporal band can only be **equal to or lower** than the
base band — deflate-only holds automatically. Never hand-raise a rating.

### Step 4 — Build the CVSS vector

Produce the full v3.1 vector = **base metrics + temporal metrics**:
`CVSS:3.1/AV:_/AC:_/PR:_/UI:_/S:_/C:_/I:_/A:_/E:_/RL:_/RC:_`

- If the finding has a `cve`, use that CVE's **published NVD v3.1 base vector** for the base
  half; append the `E`/`RL`/`RC` letters you chose.
- If there is no CVE, derive the base metrics from the finding's characteristics (network vs
  local, auth required, impact), then append the temporal letters.
- **Never invent a base score.** If you cannot establish a base (no CVE, no `cvss`, not enough
  detail), leave `cvss_temporal` null, keep the analyst `severity`, still set `exploitation`,
  and list the finding under "needs manual base score" in the summary.

Findings with **no CVSS at all** (qualitative issues like an open share or weak policy): keep
the analyst-assigned `severity`, but still set an honest `exploitation` and note that severity
rests on analyst judgment, not a temporal score.

### Step 5 — Append the calibrated record (append-only, reuse the id)

For each finding, append ONE new line = the latest record merged with the calibrated fields.
This preserves every original field and overwrites only the calibrated ones:

```sh
# REC = the collapsed latest JSON object for this id (from /tmp/findings_collapsed.json)
# TEMP/VEC/SEV/EXPL = your computed temporal score (number), vector, severity band, exploitation
printf '%s' "$REC" | jq -c \
  --argjson temp "$TEMP" --arg vec "$VEC" --arg sev "$SEV" --arg expl "$EXPL" \
  '. + {schema_version:"1.1", exploitation:$expl, cvss_vector:$vec, cvss_temporal:$temp, severity:$sev, source_agent:"severity-calibrate", updated_at:(now|todate)}' \
  >> "$ENGAGEMENT_DIR/findings.jsonl"
```

(For a finding left at null temporal, omit `cvss_temporal`/`cvss_vector`/`severity` from the
merge and only set `exploitation` + `source_agent` + `updated_at`.)

**Keep the original `cvss` as the base score** — do not overwrite it. The report shows base
vs temporal side by side.

### Step 6 — Present the calibration summary

Show what changed so the operator can sanity-check before the report:

```
SEVERITY CALIBRATION SUMMARY
────────────────────────────────────────────────────────────────────────────
| ID     | Base | Temporal | Severity (before → after) | Exploitation | Driver |
|--------|------|----------|---------------------------|--------------|--------|
| F-0001 | 9.8  | 8.3      | critical → high           | unproven     | E:U RC:U |
| ...    |      |          |                           |              |        |
────────────────────────────────────────────────────────────────────────────
Deflated: N   Unchanged: M   Needs manual base score: K
Theoretical (exploitation ≠ confirmed): X of Y findings
```

Call out the headline: how many "critical" ratings were version-only and dropped to high/medium.

### Rules

1. **Deflate-only.** Temporal severity ≤ base severity, always. Never raise a rating here.
2. **Idempotent.** Always recompute from the original `cvss` base — never from a prior
   `cvss_temporal` — so re-running does not compound deflation. The `cvss` base field is the
   single source of truth; you only ever multiply it fresh.
3. **Honesty over drama.** `exploitation:"confirmed"` requires that it was actually proven
   (a poc-validator `confirmed` record). Everything else is theoretical and must say so.
4. **Don't invent base scores.** No CVE/CVSS and not enough detail → null temporal, flag it.
5. **Append only.** One new JSONL line per finding; never rewrite the file.
6. **No targets touched.** This is a scoring pass over the store, nothing else.
