---
name: aws-ec2-recon
description: >
  Enumerate EC2 instances (instance IDs, name tags, public/private IPs and DNS,
  state, type, VPC, security groups) across AWS regions using the AWS CLI, and
  save the results as initial reconnaissance evidence for a penetration test.
  Invoke after /scope-declare so the target AWS account is confirmed in scope.
disable-model-invocation: false
allowed-tools: Bash, Read, Write
---

## Current scope for this engagement

!`cat engagements/scope.md 2>/dev/null || echo "No scope declared yet. Run /scope-declare before enumerating any AWS account."`

## Evidence directory for this engagement

!`grep -m1 'Evidence directory:' engagements/scope.md 2>/dev/null | sed 's/.*Evidence directory: //' || echo "engagements (no scope declared — run /scope-declare first)"`

## Caller identity (which AWS account these credentials belong to)

!`aws sts get-caller-identity --output json 2>&1 || echo "AWS CLI not authenticated or not installed. Configure credentials (aws configure / SSO / env vars) before running this skill."`

## Instructions

You are running cloud reconnaissance against an AWS account. This is **read-only
API enumeration** — `describe-*` calls only. Never create, modify, or delete
resources from this skill.

The **Evidence directory** shown above is `ENGAGEMENT_DIR`. Use it as an absolute
path prefix for every output file in this skill. Never use relative paths.

### Step 1 — Confirm scope and authorization (MANDATORY)

1. Read `engagements/scope.md`. If it does not exist, STOP and tell the user to run
   `/scope-declare` first.
2. Compare the **Account** field from the caller-identity output above against
   the authorized scope. The AWS account ID (and/or account alias) MUST be named
   in the declared scope.
3. If the authenticated account is **not** in scope, REFUSE and explain. Do not
   enumerate an account the engagement does not cover.
4. If scope or caller identity is unclear, ask the user to confirm the account ID
   is authorized before proceeding.

### Step 2 — Choose region coverage

Ask the user: enumerate **all enabled regions** or a **specific region**?

Enumerate the list of enabled regions with:

```
aws ec2 describe-regions --query 'Regions[].RegionName' --output text
```

(OPSEC: **MODERATE** — read-only AWS API calls. They are not noisy on the network
but are recorded in CloudTrail and may trigger GuardDuty if the account is
monitored. Mention this to the user.)

### Step 3 — Enumerate EC2 instances

For each in-scope region, run a structured query. Replace `REGION`:

```
aws ec2 describe-instances --region REGION \
  --query 'Reservations[].Instances[].{InstanceId:InstanceId,Name:Tags[?Key==`Name`]|[0].Value,State:State.Name,Type:InstanceType,PrivateIP:PrivateIpAddress,PublicIP:PublicIpAddress,PrivateDNS:PrivateDnsName,PublicDNS:PublicDnsName,AZ:Placement.AvailabilityZone,VPC:VpcId,SubnetId:SubnetId,KeyName:KeyName,SecurityGroups:SecurityGroups[].GroupName}' \
  --output table
```

Run the same query with `--output json` to capture machine-readable evidence.

Notes:
- `describe-instances` returns terminated/stopped instances too — keep them; a
  stopped host with a public IP history is still useful context.
- For a quick host/IP-only sweep across every region in one pass:

```
for r in $(aws ec2 describe-regions --query 'Regions[].RegionName' --output text); do
  echo "== $r =="
  aws ec2 describe-instances --region "$r" \
    --query 'Reservations[].Instances[].[InstanceId,Tags[?Key==`Name`]|[0].Value,State.Name,PrivateIpAddress,PublicIpAddress,PublicDnsName]' \
    --output text
done
```

### Step 4 — Save evidence

First, verify the evidence directory and set `ENGAGEMENT_DIR`:

```sh
test -d engagements && test -w engagements || { echo "ERROR: engagements not mounted or not writable"; exit 1; }
ENGAGEMENT_DIR=$(grep -m1 'Evidence directory:' engagements/scope.md | sed 's/.*Evidence directory: //')
[ -z "$ENGAGEMENT_DIR" ] && ENGAGEMENT_DIR="engagements"
mkdir -p "$ENGAGEMENT_DIR/scans" "$ENGAGEMENT_DIR/reports"
```

Save raw JSON output before presenting analysis, using absolute paths:

- Per-region raw JSON: `$ENGAGEMENT_DIR/scans/awsec2_{accountid}_{region}_{YYYYMMDD_HHMMSS}.json`
- Combined recon summary (markdown table): `$ENGAGEMENT_DIR/reports/awsec2_recon_{accountid}_{YYYYMMDD_HHMMSS}.md`

Write the markdown summary with the Write tool using the absolute path above. Include a
header noting the account ID, regions covered, the engagement ID from
`engagements/scope.md`, and the collection timestamp.

### Step 5 — Present the recon summary

Produce a prioritized table:

| Instance ID | Name | State | Public IP | Public DNS | Private IP | Type | Region | Security Groups |
|-------------|------|-------|-----------|------------|------------|------|--------|-----------------|

Then highlight high-value observations for the next phase:
- Internet-facing hosts (instances with a public IP) — the external attack surface.
- Instances whose Name tag or security group hints at sensitive roles (db, jenkins,
  bastion, vpn, admin, prod).
- Overly permissive security group names worth a follow-up `describe-security-groups`.

### Step 6 — Recommend next steps

Suggest concrete follow-ups, for example:
- `aws ec2 describe-security-groups` to map ingress rules on exposed instances.
- Hand public IPs/DNS names to the `/full-recon` skill for a sweep (it sources EC2
  the same way), or to the `recon-advisor` agent for targeted scans (those targets
  must also be in scope).
- `aws ec2 describe-instances` is metadata only — note that confirming live
  services still requires network-level recon against the in-scope hosts.

Remind the user that evidence is in `$ENGAGEMENT_DIR/` and synced to the host.
