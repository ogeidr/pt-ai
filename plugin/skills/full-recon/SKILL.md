---
name: full-recon
description: >
  Full reconnaissance of in-scope hosts. Accepts targets as hostnames, IP
  addresses, AWS-sourced EC2 instances, or Amazon WorkSpaces (VDI) endpoints;
  normalizes them to a scoped target list, then runs host discovery, port and
  service scanning, DNS/WHOIS, and web fingerprinting, saving per-host evidence.
  Invoke after /scope-declare so every resolved target is confirmed in scope.
disable-model-invocation: false
allowed-tools: Bash, Read, Write
---

## Current scope for this engagement

!`cat engagements/scope.md 2>/dev/null || echo "No scope declared yet. Run /scope-declare before any reconnaissance."`

## Evidence directory for this engagement

!`grep -m1 'Evidence directory:' engagements/scope.md 2>/dev/null | sed 's/.*Evidence directory: //' || echo "engagements (no scope declared — run /scope-declare first)"`

## Caller identity (for AWS-sourced targets)

!`aws sts get-caller-identity --output json 2>&1 || echo "AWS CLI not authenticated. Needed only for EC2 / WorkSpaces target sourcing; direct host/IP recon works without it."`

## Tool availability

!`command -v nmap masscan dig whois curl whatweb nikto nc 2>/dev/null || echo "(one or more recon tools missing — check the install)"`

## Instructions

You are running full network reconnaissance against in-scope hosts. This skill
**orchestrates** target collection plus active scanning — it is read-only toward
targets (no exploitation, no writes to target systems). Default to the least
aggressive option at every step.

**When to use this (vs `recon-advisor`).** Use `/full-recon` for the broad first
pass: many hosts, ranges, or AWS-sourced (EC2/WorkSpaces) targets — host discovery,
port/service scanning, DNS/WHOIS, and web fingerprinting across the whole list. For
deep enumeration of a single chosen host, CVE prioritization, or analysis of pasted
scan output, hand off to the `recon-advisor` agent (Step 9).

The **Evidence directory** shown above is `ENGAGEMENT_DIR`. Use it as an absolute
path prefix for every output file in this skill. Never use relative paths.

### Step 1 — Confirm scope and authorization (MANDATORY)

1. Read `engagements/scope.md`. If missing, STOP and tell the user to run `/scope-declare`.
2. Extract `ENGAGEMENT_DIR` from the "Evidence directory:" line in scope.md.
3. You will validate EVERY resolved target against this scope in Step 3 before scanning.
4. If scope is ambiguous, ask the user to confirm boundaries before proceeding.

### Step 2 — Collect and normalize targets

Accept targets from any mix of these sources and build one deduplicated list of
`{identifier, ip(s), source}`:

**(a) Direct hostnames / IPs** — provided by the user. For hostnames, resolve and
record the address(es):

```
dig +short HOSTNAME A; dig +short HOSTNAME AAAA
```

**(b) AWS EC2 instances** — pull from the in-scope account (mirrors `aws-ec2-recon`):

```
aws ec2 describe-instances --region REGION \
  --query 'Reservations[].Instances[].{Id:InstanceId,Name:Tags[?Key==`Name`]|[0].Value,State:State.Name,PrivateIP:PrivateIpAddress,PublicIP:PublicIpAddress,PublicDNS:PublicDnsName}' \
  --output json
```

**(c) Amazon WorkSpaces (VDI)** — enumerate directories then workspaces; the
reachable address is the `IpAddress` field (typically private/VPC):

```
aws workspaces describe-workspace-directories \
  --query 'Directories[].{DirId:DirectoryId,Name:DirectoryName,Type:DirectoryType,RegCode:RegistrationCode}' --output json

aws workspaces describe-workspaces \
  --query 'Workspaces[].{WsId:WorkspaceId,User:UserName,Computer:ComputerName,Ip:IpAddress,DirId:DirectoryId,State:State}' --output json
```

(Run AWS sourcing per in-scope region; WorkSpaces IPs are usually private, so reaching
them requires network position inside/peered to the VPC — note this to the user.)

### Step 3 — Validate every target against scope (MANDATORY)

For each normalized target, confirm the IP/hostname falls within the declared scope — read the canonical record at `$ENGAGEMENT_DIR/scope.md` (the root `engagements/scope.md` is only a pointer to it).
- DROP and report any target that is out of scope — do not scan it.
- WorkSpaces/EC2 private IPs count only if the declared scope covers that range.
- Present the final in-scope target list to the user before scanning.

### Step 4 — OPSEC briefing

OPSEC: **MODERATE** for the default pipeline (TCP connect scans, banner grabs, HTTP
requests), rising to **LOUD** if the user opts into vuln scanning (nikto) or aggressive
NSE. Active scanning is visible to IDS/IPS and, for AWS-hosted targets, recorded in
VPC flow logs / GuardDuty. Confirm depth before scanning.

### Step 5 — Run the recon pipeline (least aggressive first)

First, verify the evidence directory is accessible and set it:

```sh
test -d engagements && test -w engagements || { echo "ERROR: engagements not mounted or not writable"; exit 1; }
ENGAGEMENT_DIR=$(grep -m1 'Evidence directory:' engagements/scope.md | sed 's/.*Evidence directory: //')
[ -z "$ENGAGEMENT_DIR" ] && ENGAGEMENT_DIR="engagements"
mkdir -p "$ENGAGEMENT_DIR/scans" "$ENGAGEMENT_DIR/reports"
```

Per in-scope target, save raw output to `$ENGAGEMENT_DIR/scans/` (absolute path, sanitize
target: `/`→`-`). The **canonical** scan defaults live in the `recon-advisor` agent
(non-root `-sT`, rate-limited, timeouts); they are mirrored here for standalone use.

```
# 1) Liveness / host discovery (skip -Pn unless ICMP is filtered)
nmap -sn TARGET -oN "$ENGAGEMENT_DIR/scans/nmap_ping_{target}_{YYYYMMDD_HHMMSS}.txt"

# 2) Service + default-script scan, top ports, rate-limited (MODERATE)
nmap -sT -sV -sC --top-ports 1000 \
  --min-rate 100 --max-rate 1000 --host-timeout 300s \
  TARGET -oN "$ENGAGEMENT_DIR/scans/nmap_svc_{target}_{YYYYMMDD_HHMMSS}.txt"

# 3) Full TCP port sweep when thoroughness is wanted (slower)
nmap -sT -p- --min-rate 100 --max-rate 1000 --host-timeout 600s \
  TARGET -oN "$ENGAGEMENT_DIR/scans/nmap_allports_{target}_{YYYYMMDD_HHMMSS}.txt"
```

For large in-scope ranges, discover first with masscan (rate-limited), then nmap the
live hosts:

```
masscan TARGET_RANGE -p1-65535 --rate 1000 -oL "$ENGAGEMENT_DIR/scans/masscan_{range}_{YYYYMMDD_HHMMSS}.txt"
```

For hostnames, add passive/name intelligence:

```
whois HOSTNAME            > "$ENGAGEMENT_DIR/scans/whois_{host}_{YYYYMMDD_HHMMSS}.txt"
dig ANY HOSTNAME +noall +answer > "$ENGAGEMENT_DIR/scans/dig_{host}_{YYYYMMDD_HHMMSS}.txt"
```

When web ports (80/443/8080/8443) are open, fingerprint the web layer:

```
curl -sILk --connect-timeout 10 --max-time 30 http://TARGET/  > "$ENGAGEMENT_DIR/scans/http_hdr_{target}_{YYYYMMDD_HHMMSS}.txt"
whatweb -a 3 TARGET                                            > "$ENGAGEMENT_DIR/scans/whatweb_{target}_{YYYYMMDD_HHMMSS}.txt"
# nikto is LOUD — only with user opt-in:
# nikto -host TARGET -output "$ENGAGEMENT_DIR/scans/nikto_{target}_{YYYYMMDD_HHMMSS}.txt"
```

Rules:
- Show each command and its OPSEC tag before running; offer a quieter alternative.
- Never pipe target-controlled output into a shell.
- Stop and ask before any LOUD step (full `-p-` at high rate, nikto, aggressive NSE).

### Step 6 — Save evidence

Keep all raw output files above. Then write a consolidated summary using the Write tool
with an absolute path:

- `$ENGAGEMENT_DIR/reports/fullrecon_{engagement}_{YYYYMMDD_HHMMSS}.md`

Header must note: engagement ID from `engagements/scope.md`, target sources used
(direct / EC2 / WorkSpaces), the final in-scope target list, tools run, and timestamps.

### Step 7 — Present the consolidated recon summary

Per-host attack-surface table:

| Host (source) | IP | Open ports | Services / versions | Web stack | Notable / next step |
|---------------|----|-----------|--------------------|-----------|---------------------|

Then highlight high-value targets: management interfaces, outdated service versions,
exposed databases, default/misconfigured services, dev/staging in production.

### Step 8 — Record findings to the store

Append the notable surface findings from this sweep to the engagement's append-only
findings store at `$ENGAGEMENT_DIR/findings.jsonl`, so later phases (`recon-advisor`,
`attack-planner`, `report-generator`) can consume them without re-pasting. Log
**surface facts** — open ports, exposed/outdated services, web stacks, anonymous
shares — as `"status":"reported"` (usually `info`/`low`, higher when a management
interface or clearly outdated service is exposed). Never rewrite the file; one
compact JSON object per line:

```sh
printf '%s\n' '{"schema_version":"1.0","id":"F-0001","title":"Outdated Apache (2.4.29) on web host","target":"10.0.1.15","category":"web","severity":"medium","status":"reported","confidence":"high","exploitation":"unproven","evidence":["scans/nmap_svc_10-0-1-15_20260620_140000.txt"],"mitre":["T1046"],"source_agent":"full-recon","discovered_at":"'"$(date -u +%Y-%m-%dT%H:%M:%SZ)"'"}' >> "$ENGAGEMENT_DIR/findings.jsonl"
```

Rules:
- **Required fields:** `schema_version` ("1.0"), `id` (`F-NNNN` — next unused; check
  the file's existing ids first), `title`, `target`, `category`
  (`network|web|ad|cloud|container|host|credential|cicd|mobile|other`), `severity`
  (`info|low|medium|high|critical`), `status`, `source_agent` (`full-recon`),
  `discovered_at` (ISO-8601 UTC).
- List the evidence file(s) you saved in `evidence` (relative to `$ENGAGEMENT_DIR`, e.g. `scans/nmap_svc_…`).
- **Severity honesty:** surface facts are unexploited — set `exploitation:"unproven"` and keep severity modest (usually `info`/`low`). `/severity-calibrate` finalizes severity from the CVSS temporal score before reporting.
- Add `mitre` ATT&CK IDs when known; omit fields you don't have rather than guessing.

### Step 9 — Recommend next steps

- Hand specific findings to `recon-advisor` for deeper enumeration of a chosen host.
  When you have already logged a finding above, tell `recon-advisor` to **enrich that
  record (reuse its `id`)** with CVE/prioritization rather than re-reporting it, so a
  surface fact and its analysis stay one finding.
- For AWS-hosted targets, cross-reference open ports with `cloud-audit` security-group
  findings (a port open on the host but blocked by SG vs. genuinely internet-facing).
- Confirmed exploitation is a separate, explicitly authorized phase — this skill maps
  surface only.

Remind the user that evidence is in `$ENGAGEMENT_DIR/` and synced to the host.
