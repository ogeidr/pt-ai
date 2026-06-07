# Engagement Findings Store (`findings.jsonl`)

A structured, append-only record of every finding in an engagement, written by the
agents into `/engagements/{safe_id}/findings.jsonl` (one JSON object per line).

It replaces the current human-copy-paste handoff: instead of pasting one agent's
output into the next agent's prompt, agents **write findings here** and the
downstream agents (`attack-planner`, `report-generator`) **read them back**. The
machine contract is [`schema/findings.schema.json`](../schema/findings.schema.json).

## Why

| Without the store | With the store |
|-------------------|----------------|
| Findings move by copy-paste between sessions; some are lost | Findings persist in the engagement dir, host-synced |
| `attack-planner`/`report-generator` depend on what you remembered to paste | They consume the full record directly |
| Precision (false-positive rate) is hand-counted | `status` makes precision auto-scorable |
| The orchestrator dashboard has no backing data | The store *is* the data |

## Location & format

- Path: `/engagements/{safe_id}/findings.jsonl` (same dir as `scope.md` and evidence).
- One finding per line (JSONL) — append-friendly, no rewrite races, git-diffable.
- **Append-only, latest-wins.** To update a finding (e.g. validation flips it from
  `reported` to `confirmed`), append a *new* line reusing the same `id` with a fresh
  `updated_at`. Readers collapse by `id`, taking the last line. History is preserved.

## Lifecycle

```
recon/scan agent           poc-validator                 report-generator
  appends status=reported ───►  appends same id,    ───►  reads confirmed +
  (confidence set)              status=confirmed OR        chained findings,
                               status=false_positive       cites evidence[]
```

- `status=reported` — found by a scanner/agent, **not yet validated**.
- `status=confirmed` — `poc-validator` validated it. Counts toward precision.
- `status=false_positive` — `poc-validator` killed it. Counts against precision.
- `status=remediated` / `accepted_risk` — post-engagement / retest states.

**Precision** = `confirmed / (confirmed + false_positive)`. This is exactly the
false-positive elimination that `poc-validator` exists to do, now measurable.

## Field reference

Required: `schema_version, id, title, target, category, severity, status,
source_agent, discovered_at`. Everything else is optional but improves chaining
and report quality. Full types/enums in the JSON Schema; highlights:

| Field | Notes |
|-------|-------|
| `id` | `F-0001` style. **Reuse to update.** |
| `category` | domain: network/web/ad/cloud/container/host/credential/other |
| `phase` | recon/vuln-assessment/exploitation/post-exploitation/reporting |
| `severity` | info/low/medium/high/critical |
| `confidence` | analyst confidence *before* validation (status is the *outcome*) |
| `status` | lifecycle / validation state — drives precision |
| `evidence` | paths to raw files under the engagement dir — the propagation glue |
| `mitre` | ATT&CK IDs (`T1190`, `T1021.002`) |
| `chain_id` / `chain_step` | links a finding into an `attack-planner` chain |

## Which agent writes/reads what

| Agent | Writes | Reads |
|-------|--------|-------|
| recon-advisor, vuln-scanner, web-hunter, ad-attacker, cloud-security … | new `reported` findings + `evidence[]` | — |
| poc-validator | appends `confirmed` / `false_positive` updates | `reported` findings |
| attack-planner | `chain_id`/`chain_step` updates | `confirmed` findings |
| report-generator | — | all (collapsed, latest-wins) |

> **Wiring status (complete):** every agent carries a Findings Store section.
> `recon-advisor`, `vuln-scanner`, and `web-hunter` embed tailored producer
> write-blocks; all other agents — remaining producers and the consumers
> (`poc-validator`, `attack-planner`, `report-generator`) — receive the canonical
> role-based block (`agents/_findings-store.md`) injected at provision time by
> `provision/02-claude.sh`, mirroring the `_scope-guard.md` pattern. Idempotent:
> re-provisioning skips any agent that already has the section.

## Example

```json
{"schema_version":"1.0","id":"F-0001","title":"Jenkins pre-auth RCE","target":"10.10.1.50","port":443,"service":"https","category":"web","phase":"vuln-assessment","severity":"critical","cvss":9.8,"confidence":"high","status":"reported","cve":["CVE-2024-23897"],"mitre":["T1190"],"evidence":["nuclei_10-10-1-50_20260607_140000.txt"],"source_agent":"vuln-scanner","source_tool":"nuclei","engagement":"acme-2026","discovered_at":"2026-06-07T14:00:00Z"}
{"schema_version":"1.0","id":"F-0001","title":"Jenkins pre-auth RCE","target":"10.10.1.50","category":"web","severity":"critical","status":"confirmed","confidence":"high","chain_id":"C1","chain_step":1,"evidence":["nuclei_10-10-1-50_20260607_140000.txt","poc_10-10-1-50_20260607_150000.txt"],"source_agent":"poc-validator","discovered_at":"2026-06-07T14:00:00Z","updated_at":"2026-06-07T15:00:00Z"}
```

Two lines, same `id`: the finding was reported by `vuln-scanner`, then confirmed by
`poc-validator` and linked into chain `C1`. Readers see the second (latest) line.

## Status

Wiring is **complete** in the agent prompts — takes effect in the VM after
`./pt-ai provision` (or a fresh `up`), which
runs the injection. Validate a record against the contract with any JSON Schema
tool, e.g. `jsonschema -i <record> schema/findings.schema.json`. Note the `schema/`
dir is not synced into the VM, so the agent blocks are self-contained (fields +
append idiom inline) rather than pointing at the schema.
