# aws-ec2-recon

Enumerate EC2 instances across AWS regions using the AWS CLI and save the
results as initial reconnaissance evidence for a penetration test. This is
read-only API enumeration (`describe-*` only) — never create, modify, or
delete resources.

## Check scope and caller identity first

Use the read tool to check `/work/scope.md`. If it does not exist, STOP and
tell the user to run `/scope-declare` before enumerating any AWS account.

Confirm which AWS account the credentials belong to:

```
aws sts get-caller-identity --output json
```

The account ID (and/or alias) MUST appear in the declared scope. If the
authenticated account is not in scope, REFUSE and explain. If unclear, ask the
user to confirm the account ID is authorized before proceeding.

## Choose region coverage

Ask the user: enumerate **all enabled regions** or a **specific region**?

List enabled regions:

```
aws ec2 describe-regions --query 'Regions[].RegionName' --output text
```

OPSEC: **MODERATE** — read-only AWS API calls. Not noisy on the network, but
recorded in CloudTrail and may trigger GuardDuty in a monitored account. Tell
the user this before running.

## Enumerate EC2 instances

For each in-scope region (replace `REGION`):

```
aws ec2 describe-instances --region REGION \
  --query 'Reservations[].Instances[].{InstanceId:InstanceId,Name:Tags[?Key==`Name`]|[0].Value,State:State.Name,Type:InstanceType,PrivateIP:PrivateIpAddress,PublicIP:PublicIpAddress,PrivateDNS:PrivateDnsName,PublicDNS:PublicDnsName,AZ:Placement.AvailabilityZone,VPC:VpcId,SubnetId:SubnetId,KeyName:KeyName,SecurityGroups:SecurityGroups[].GroupName}' \
  --output table
```

Run the same query with `--output json` to capture machine-readable evidence.

Quick host/IP-only sweep across every region in one pass:

```
for r in $(aws ec2 describe-regions --query 'Regions[].RegionName' --output text); do
  echo "== $r =="
  aws ec2 describe-instances --region "$r" \
    --query 'Reservations[].Instances[].[InstanceId,Tags[?Key==`Name`]|[0].Value,State.Name,PrivateIpAddress,PublicIpAddress,PublicDnsName]' \
    --output text
done
```

## Save evidence

Save raw JSON before presenting analysis. Use the working directory and a
timestamped name (sanitize the account ID):

- Per-region raw JSON: `awsec2_{accountid}_{region}_{YYYYMMDD_HHMMSS}.json`
- Combined recon summary: `awsec2_recon_{accountid}_{YYYYMMDD_HHMMSS}.md`

The summary header should note account ID, regions covered, engagement ID from
`/work/scope.md`, and the collection timestamp.

## Present the recon summary

| Instance ID | Name | State | Public IP | Public DNS | Private IP | Type | Region | Security Groups |
|-------------|------|-------|-----------|------------|------------|------|--------|-----------------|

Highlight for the next phase:
- Internet-facing hosts (instances with a public IP) — the external attack surface.
- Name tags / security groups hinting at sensitive roles (db, jenkins, bastion,
  vpn, admin, prod).
- Overly permissive security group names worth a follow-up `describe-security-groups`.

## Recommend next steps

- `aws ec2 describe-security-groups` to map ingress rules on exposed instances.
- Hand in-scope public IPs/DNS names to the recon-advisor for nmap/service scans.
- Note that `describe-instances` is metadata only — confirming live services
  still requires network-level recon against the in-scope hosts.

Remind the user to secure or transfer the evidence files at session end.
