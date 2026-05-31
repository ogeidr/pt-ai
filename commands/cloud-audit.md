# cloud-audit

Audit an authorized cloud account for misconfigurations and attack surface using
prowler and ScoutSuite (IAM, S3, security groups, public snapshots, weak policies,
logging gaps). Read-only posture assessment — never create, modify, or delete
resources, and never add write/exploit flags.

## Check scope, identity, and tools first

Use the read tool to check `/work/scope.md`. If it does not exist, STOP and tell
the user to run `/scope-declare` first.

Confirm the authenticated account and that the tools are present:

```
aws sts get-caller-identity --output json
command -v prowler scout
```

The account/subscription/project ID MUST appear in the declared scope. If it is
not in scope, REFUSE and explain. If ambiguous, ask the user to confirm before
proceeding.

## OPSEC briefing (tell the user before running)

OPSEC: **MODERATE**, but **high CloudTrail volume**. A full prowler or ScoutSuite
run makes hundreds-to-thousands of read-only API calls in minutes — quiet on the
network, but very visible in CloudTrail and likely to trip GuardDuty / SOC alerting
in a monitored account. Confirm a full sweep, or scope it down if stealth matters.

## Choose provider and depth

Ask: which provider (`aws` / `azure` / `gcp` / `kubernetes`) and full vs. targeted?
Both tools default to AWS.

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

Other providers: `scout azure`, `scout gcp --project-id <id>`, `scout kubernetes`.

## Save evidence

Both tools write to the `--output-directory` / `--report-dir` you pass — keep those
timestamped dirs as raw evidence. Then write a markdown summary:

- `cloudaudit_{accountid}_{YYYYMMDD_HHMMSS}.md`

Header must note: provider, account/subscription/project ID, engagement ID from
`/work/scope.md`, tools + versions run, and the collection timestamp.

## Present prioritized findings

Parse the prowler JSON (and ScoutSuite JSON under `scoutsuite-results/`) into a
severity-ranked table:

| Severity | Service | Finding | Resource | Why it matters / next step |
|----------|---------|---------|----------|----------------------------|

Lead with exploitable, attacker-relevant issues, not compliance noise:
- Public S3 buckets, public EBS/RDS snapshots, public AMIs.
- IAM: wildcard policies, privilege-escalation paths, long-lived/unused access keys,
  users without MFA, overly trusting assume-role policies.
- Security groups open to `0.0.0.0/0` on sensitive ports (22, 3389, 3306, 5432, etc.).
- Disabled CloudTrail / GuardDuty / Config.

## Recommend next steps

- Cross-reference open security groups with public IPs from `aws-ec2-recon`.
- Feed IAM privesc findings to the cloud-security agent for an attack-path write-up.
- Confirmed exploitation (e.g., abusing an IAM privesc path) belongs in a separate,
  explicitly authorized active-testing phase — cloud-audit stays read-only.

Remind the user to secure or transfer the evidence directories at session end.
