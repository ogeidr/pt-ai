# Agent Guide

## What Are Claude Code Subagents?

Each agent is a Markdown file in `.claude/agents/` with a YAML frontmatter block (`name`, `description`, `model`, `tools`) and a system prompt below it. Claude Code reads the `description` to decide which agent to route your prompt to.

---

## Agent Reference

| Agent | Use case | Tier 2 | Key tip |
|-------|----------|--------|---------|
| **engagement-planner** | Scope, timeline, rules of engagement | — | Include environment size, tech stack, compliance requirements |
| **threat-modeler** | STRIDE, attack trees, architecture review | — | Describe components and data flows in detail |
| **attack-planner** | Correlate findings into attack chains | — | Paste all raw scan and BloodHound data |
| **swarm-orchestrator** | Engagement-lifecycle methodology reference (playbook) | — | Does NOT execute or delegate; to actually run an engagement use the `/engagement` skill |
| **recon-advisor** | Analyze scan output; run nmap/dig/whois/curl | ✓ | Paste real output; declare scope before execution |
| **osint-collector** | Passive OSINT, subdomain enum, target profiling | — | Specify passive-only vs. active |
| **vuln-scanner** | Run nuclei/nikto, parse CVEs, prioritize findings | ✓ | Paste existing output for analysis without rescanning |
| **web-hunter** | Directory brute force, SQLi, parameter fuzzing | ✓ | Name the tech stack for tailored wordlists |
| **api-security** | REST/GraphQL/OAuth/JWT testing methodology | — | Provide API docs or Swagger specs |
| **bizlogic-hunter** | Business logic flaws, race conditions, workflow bypass | ✓ | Describe the intended workflow before testing |
| **bug-bounty** | Bug bounty methodology, HackerOne/Bugcrowd reports | — | Paste the program scope for tailored guidance |
| **ad-attacker** | BloodHound, Kerberoasting, DCSync, NTLM relay | ✓ | Paste BloodHound output for concrete attack paths |
| **credential-tester** | Hash cracking, password spray, hashcat modes | — | Specify the hash type for precise mode numbers |
| **exploit-guide** | Exploitation technique methodology | — | Include target OS version and patch level |
| **exploit-chainer** | Multi-vulnerability chains, exploit automation | ✓ | Provide specific vuln details, not just types |
| **poc-validator** | Confirm findings, eliminate false positives | ✓ | Include scanner output and response snippets |
| **privesc-advisor** | Linux/Windows/container privilege escalation | — | Paste `id`, `sudo -l`, `uname` output |
| **cloud-security** | AWS/Azure/GCP IAM analysis, cloud attack paths | — | Paste IAM policies for concrete escalation paths |
| **cicd-redteam** | CI/CD pipeline security testing | ✓ | Specify CI platform and authorized environments |
| **mobile-pentester** | Android/iOS app testing, Frida, cert pinning | — | Specify platform and available testing environment |
| **wireless-pentester** | WiFi/BT attacks, WPA2/WPA3, evil twin | ✓ | Wireless testing requires separate written authorization |
| **social-engineer** | Phishing, vishing, pretexting campaigns | ✓ | Requires explicit authorization beyond standard pentest scope |
| **detection-engineer** | Sigma, SPL, KQL detection rules | — | Specify SIEM platform and available log sources |
| **stig-analyst** | STIG compliance, remediation, keep-open justifications | — | Reference specific V-XXXXXX IDs |
| **forensics-analyst** | DFIR, evidence acquisition, timeline analysis | — | Paste Volatility/Plaso output directly |
| **malware-analyst** | Static/dynamic analysis, IOC extraction | — | Always work from an isolated environment |
| **report-generator** | Professional pentest reports, executive summaries | — | Specify audience: technical team vs. executives |

**Tier 2 (✓)** agents have the `Bash` tool enabled and compose and execute commands directly after you approve each one. **Advisory (—)** agents analyze pasted data and produce guidance but do not run commands.

**Why some agents stay advisory:** `exploit-guide` and `wireless-pentester` carry high unintended-impact risk or require hardware; `credential-tester` risks account lockouts; `threat-modeler`, `attack-planner`, and `report-generator` produce documents, not commands.

---

## Execution Mode

### Safety model

Two layers protect you from unintended execution:

**Layer 1 — Prompt-level scope enforcement.** Before composing any command, a Tier 2 agent requires a declared authorized scope, validates every target against it, explains what the command does and what it connects to, tags its noise level (QUIET / MODERATE / LOUD), and defaults to the least aggressive option. This catches honest mistakes and keeps the workflow disciplined. It is a convenience layer, not a hard security boundary.

**Layer 2 — Claude Code permission gate.** Every Bash command goes through Claude Code's built-in approval prompt. You see the full command before it runs. You approve or deny. This is the hard boundary — the agent cannot bypass it.

```
[MODERATE] Service scan:
  nmap -sT -sV -sC --top-ports 1000 --min-rate 100 --max-rate 1000
    --host-timeout 300s 10.10.1.0/24
    -oN /engagements/acme-2026/nmap_10.10.1.0_20260606_140000.txt

▸ Allow Bash command? [y/n]
```

### How to use

1. Run `/scope-declare` — sets the engagement ID and creates `/engagements/{id}/`
2. Ask naturally — the agent composes the command, explains it, and tags the noise level
3. Read the command, then approve or deny at the Claude Code prompt
4. The agent analyzes results, saves evidence, and suggests the next step

To disable execution mode on any agent, remove `Bash` from its `tools` list in the YAML frontmatter. See [CUSTOMIZATION.md](CUSTOMIZATION.md) for details.

### Evidence

`/scope-declare` writes `/engagements/scope.md` with an `Evidence directory:` line pointing to the per-engagement subdirectory. All Tier 2 agents read that line and write every output file there as an absolute path. The `/engagements/` folder is synced to the host — evidence appears in real time and survives VM snapshot restores.

---

## Workflow Chaining

The agents are designed to work together across the phases of a complete engagement.

### Phase 0: Threat Modeling (Optional Pre-Engagement)

Before scoping, use `threat-modeler` to understand the attack surface from an architectural perspective.

```
Threat model the client's three-tier web application — React frontend, Java
Spring Boot API, PostgreSQL on AWS RDS. Identify the highest-risk components
and attack vectors so we can prioritize our scope.
```

### Phase 1: Planning

Use `engagement-planner` to define scope, rules of engagement, and methodology.

```
Plan a two-week internal penetration test for Acme Corp's corporate network.
The scope includes 10.0.0.0/8 and all Active Directory domains. Exclude the
10.0.50.0/24 production database subnet.
```

### Phase 2: Reconnaissance

Run OSINT and passive recon with `osint-collector` before touching the network. Then feed active scan results to `recon-advisor` for prioritization.

```
# OSINT first (passive, no target interaction)
Build an OSINT profile for acmecorp.com. I need subdomains, employee names,
email patterns, and technology stack from public sources only.

# Then active recon analysis
Here is the Nmap scan output for the first three subnets. Identify high-value
targets and recommend an attack path. [paste output]
```

### Phase 3: Vulnerability Assessment

Use `vuln-scanner` to run targeted scans against identified high-value hosts, then `poc-validator` to eliminate false positives before investing time in exploitation.

```
# Scan high-value targets identified by recon
Run a nuclei scan against 10.0.1.10-20 focusing on the services recon-advisor
flagged as high priority.

# Validate findings before acting on them
Nuclei reported CVE-2021-41773 on 10.0.1.15. Write a safe PoC to confirm it
before I include it in the attack plan.
```

### Phase 4: Attack Planning

Feed all findings into `attack-planner` to build the optimal exploitation path before executing anything.

```
Here are my recon findings, vulnerability scan results, and BloodHound data
from the first week of this engagement. Build me an attack chain that gets
to Domain Admin with the lowest detection risk.
```

### Phase 5: Exploitation

Route to the appropriate specialist based on the attack vector.

```
# Kerberoasting
The recon phase identified several SPNs for service accounts. Walk me through
Kerberoasting these accounts and what detection I should expect.

# Web exploitation
Run a directory brute force against the web app on 10.0.1.15 and test the
login endpoint for injection vulnerabilities.

# Post-compromise escalation
I have a shell as www-data on the DMZ web server. Walk me through the Linux
privilege escalation checklist.
```

### Phase 6: Credential and Lateral Movement

Use `credential-tester` for hash cracking and password analysis, `ad-attacker` for lateral movement and domain dominance.

```
# Crack harvested hashes
Here are the NTLM hashes from the compromised host's SAM database. Walk me
through cracking them with hashcat using the best rule set.

# Lateral movement
I have Domain User credentials and a BloodHound graph. Identify the shortest
path to Domain Admin and walk me through the attacks.
```

### Phase 7: Detection Engineering

After testing is complete, use `detection-engineer` to produce detection rules for the techniques you successfully used.

```
During testing I successfully performed Kerberoasting, DCSync, and Golden Ticket
attacks. Create Sigma rules for detecting each of these techniques.
```

### Phase 8: Compliance Mapping

If the engagement includes compliance requirements, use `stig-analyst` to map findings to STIG controls.

```
Map the Active Directory findings from our assessment to relevant STIG controls
and provide remediation steps for each.
```

### Phase 9: Report Generation

Use `report-generator` to compile everything into a professional deliverable.

```
Compile the following findings into a professional penetration test report.
Include an executive summary, methodology section, and findings ranked by
severity with remediation recommendations. [paste findings]
```

### Full-Engagement Automation

For engagements where you want real, automated agent handoffs, use the
**`/engagement` skill** — not `swarm-orchestrator`. The skill runs in the main
thread, so it can use the `Task` tool to delegate to each specialist agent in turn;
a subagent (which is what `swarm-orchestrator` becomes when invoked) cannot spawn
other subagents, so it can only describe the lifecycle, never run it.

`/engagement` is **operator-gated**: it emits a per-delegation scope envelope,
records phase state in `gates.jsonl`, and stops for your explicit approval at every
phase transition (and a hard gate before exploitation). Every command a delegated
agent composes still goes through Claude Code's per-command permission prompt.

```
/scope-declare      # set engagement id, scope, written-authorization = yes
/engagement         # confirm the authorized agent set, then approve each phase
```

> **opencode note:** opencode has no `Task` tool, so there is no automated fan-out
> there. Under opencode, drive the lifecycle by hand using `swarm-orchestrator` as
> the playbook and invoking each agent in turn.

---

## General Tips

- **Declare scope first.** Run `/scope-declare` at the start of every session before asking any Tier 2 agent to execute commands.
- **Paste real tool output.** The agents are designed to analyze actual data. Copy and paste Nmap scans, BloodHound output, error messages, and configuration files directly.
- **Provide engagement context.** Tell the agent whether this is an internal test, external test, web app assessment, red team, or compliance audit. Context shapes the response.
- **Review every command.** Claude Code shows you the full command before it runs. Read it. If it looks wrong, deny it and ask the agent to explain its reasoning.
- **Chain agents deliberately.** The output from one agent often serves as ideal input for the next. Copy relevant output and paste it into your next prompt for the following phase.
- **Start a fresh session per phase.** Token cost grows with conversation length. Starting a new Claude Code session for each major phase (recon, exploitation, reporting) keeps costs down and context clean.
