---
name: cloud-audit
description: >
  Audit an authorized cloud account for misconfigurations and attack surface
  using prowler and ScoutSuite (IAM, S3, security groups, public snapshots,
  weak policies, logging gaps). Read-only posture assessment that extends initial
  recon. Invoke after /scope-declare so the target account is confirmed in scope.
disable-model-invocation: false
allowed-tools: Bash, Read, Write
---

## Current scope for this engagement

!`cat /work/scope.md 2>/dev/null || echo "No scope declared yet. Run /scope-declare before auditing any cloud account."`

## Caller identity (which AWS account these credentials belong to)

!`aws sts get-caller-identity --output json 2>&1 || echo "AWS CLI not authenticated. For Azure/GCP, confirm the active subscription/project before running."`

## Tool availability

!`for t in prowler scout; do command -v "$t" >/dev/null 2>&1 && echo "$t: $(command -v $t)" || echo "$t: NOT FOUND"; done`

## Instructions

You are running a **read-only cloud posture audit**. prowler and ScoutSuite make
large numbers of `describe/list/get` API calls across every service — they never
create, modify, or delete resources. Never add write/exploit flags from this skill.

### Step 1 — Confirm scope and authorization (MANDATORY)

1. Read `/work/scope.md`. If missing, STOP and tell the user to run `/scope-declare`.
2. Confirm the authenticated account/subscription/project (from caller identity
   above) is named in the declared scope. If not, REFUSE and explain.
3. If scope or identity is ambiguous, ask the user to confirm before proceeding.

### Step 2 — OPSEC briefing (tell the user before running)

OPSEC: **MODERATE**, but **high CloudTrail volume**. A full prowler or ScoutSuite
run generates hundreds-to-thousands of read-only API calls in minutes — quiet on
the network, but very visible in CloudTrail and likely to trip GuardDuty / SOC
alerting in a monitored account. Confirm the user wants a full sweep, or scope it
down (Step 3) if stealth matters.

### Step 3 — Choose provider and depth

Ask: which provider (`aws` / `azure` / `gcp` / `kubernetes`) and full sweep vs.
targeted? Both tools default to AWS.

**prowler** — checks-based, severity-filterable:

```
# Full AWS audit, JSON + HTML evidence into a timestamped dir
prowler aws \
  --output-formats csv json-ocsf html \
  --output-directory ./prowler_{accountid}_{YYYYMMDD_HHMMSS}
```

```
# Stealthier / focused: only high+critical, specific services
prowler aws --severity critical high \
  --service iam s3 ec2 \
  --output-formats json-ocsf \
  --output-directory ./prowler_{accountid}_{YYYYMMDD_HHMMSS}
```

```
# List checks/services without calling the cloud (offline planning)
prowler aws --list-checks
prowler aws --list-services
```

**ScoutSuite** — full posture snapshot with an HTML report:

```
scout aws --no-browser \
  --report-dir ./scoutsuite_{accountid}_{YYYYMMDD_HHMMSS}
```

For other providers: `scout azure`, `scout gcp --project-id <id>`, `scout kubernetes`.

### Step 4 — Save evidence

Both tools already write to the `--output-directory` / `--report-dir` you pass —
keep those timestamped dirs as the raw evidence (don't overwrite them). Then write
a markdown summary with the Write tool:

- `cloudaudit_{accountid}_{YYYYMMDD_HHMMSS}.md`

Header must note: provider, account/subscription/project ID, engagement ID from
`/work/scope.md`, tools + versions run, and the collection timestamp.

### Step 5 — Present prioritized findings

Parse the prowler JSON (and/or ScoutSuite JSON under its `scoutsuite-results/`)
and produce a severity-ranked table:

| Severity | Service | Finding | Resource | Why it matters / next step |
|----------|---------|---------|----------|----------------------------|

Lead with the exploitable, attacker-relevant issues, not compliance noise:
- Public S3 buckets, public EBS/RDS snapshots, public AMIs.
- IAM: wildcard policies, privilege-escalation paths, long-lived/unused access keys,
  users without MFA, overly trusting assume-role policies.
- Security groups open to `0.0.0.0/0` on sensitive ports (22, 3389, 3306, 5432, etc.).
- Disabled CloudTrail / GuardDuty / Config (both blind spots and findings).

### Step 6 — Recommend next steps

- Cross-reference open security groups with public IPs from `aws-ec2-recon`.
- Feed IAM privesc findings to the `cloud-security` agent for an attack-path write-up.
- Note that confirmed exploitation (e.g., abusing an IAM privesc path) belongs in a
  separate, explicitly authorized active-testing phase — `cloud-audit` stays read-only.

Remind the user to secure or transfer the evidence directories at session end.
