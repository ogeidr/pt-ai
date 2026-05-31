# full-recon

Full reconnaissance of in-scope hosts. Accepts targets as hostnames, IP addresses,
AWS-sourced EC2 instances, or Amazon WorkSpaces (VDI) endpoints; normalizes them to a
scoped target list, then runs host discovery, port and service scanning, DNS/WHOIS,
and web fingerprinting, saving per-host evidence. Read-only toward targets — no
exploitation, no writes to target systems. Default to the least aggressive option.

## Check scope, identity, and tools first

Use the read tool to check `/work/scope.md`. If it does not exist, STOP and tell the
user to run `/scope-declare` first.

Confirm identity (for AWS sourcing) and tools:

```
aws sts get-caller-identity --output json
for t in nmap masscan dig whois curl whatweb nikto nc; do command -v "$t"; done
```

You will validate EVERY resolved target against scope in the validation step before
scanning. If scope is ambiguous, ask the user to confirm boundaries first.

## Collect and normalize targets

Build one deduplicated list of `{identifier, ip(s), source}` from any mix of:

**(a) Direct hostnames / IPs** — for hostnames, resolve and record addresses:

```
dig +short HOSTNAME A; dig +short HOSTNAME AAAA
```

**(b) AWS EC2 instances** — pull from the in-scope account:

```
aws ec2 describe-instances --region REGION \
  --query 'Reservations[].Instances[].{Id:InstanceId,Name:Tags[?Key==`Name`]|[0].Value,State:State.Name,PrivateIP:PrivateIpAddress,PublicIP:PublicIpAddress,PublicDNS:PublicDnsName}' \
  --output json
```

**(c) Amazon WorkSpaces (VDI)** — directories, then workspaces (`IpAddress` is the
reachable, usually private, address):

```
aws workspaces describe-workspace-directories \
  --query 'Directories[].{DirId:DirectoryId,Name:DirectoryName,Type:DirectoryType,RegCode:RegistrationCode}' --output json

aws workspaces describe-workspaces \
  --query 'Workspaces[].{WsId:WorkspaceId,User:UserName,Computer:ComputerName,Ip:IpAddress,DirId:DirectoryId,State:State}' --output json
```

WorkSpaces/EC2 private IPs require network position inside/peered to the VPC — note
this to the user.

## Validate every target against scope (MANDATORY)

For each normalized target, confirm the IP/hostname falls within `/work/scope.md`.
DROP and report any out-of-scope target. Private IPs count only if scope covers that
range. Present the final in-scope target list to the user before scanning.

## OPSEC briefing

OPSEC: **MODERATE** for the default pipeline (TCP connect scans, banner grabs, HTTP
requests), rising to **LOUD** with vuln scanning (nikto) or aggressive NSE. Active
scanning is visible to IDS/IPS and, for AWS targets, VPC flow logs / GuardDuty. Confirm
depth before scanning.

## Run the recon pipeline (least aggressive first)

Per in-scope target, save raw output to a timestamped file (sanitize target: `/`->`-`).
Defaults: non-root `-sT`, rate-limited, timeouts.

```
# 1) Liveness / host discovery
nmap -sn TARGET -oN nmap_ping_{target}_{YYYYMMDD_HHMMSS}.txt

# 2) Service + default-script scan, top ports, rate-limited (MODERATE)
nmap -sT -sV -sC --top-ports 1000 \
  --min-rate 100 --max-rate 1000 --host-timeout 300s \
  TARGET -oN nmap_svc_{target}_{YYYYMMDD_HHMMSS}.txt

# 3) Full TCP port sweep when thoroughness is wanted (slower)
nmap -sT -p- --min-rate 100 --max-rate 1000 --host-timeout 600s \
  TARGET -oN nmap_allports_{target}_{YYYYMMDD_HHMMSS}.txt
```

For large in-scope ranges, discover with masscan first, then nmap the live hosts:

```
masscan TARGET_RANGE -p1-65535 --rate 1000 -oL masscan_{range}_{YYYYMMDD_HHMMSS}.txt
```

For hostnames, add name intelligence:

```
whois HOSTNAME                  > whois_{host}_{YYYYMMDD_HHMMSS}.txt
dig ANY HOSTNAME +noall +answer > dig_{host}_{YYYYMMDD_HHMMSS}.txt
```

When web ports (80/443/8080/8443) are open:

```
curl -sILk --connect-timeout 10 --max-time 30 http://TARGET/ > http_hdr_{target}_{YYYYMMDD_HHMMSS}.txt
whatweb -a 3 TARGET                                          > whatweb_{target}_{YYYYMMDD_HHMMSS}.txt
# nikto is LOUD — only with user opt-in:
# nikto -host TARGET -output nikto_{target}_{YYYYMMDD_HHMMSS}.txt
```

Rules: show each command and its OPSEC tag before running; offer a quieter alternative;
never pipe target-controlled output into a shell; stop and ask before any LOUD step
(full `-p-` at high rate, nikto, aggressive NSE).

## Save evidence

Keep all raw output files. Then write a consolidated summary:

- `fullrecon_{engagement}_{YYYYMMDD_HHMMSS}.md`

Header must note: engagement ID from `/work/scope.md`, target sources used
(direct / EC2 / WorkSpaces), the final in-scope target list, tools run, and timestamps.

## Present the consolidated recon summary

| Host (source) | IP | Open ports | Services / versions | Web stack | Notable / next step |
|---------------|----|-----------|--------------------|-----------|---------------------|

Highlight high-value targets: management interfaces, outdated versions, exposed
databases, default/misconfigured services, dev/staging in production.

## Recommend next steps

- Hand specific findings to the recon-advisor for deeper enumeration of a chosen host.
- For AWS targets, cross-reference open ports with cloud-audit security-group findings
  (open on host but blocked by SG vs. genuinely internet-facing).
- Confirmed exploitation is a separate, explicitly authorized phase — this skill maps
  surface only.

Remind the user to secure or transfer the evidence files at session end.
