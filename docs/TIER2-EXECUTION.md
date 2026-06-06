# Tier 2 Execution Mode

## What Is Tier 2?

Tier 2 agents can compose and execute commands directly, instead of only suggesting them. When you ask the recon advisor to scan a subnet, it builds the command, explains it, and runs it after you approve. Then it parses the output, saves evidence, and recommends the next step.

Tier 1 (advisory mode) still works for every agent. You can paste output and get analysis without any execution. Tier 2 adds execution on top of the advisory capability.

## Safety Model

Two layers protect you from unintended execution:

### Layer 1: Prompt-Level Scope Enforcement

Before executing any command, a Tier 2 agent:

1. Requires you to declare an authorized scope (IP ranges, domains, URLs)
2. Validates every target in the command against your declared scope
3. Refuses commands targeting anything outside scope
4. Explains what the command does and tags its noise level (QUIET / MODERATE / LOUD)
5. Defaults to the least aggressive option (TCP connect over SYN scan, passive DNS over zone transfer)
6. Includes rate limits and timeouts to prevent accidental denial of service

This is a convenience layer, not a hard security boundary. Prompt-level enforcement can be worked around with creative phrasing. It catches honest mistakes and keeps the workflow disciplined.

### Layer 2: Claude Code Permission Gate

Every Bash command goes through Claude Code's built-in permission prompt. You see the full command before it runs. You approve or deny. This is the hard safety boundary. The agent cannot bypass it.

```
[MODERATE] Service scan:
  nmap -sT -sV -sC --top-ports 1000 --min-rate 100 --max-rate 1000
    --host-timeout 300s 10.10.1.0/24
    -oN nmap_10.10.1.0_services_20260330_140000.txt

▸ Allow Bash command? [y/n]
```

You are the final checkpoint. If a command looks wrong, deny it.

### What This Means in Practice

The safety model is identical to a human operator running tools: someone composes the command, someone reviews it, then it runs. The agent composes. You review. This is the same trust model as any pentest team where one person suggests commands and another executes them.

## Which Agents Support Tier 2?

### Currently Tier 2

| Agent | What It Executes | Risk Profile |
|-------|-----------------|--------------|
| **Recon Advisor** | nmap, dig, whois, curl, netcat, traceroute, whatweb, nikto, masscan | Low: read-only network reconnaissance |
| **Vuln Scanner** | nuclei, nikto, nmap NSE scripts | Low-Medium: vulnerability detection scans |
| **Web Hunter** | ffuf, gobuster, feroxbuster, sqlmap, dalfox, whatweb, curl | Medium: active web application testing |
| **Biz Logic Hunter** | curl, python3, httpie, custom request scripts | Medium: active web application logic testing |
| **PoC Validator** | curl, python3, custom PoC scripts, nuclei (targeted) | Medium: targeted vulnerability confirmation |
| **AD Attacker** | BloodHound, Impacket suite, CrackMapExec/NetExec, Certipy, ldapsearch, enum4linux, kerbrute | Medium-High: AD enumeration and Kerberos attacks |
| **Exploit Chainer** | python3, curl, custom exploit scripts, multi-step attack automation | High: chained exploit execution |
| **CI/CD Red Team** | git, docker, pipeline CLI tools, nuclei (staging targets) | Medium: pipeline validation and automated security testing |
| **Social Engineer** | GoPhish CLI, mail tooling, campaign infrastructure setup | Medium: phishing campaign tooling configuration |

### Planned Tier 2 (by rollout priority)

| Agent | What It Would Execute | Risk Profile |
|-------|----------------------|--------------|
| **Forensics Analyst** | volatility3, strings, file, xxd, sha256sum, exiftool, foremost, binwalk | Low: local file analysis only |
| **Malware Analyst** | file, strings, xxd, sha256sum, objdump, readelf, yara | Low: local static analysis only |
| **Detection Engineer** | sigma-cli (rule validation), python3 (rule testing) | Low: local validation only |
| **STIG Analyst** | reg query, auditpol, secedit, sysctl, config file checks | Low: local read-only system checks |
| **OSINT Collector** | dig, whois, curl (crt.sh), host, nslookup, subfinder, amass (passive) | Low: passive queries only |
| **Privesc Advisor** | id, whoami, uname, find (SUID/SGID), getcap, ps, ss, netstat, systeminfo | Medium: local enumeration on compromised host |
| **Cloud Security** | aws/az/gcloud CLI (read-only: iam, describe, list commands) | Medium: read-only cloud API calls |
| **CTF Solver** | curl, nc, python3, base64, xxd, file, strings, binwalk, exiftool | Medium: sandboxed CTF environments |
| **API Security** | curl, httpie, python3, jq | Medium: HTTP requests to in-scope APIs |

### Will Not Get Tier 2

| Agent | Why |
|-------|-----|
| **Exploit Guide** | Exploitation tools are high-risk. Methodology guidance is the right level of assistance. |
| **Wireless Pentester** | Wireless tools require hardware interaction (WiFi adapters in monitor mode). Not reproducible in the VM environment. |
| **Mobile Pentester** | Mobile tools require device connections and complex environment setup. Not reproducible in the VM environment. |
| **Credential Tester** | Password attacks carry high lockout risk. Methodology agent; execution covered by AD Attacker for spraying. |
| **Attack Planner** | Produces strategy documents, not commands. Coordinates findings from other agents. |
| **Bug Bounty Hunter** | Methodology and reporting agent. Recon tools covered by other Tier 2 agents. |
| **Engagement Planner** | Produces planning documents, not commands. |
| **Threat Modeler** | Produces threat analysis, not commands. |
| **Report Generator** | Produces written reports, not commands. |

## How to Use Execution Mode

### Step 1: Declare Scope

Tell the agent your authorized scope before asking it to run anything:

```
My authorized scope is 10.10.1.0/24 and the domain corp.local.
This is an internal network penetration test.
```

### Step 2: Ask for Scans

Ask naturally. The agent builds the command:

```
Run a service scan on the subnet, focus on common ports first.
```

### Step 3: Review and Approve

The agent shows you the command with a noise tag and explanation. Claude Code asks for permission. Approve or deny.

### Step 4: Iterate

After each scan, the agent analyzes results and suggests the next step. Approve the follow-up or redirect.

## How to Disable Execution Mode

If you want advisory-only behavior from a Tier 2 agent, two options:

**Option 1:** Just paste output instead of asking the agent to scan. Tier 2 agents still work in advisory mode for pasted data.

**Option 2:** Remove `Bash` from the agent's tool list in the YAML frontmatter:

```yaml
tools:
  - Read
  - Write
  - Edit
  - Grep
  - Glob
  # - Bash  ← removed
```

## How to Convert an Agent to Tier 2

If you are a contributor looking to add execution capability to an agent, the full step-by-step process is documented in [CONTRIBUTING.md](CONTRIBUTING.md) under "Adding Tier 2 Execution."

## Evidence Management

Run `/scope-declare` at the start of every session. It creates a per-engagement
subdirectory under `/engagements/` and writes the path into `scope.md`:

```
/engagements/acme-corp-external-2026/
  scope.md
  nmap_10.10.1.0_20260330_140000.txt
  dig_corp.local_20260330_140215.txt
  whois_example.com_20260330_140330.txt
```

All Tier 2 agents read the `Evidence directory:` line from `/engagements/scope.md`
and write every output file there using an absolute path. The `/engagements/`
folder is synced to the host — files appear on your host machine in real time and
survive snapshot restores.

**Why absolute paths matter.** Claude Code's Bash tool maintains CWD across tool
calls within a session. If any command changes directory (e.g., `cd /tmp`), a
relative filename silently saves evidence to the wrong location. Absolute paths
under `/engagements/{id}/` are CWD-immune.

At session end, evidence is already on the host at `engagements/{id}/` — no
manual transfer needed.

## Scope Guard Reference

The shared scope enforcement prompt text lives in `agents/_scope-guard.md`. This file is not a standalone agent (the underscore prefix prevents routing). It serves as the canonical source for the scope enforcement block that all Tier 2 agents incorporate.

When updating scope enforcement logic, update `_scope-guard.md` first, then propagate changes to each Tier 2 agent file.
