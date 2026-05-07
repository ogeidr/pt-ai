# Agent Guide

## What Are Claude Code Subagents?

Each agent is a Markdown file in `.claude/agents/` with a YAML frontmatter block (`name`, `description`, `model`, `tools`) and a system prompt below it. Claude Code reads the `description` to decide which agent to route your prompt to.

---

## Agent Details

### engagement-planner

**When it activates:** When you ask about planning, scoping, or organizing a penetration test or red team engagement.

**What it does:** Helps you define the scope, timeline, methodology, and rules of engagement for security assessments. Maps engagement objectives to MITRE ATT&CK techniques and provides structured planning documents.

**Example prompts:**

- "Plan an internal network pentest for a 500-endpoint Active Directory environment with a two-week timeline."
- "Create a rules of engagement template for an external web application assessment."
- "Map our engagement objectives to MITRE ATT&CK techniques for a cloud-focused red team exercise."
- "What should the scope exclusions look like for a healthcare organization pentest?"

**Tips for best results:** Provide details about the target environment size, technology stack, compliance requirements, and timeline constraints. The more context you give, the more tailored the plan will be.

---

### threat-modeler

**When it activates:** When you ask about threat modeling, attack surface analysis, STRIDE, DREAD, attack trees, data flow diagrams, trust boundaries, or security architecture review.

**What it does:** Systematically decomposes systems into their components, identifies threats against each component using STRIDE and attack tree analysis, scores risk, and produces actionable remediation guidance. Maps every identified threat to MITRE ATT&CK techniques. Distinguishes between quick-win mitigations and long-term architectural fixes.

**Example prompts:**

- "Threat model a three-tier web application with a React frontend, Node.js API, and PostgreSQL database hosted on AWS."
- "Run a STRIDE analysis on our authentication service and identify the highest-risk threats."
- "Draw a data flow diagram for our payment processing pipeline and identify trust boundaries."
- "What are the supply chain risks in our CI/CD pipeline and how would you prioritize remediating them?"

**Tips for best results:** Describe the system architecture in detail — components, data flows, protocols, authentication mechanisms, and deployment environment. The more context you provide, the more precise the threat enumeration will be.

---

### attack-planner

**When it activates:** When you want to correlate findings from multiple tools or agents, build multi-step attack chains, identify the optimal exploitation path through a network, or plan lateral movement strategies.

**What it does:** Correlates findings from reconnaissance, vulnerability scanning, and enumeration tools to build end-to-end attack paths. Thinks adversarially to identify the lowest-effort, highest-impact path through a target environment. Produces attack chain narratives with MITRE ATT&CK mapping that demonstrate real business risk.

**Example prompts:**

- "Here are my Nmap results, BloodHound graph, and nuclei findings. Build me an attack chain to Domain Admin."
- "Given these five vulnerabilities, which combination creates the best lateral movement path?"
- "I have foothold on a DMZ host. Plan the attack path to reach the internal database subnet."
- "Map this engagement's findings to MITRE ATT&CK and identify gaps in our coverage."

**Tips for best results:** Provide as much raw data as possible — paste scan output, BloodHound findings, credential test results, and any other enumeration data. The richer the input, the more precise the attack chain.

---

### swarm-orchestrator

**When it activates:** When you want to coordinate multiple pentest agents as a team, run a full automated red team engagement, or execute a complete pentest lifecycle from planning through reporting with autonomous agent delegation.

**What it does:** Acts as the red team lead, delegating tasks to specialist agents and synthesizing their output into a coordinated engagement. Manages handoffs between agents, tracks progress across parallel workstreams, and compiles results into a unified picture. Does not execute scans or exploits directly — it manages the agents that do. Requires scope declaration and operator approval before each major phase transition.

**Example prompts:**

- "Run a full red team engagement against corp.local. Scope: 10.0.0.0/8 and all corp.local subdomains."
- "Coordinate the recon and vulnerability assessment phases for this engagement and hand the findings to the attack planner."
- "I have completed recon. Orchestrate the exploitation phase using the findings from recon-advisor."
- "Compile all agent outputs from this engagement into a final report."

**Tips for best results:** Use swarm-orchestrator for full-engagement orchestration, not single-agent tasks. Invoke individual agents directly for focused work. Declare your scope clearly at the start — the orchestrator enforces scope verification before delegating to each agent.

---

### recon-advisor

**When it activates:** When you share scan output, ask about reconnaissance methodology, or need help analyzing enumeration data.

**What it does:** Analyzes output from reconnaissance tools (Nmap, BloodHound, enum4linux, etc.), identifies high-value targets, prioritizes attack vectors, and recommends next steps based on what the data reveals. In Tier 2 mode, can compose and execute reconnaissance commands directly after you approve each one.

**Example prompts:**

- "Analyze this Nmap output and identify high-value targets for lateral movement. [paste output]"
- "Review this BloodHound data and identify the shortest path to Domain Admin."
- "I ran enum4linux against 10.0.0.5. Here are the results. What should I target next? [paste output]"
- "Prioritize these open services for an internal network assessment. [paste service list]"

**Tips for best results:** Paste actual tool output directly into your prompt. The agent works best when it can analyze real data rather than hypothetical scenarios. Include context about the engagement type (internal, external, web app) to get more relevant prioritization.

---

### osint-collector

**When it activates:** When you ask about OSINT, reconnaissance, information gathering, target profiling, email harvesting, subdomain enumeration, social media recon, breach data, or building a target dossier for an authorized engagement.

**What it does:** Guides systematic open source intelligence collection from publicly available sources. Covers passive DNS enumeration, certificate transparency logs, Google dorking, social media profiling, breach data analysis, and employee enumeration. Labels every technique as passive or active so you understand detection risk. Advisory mode only — does not execute commands.

**Example prompts:**

- "Build an OSINT profile for target.com — subdomains, email patterns, employee names, and technology stack."
- "What Google dorks would reveal exposed admin panels and configuration files for this domain?"
- "Walk me through passive subdomain enumeration using certificate transparency logs."
- "How do I identify employee email addresses from LinkedIn without alerting the target?"

**Tips for best results:** Specify whether you need passive-only collection (no interaction with the target) or can tolerate active techniques. For external assessments with strict rules of engagement, passive-only is the safer default.

---

### vuln-scanner

**When it activates:** When you want to run vulnerability scans, identify CVEs in target systems, use tools like nuclei or nikto, parse scan results, or prioritize vulnerabilities for exploitation.

**What it does:** Identifies, validates, and prioritizes vulnerabilities across network services, web applications, and infrastructure using industry-standard scanning tools. In Tier 2 mode, composes and executes scan commands directly after you approve each one, then parses output and recommends next steps. Requires scope declaration before any execution.

**Example prompts:**

- "Run a nuclei scan against the web servers in 10.10.1.0/24 and prioritize the findings."
- "Analyze this Nessus export and tell me which findings are most likely to be exploitable."
- "Scan this target for CVEs related to the Apache version identified in the Nmap output."
- "What nuclei templates should I run first for a quick-win vulnerability sweep?"

**Tips for best results:** Declare your authorized scope before asking for scans. Paste existing scan output for analysis if you have it — the agent can prioritize and cross-reference findings without running additional scans.

---

### web-hunter

**When it activates:** When you want to perform web application penetration testing, run directory brute forcing, test for SQL injection, discover hidden endpoints, fuzz parameters, or perform active web application security testing.

**What it does:** Discovers hidden content, identifies injection points, tests authentication mechanisms, and maps web application attack surfaces using tools like ffuf, gobuster, feroxbuster, sqlmap, and dalfox. In Tier 2 mode, composes and executes web testing commands directly after you approve each one. Requires scope declaration before any execution.

**Example prompts:**

- "Run a directory brute force against https://target.example.com and look for admin panels."
- "Test this login form for SQL injection and tell me what parameters look injectable."
- "What ffuf flags would you use to find hidden API endpoints on a Laravel application?"
- "Analyze this Burp Suite export and identify the highest-priority injection points to test."

**Tips for best results:** Specify the tech stack when known (e.g., Laravel, Django, Spring Boot) — the agent will tailor wordlists and test cases to that framework. Declare scope before requesting execution.

---

### api-security

**When it activates:** When you ask about API security testing, REST API attacks, GraphQL exploitation, OAuth/OIDC vulnerabilities, JWT attacks, or web service penetration testing methodology.

**What it does:** Provides methodology guidance for authorized API penetration testing following the OWASP API Security Top 10 (2023). Covers broken object level authorization (BOLA), JWT algorithm confusion, OAuth flow attacks, GraphQL introspection and injection, API key discovery, and rate limit bypass. Advisory mode only — does not execute commands.

**Example prompts:**

- "Walk me through testing for BOLA vulnerabilities in a REST API that uses integer IDs."
- "This JWT is using HS256. What attacks should I attempt and what tools should I use?"
- "Explain the methodology for testing OAuth authorization code flows for redirect URI manipulation."
- "How do I enumerate a GraphQL schema and test it for injection vulnerabilities?"

**Tips for best results:** Provide API documentation, Swagger/OpenAPI specs, or example requests if you have them. The agent can tailor attack guidance to the specific API design rather than giving generic advice.

---

### bizlogic-hunter

**When it activates:** When you want to test for business logic flaws, workflow bypass vulnerabilities, price manipulation, payment tampering, race conditions in transactions, or authorization boundary failures that standard vulnerability scanners miss.

**What it does:** Identifies logic errors in application workflows by understanding how the application is supposed to work and finding clever ways to break those rules. Covers price manipulation, workflow bypassing, race condition exploitation, role boundary testing, and multi-step transaction abuse. In Tier 2 mode, can execute targeted HTTP requests after scope declaration and approval. Advisory mode available for general methodology.

**Example prompts:**

- "Walk me through testing a shopping cart for price manipulation and quantity tampering."
- "How do I test for race conditions in a discount code redemption flow?"
- "The app has three user roles: user, moderator, and admin. Walk me through authorization boundary testing."
- "How would I test a multi-step account registration flow for logic bypass?"

**Tips for best results:** Describe the application's intended business workflow — the agent needs to understand the rules before it can help you break them. Screenshots, Burp history, or API documentation are all useful context.

---

### bug-bounty

**When it activates:** When you are working on bug bounty programs, submitting to HackerOne or Bugcrowd, need help with bug bounty methodology, or need help writing quality vulnerability reports for bounty submissions.

**What it does:** Guides efficient vulnerability hunting within bug bounty program scopes. Covers target selection, high-value asset identification, duplicate avoidance, and report writing that gets accepted and paid. Understands the economics and culture of bug bounty programs — triaging quickly, writing clear impact statements, and building relationships with security teams. Advisory mode only.

**Example prompts:**

- "Help me write a vulnerability report for a stored XSS finding on HackerOne that clearly communicates impact."
- "I'm starting on this program — here's the scope. Where should I focus first for the best ROI?"
- "Walk me through the methodology for finding IDOR vulnerabilities in a REST API target."
- "How do I determine if a finding is a duplicate before submitting, and what do I do if it is?"

**Tips for best results:** Paste the program's scope and rules of engagement for tailored guidance. For report writing, provide the full technical details of the finding — the agent needs the vulnerability, reproduction steps, and impact to write a quality report.

---

### ad-attacker

**When it activates:** When you want to perform Active Directory attacks, run BloodHound analysis, use Impacket tools, execute Kerberos attacks, perform AD enumeration with CrackMapExec or NetExec, or test AD delegation abuse during authorized engagements.

**What it does:** Enumerates, attacks, and demonstrates impact in Active Directory environments. Covers Kerberoasting, AS-REP Roasting, DCSync, NTLM relay, Silver/Golden/Diamond Ticket attacks, BloodHound path analysis, ADCS attacks, and lateral movement via Impacket. In Tier 2 mode, composes and executes AD attack commands directly after scope declaration and your approval.

**Example prompts:**

- "Run BloodHound against corp.local and identify the shortest path to Domain Admin."
- "Walk me through Kerberoasting the service accounts I found in the Nmap output."
- "Analyze this BloodHound JSON export and identify the most exploitable privilege escalation paths."
- "Explain the methodology for ADCS ESC1 exploitation and what artifacts it leaves."

**Tips for best results:** Declare your authorized scope (domain names, IP ranges, specific DCs) before requesting execution. Paste BloodHound output or enumeration results for analysis — the agent is most effective when working from real data.

---

### credential-tester

**When it activates:** When you ask about password attacks, credential testing, hash cracking, brute force methodology, default credential checks, password spraying, or tools like hashcat, John the Ripper, Hydra, or CrackMapExec.

**What it does:** Provides detailed guidance on password attacks, hash cracking, credential reuse testing, and authentication bypass techniques. Covers online attacks (Hydra, CrackMapExec), offline cracking (hashcat, John), password spraying with lockout awareness, and credential stuffing. Advisory mode only — execution of credential attacks is handled by ad-attacker for Active Directory targets.

**Example prompts:**

- "Here are the hashes I extracted from the SAM database. Walk me through cracking them with hashcat."
- "What is the correct hashcat mode for NTLMv2 and what wordlists and rules should I use?"
- "How do I perform a password spray against an Office 365 tenant without triggering lockouts?"
- "I found default credentials in a vendor manual. How do I test them safely without causing lockouts?"

**Tips for best results:** Specify the hash type when known (NTLM, NTLMv2, bcrypt, SHA-1, etc.) for precise tool flags and mode numbers. For spraying, always ask about lockout thresholds first — the agent will help you stay under the limit.

---

### exploit-guide

**When it activates:** When you ask about exploitation techniques, attack methodologies, or need guidance on a specific attack vector.

**What it does:** Provides step-by-step methodology guidance for exploitation techniques with a dual offensive/defensive perspective. For each technique, it covers the attack methodology, required tools, detection opportunities, and defensive mitigations.

**Example prompts:**

- "Walk me through Kerberoasting methodology and how blue teams can detect it."
- "Explain the methodology for NTLM relay attacks in a modern Active Directory environment."
- "How would I approach exploiting a misconfigured ADCS (Active Directory Certificate Services) instance?"
- "What is the methodology for Silver Ticket attacks and what artifacts do they leave?"

**Tips for best results:** Specify the target environment details (OS versions, patch levels, security tools in place) for more relevant guidance. Ask about detection alongside exploitation to get the full offensive/defensive picture.

---

### exploit-chainer

**When it activates:** When you want to chain multiple vulnerabilities into a complete attack sequence, build an automated exploit workflow, or demonstrate full kill-chain exploitation from initial access to objective completion.

**What it does:** Takes individual vulnerability findings and builds end-to-end automated exploit chains. Combines multiple lower-severity issues into high-impact attack sequences, writes exploit automation scripts, and validates each step. In Tier 2 mode, can compose and execute exploit chain steps after scope declaration and approval of every command.

**Example prompts:**

- "I have an SSRF and a metadata service endpoint. Chain these into credential theft and cloud lateral movement."
- "Chain this path traversal with the local file inclusion to achieve RCE on the target."
- "Build an automated exploit script that chains the SQL injection finding into admin account takeover."
- "I have these four medium findings. Can they be chained into a critical impact scenario?"

**Tips for best results:** Provide the specific vulnerability details, not just the type — include the endpoint, parameter, and any existing PoC. The agent builds chains from concrete findings, not hypothetical scenarios.

---

### poc-validator

**When it activates:** When you want to validate a vulnerability finding with a safe Proof of Concept, eliminate false positives from scan results, or verify that a reported bug is real before including it in a pentest report.

**What it does:** Generates minimal, non-destructive PoC scripts for reported vulnerabilities, executes them after scope declaration and approval, and confirms whether the finding is real. Specializes in false positive elimination — it distinguishes between scanner noise and confirmed vulnerabilities. In Tier 2 mode, executes PoC scripts directly after approval.

**Example prompts:**

- "Nuclei reported a CVE-2021-41773 on this Apache server. Write a safe PoC to confirm it."
- "I have 47 scanner findings. Help me quickly validate which ones are real vs false positives."
- "Write a non-destructive PoC for this SQL injection finding that proves it's exploitable without damaging data."
- "How do I safely demonstrate impact for this XXE finding without reading sensitive server files?"

**Tips for best results:** Provide the full finding details from the scanner, including the URL, parameter, and response snippet. The agent writes PoCs that prove the vulnerability is real while avoiding unintended damage to the target.

---

### privesc-advisor

**When it activates:** When you ask about privilege escalation techniques, local enumeration, Linux or Windows privilege escalation, container escape, or need help escalating access on a compromised system during authorized testing.

**What it does:** Guides systematic local enumeration and privilege escalation on Linux, Windows, and container environments. Covers SUID/SGID abuse, sudo misconfigurations, capabilities, cron exploitation, token impersonation, unquoted service paths, DLL hijacking, container escapes, and kernel exploits. Advisory mode only — provides commands to run manually on your compromised host.

**Example prompts:**

- "I have a shell as www-data on an Ubuntu 22.04 server. Walk me through the privilege escalation checklist."
- "Here is the output of sudo -l on this Linux host. What can I exploit?"
- "I'm running as a low-privileged service account on Windows Server 2019. What escalation paths should I check?"
- "I have a shell inside a Docker container. How do I determine if container escape is possible?"

**Tips for best results:** Paste the output of enumeration commands (id, sudo -l, uname -a, ps aux, etc.) for targeted guidance. The agent gives much more precise recommendations when it can see your actual environment rather than working from hypotheticals.

---

### cloud-security

**When it activates:** When you ask about cloud security testing, AWS/Azure/GCP penetration testing, cloud misconfiguration analysis, IAM privilege escalation, container security, Kubernetes attacks, serverless security, or cloud-native attack paths.

**What it does:** Provides methodology guidance for authorized cloud security assessments across AWS, Azure, and GCP. Covers IAM policy analysis and privilege escalation paths, S3/Blob/GCS misconfiguration, instance metadata exploitation, container and Kubernetes attacks, serverless security testing, and cloud-native detection evasion. Advisory mode — references cloud CLI tools and scripts but does not execute them.

**Example prompts:**

- "Analyze this AWS IAM policy and identify privilege escalation paths to AdministratorAccess."
- "Walk me through the methodology for enumerating an Azure tenant after obtaining an OAuth token."
- "Here is the output of aws iam list-attached-user-policies. What can I escalate with these permissions?"
- "Explain the methodology for exploiting the EC2 instance metadata service and what data it exposes."

**Tips for best results:** Paste IAM policies, CLI output, or configuration data directly — the agent can analyze specific policies and identify concrete escalation paths. Specify which cloud provider and which services are in scope.

---

### cicd-redteam

**When it activates:** When you want to integrate red teaming into CI/CD pipelines, set up continuous automated security testing on every code push, generate pipeline configurations for automated pentesting, or build a continuous red team capability.

**What it does:** Integrates security testing directly into CI/CD workflows so that every deployment triggers an automated security assessment. Generates pipeline configurations for GitHub Actions, GitLab CI, Jenkins, and other platforms. Covers secret scanning, SAST integration, container image scanning, and automated Nuclei scans against staging environments. In Tier 2 mode, can execute pipeline validation commands after scope declaration and approval.

**Example prompts:**

- "Generate a GitHub Actions workflow that runs nuclei against our staging environment on every PR."
- "Build a GitLab CI pipeline that scans Docker images for CVEs and fails the build on critical findings."
- "How do I integrate SAST into our Jenkins pipeline without adding more than 5 minutes to build time?"
- "Set up a continuous secret scanning job that catches leaked API keys before they reach main."

**Tips for best results:** Specify your CI/CD platform, existing pipeline structure, and what environments are authorized for automated testing. For staging environment scanning, declare scope explicitly before asking for pipeline configurations with real target URLs.

---

### mobile-pentester

**When it activates:** When you ask about mobile application security testing, Android pentesting, iOS pentesting, APK analysis, IPA analysis, mobile API testing, certificate pinning bypass, or mobile reverse engineering.

**What it does:** Guides Android and iOS application security testing following the OWASP MASTG and MASVS. Covers APK/IPA static analysis, decompilation and reverse engineering, dynamic analysis with Frida, certificate pinning bypass, traffic interception, data storage analysis, and authentication testing. Advisory mode only — provides commands and scripts to run in your own testing environment.

**Example prompts:**

- "Walk me through extracting and decompiling this APK to find hardcoded credentials and API keys."
- "How do I bypass certificate pinning on an Android app using Frida?"
- "Analyze this AndroidManifest.xml and identify exported components that could be abused."
- "What is the MASTG methodology for testing local data storage on iOS?"

**Tips for best results:** Specify the platform (Android/iOS), app type (native/React Native/Flutter/Cordova), and what testing environment you have available (rooted device, emulator, jailbroken iPhone). Provide the manifest or decompiled code snippets for specific analysis.

---

### wireless-pentester

**When it activates:** When you ask about wireless security testing, WiFi pentesting, WPA/WPA2/WPA3 attacks, Bluetooth security, wireless reconnaissance, rogue access points, or evil twin attacks.

**What it does:** Guides WiFi, Bluetooth, and RF security testing from reconnaissance through exploitation and post-exploitation. Covers passive and active wireless scanning, WPA2 handshake capture and cracking, WPA3 SAE attacks, evil twin setup, client deauthentication, PMKID attacks, and Bluetooth enumeration. Advisory mode only — wireless tools require hardware-specific setup that must be performed locally.

**Example prompts:**

- "Walk me through capturing a WPA2 4-way handshake and cracking it with hashcat."
- "How do I set up an evil twin attack against a WPA2 Enterprise network?"
- "What is the methodology for testing WPA3 networks for SAE vulnerabilities?"
- "Walk me through a Bluetooth Low Energy security assessment — enumeration through characteristic exploitation."

**Tips for best results:** Specify your wireless adapter and whether it supports monitor mode and packet injection. Include the target network details (security type, band, BSSID if known) for targeted guidance. Always confirm your authorized scope includes wireless testing, as it often requires separate written approval.

---

### social-engineer

**When it activates:** When you ask about social engineering, phishing campaigns, pretexting, vishing, physical social engineering, security awareness testing, or human-factor security assessments.

**What it does:** Provides methodology guidance for authorized human-factor attack campaigns. Covers phishing infrastructure setup, spearphishing email crafting, pretexting scenarios for vishing, physical social engineering tactics, and security awareness program design. Generates campaign plans, pretext scripts, and email templates for authorized testing. In Tier 2 mode, can assist with campaign tooling configuration after scope declaration and approval.

**Example prompts:**

- "Design a spearphishing campaign targeting the finance team for an authorized red team engagement."
- "Write a pretext script for a vishing call impersonating IT support to collect credentials."
- "What metrics should we collect in a security awareness phishing simulation?"
- "Build a physical social engineering scenario for testing badge access controls at a corporate office."

**Tips for best results:** Social engineering testing requires explicit written authorization beyond a standard pentest scope — confirm this is covered before requesting campaign guidance. Specify the target audience, campaign objectives, and any restrictions (e.g., no credential harvesting, simulation only).

---

### detection-engineer

**When it activates:** When you ask about creating detection rules, building alerts, or writing queries for security monitoring platforms.

**What it does:** Generates detection rules in multiple formats including Sigma (platform-agnostic), Splunk SPL, and KQL (Microsoft Sentinel/Defender). Rules include descriptions, severity ratings, MITRE ATT&CK mappings, and tuning recommendations.

**Example prompts:**

- "Create a detection rule for DCSync attacks in Sigma and Splunk SPL format."
- "Write a KQL query to detect Kerberoasting activity in Microsoft Sentinel."
- "Build a Sigma rule for detecting suspicious scheduled task creation used for persistence."
- "Create a detection rule for LSASS memory access that minimizes false positives."

**Tips for best results:** Specify the detection platform you are using (Splunk, Sentinel, Elastic, etc.) and any constraints such as available log sources. Mention if you need tuning guidance to reduce false positives in specific environments.

---

### stig-analyst

**When it activates:** When you ask about STIG (Security Technical Implementation Guide) compliance, specific STIG IDs, or need remediation or justification guidance.

**What it does:** Analyzes specific STIG requirements, provides GPO-based and command-line remediation steps, helps write keep-open (risk acceptance) justifications, and explains the security impact of findings.

**Example prompts:**

- "Analyze V-220768 and provide GPO remediation steps."
- "Write a keep-open justification for V-254243 where the application requires the insecure configuration."
- "What are the CAT I STIG findings most commonly found in Windows Server 2022 environments?"
- "Explain the security impact of V-220712 and provide both GPO and PowerShell remediation."

**Tips for best results:** Reference specific STIG IDs (V-XXXXXX format) for the most precise guidance. Provide context about why a finding cannot be remediated if you need a keep-open justification, as the quality of the justification depends on the business context.

---

### forensics-analyst

**When it activates:** When you ask about digital forensics, incident response, evidence acquisition, memory forensics, disk forensics, network forensics, timeline analysis, or chain of custody.

**What it does:** Guides evidence acquisition, analysis, and reporting while maintaining forensic soundness and chain of custody. Covers disk imaging and hash verification, memory acquisition and analysis with Volatility, network packet analysis, log correlation and timeline reconstruction, and DFIR report writing. Every recommendation prioritizes evidence integrity and legal defensibility. Advisory mode only.

**Example prompts:**

- "Walk me through acquiring forensic memory from a running Windows host using WinPmem."
- "Analyze this Volatility output from a compromised Linux host and identify indicators of compromise."
- "How do I build a forensic timeline from Windows event logs, Prefetch, and NTFS MFT records?"
- "What is the correct chain of custody procedure for seizing a running server in an active incident?"

**Tips for best results:** Paste tool output (Volatility, Plaso, Autopsy) directly for specific analysis guidance. For incident response scenarios, describe the suspected attack type and available evidence sources — the agent will prioritize the most relevant forensic artifacts.

---

### malware-analyst

**When it activates:** When you ask about malware analysis, reverse engineering, binary analysis, disassembly, debugging, sandbox analysis, static analysis, dynamic analysis, or suspicious file triage.

**What it does:** Guides static and dynamic malware analysis, indicator of compromise extraction, and threat intelligence production from suspicious samples. Covers file identification and triage, strings extraction, PE header analysis, disassembly with Ghidra and IDA, sandbox detonation interpretation, network traffic analysis, and MITRE ATT&CK behavior mapping. Always works from isolated environments. Advisory mode only.

**Example prompts:**

- "Walk me through triaging this suspicious PE binary — what should I check first?"
- "Analyze this strings output and identify the IOCs, C2 indicators, and persistence mechanisms."
- "Explain how to set up an isolated dynamic analysis environment for detonating this sample safely."
- "Map these observed malware behaviors to MITRE ATT&CK techniques and produce an IOC report."

**Tips for best results:** Paste strings output, Ghidra disassembly snippets, or sandbox reports directly for specific analysis. Always specify that samples are being analyzed in an isolated environment — the agent will tailor its guidance to sandboxed or air-gapped setups accordingly.

---

### report-generator

**When it activates:** When you ask about writing penetration test reports, formatting findings, or producing executive summaries.

**What it does:** Helps structure and write professional penetration test reports including executive summaries, methodology sections, individual findings with severity ratings, evidence formatting, and remediation recommendations.

**Example prompts:**

- "Format these findings into a professional pentest report with executive summary and remediation priorities."
- "Write an executive summary for a pentest that found 3 critical, 7 high, and 12 medium findings on an internal network."
- "Structure this finding as a professional report entry: we obtained Domain Admin via Kerberoasting a service account with a weak password."
- "Create a remediation roadmap section that prioritizes fixes by effort and impact."

**Tips for best results:** Provide the raw finding details including the vulnerability, evidence, affected systems, and business impact. The more detail you provide, the more polished the report output will be. Specify the audience (technical team vs. executive leadership) for appropriate tone and detail level.

---

### ctf-solver

**When it activates:** When you are working on CTF challenges, HackTheBox machines, TryHackMe rooms, or need help with CTF methodology including web exploitation, binary exploitation, cryptography, forensics, or privilege escalation challenges.

**What it does:** Guides you through CTF challenges across all major categories — web exploitation, binary exploitation (pwn), cryptography, forensics, reverse engineering, OSINT, and privilege escalation. Acts as a methodical problem-solving partner, teaching methodology and helping you progress when stuck rather than simply handing over flags. Advisory mode, with optional command guidance for your own CTF environment.

**Example prompts:**

- "I'm stuck on this HackTheBox machine. I have a login page and directory listing — what should I try next?"
- "This CTF crypto challenge gives me ciphertext and says it uses AES-ECB. What attacks apply?"
- "Walk me through a methodology for approaching a binary exploitation challenge on a 64-bit Linux binary."
- "I captured this PCAP from a CTF forensics challenge. What should I look for first?"

**Tips for best results:** Paste the challenge description, any output you have, and what you have already tried. The agent is most helpful when it knows where you are stuck rather than starting from scratch. Specify the CTF platform and challenge category for more targeted guidance.

---

## Workflow Chaining

The agents are designed to work together across the phases of a complete engagement. Here is how to chain them for maximum effectiveness.

### Phase 0: Threat Modeling (Optional Pre-Engagement)

Before scoping, use `threat-modeler` to understand the attack surface from an architectural perspective.

```
Threat model the client's three-tier web application — React frontend, Java
Spring Boot API, PostgreSQL on AWS RDS. Identify the highest-risk components
and attack vectors so we can prioritize our scope.
```

### Phase 1: Planning

Use `engagement-planner` to define scope, rules of engagement, and methodology. This sets the foundation for the entire assessment.

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

Route to the appropriate specialist based on the attack vector. Use `exploit-guide` for methodology, `exploit-chainer` for multi-step chains, `ad-attacker` for Active Directory, `web-hunter` for web targets, and `privesc-advisor` for post-compromise escalation.

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

After testing is complete, use `detection-engineer` to produce detection rules for the techniques you successfully used. This is the direct deliverable for blue teams.

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

For engagements where you want to automate the agent handoffs, use `swarm-orchestrator` to coordinate the entire lifecycle from Phase 1 through Phase 9.

```
Run a full red team engagement against Acme Corp. Authorized scope is
10.0.0.0/8 and corp.local. I need planning, recon, vulnerability assessment,
exploitation, and a final report. Pause for my approval before each phase
transition.
```

---

## General Tips

- **Be specific.** Vague prompts produce vague results. Include environment details, tool names, version numbers, and specific objectives.
- **Paste real tool output.** The agents are designed to analyze actual data. Copy and paste Nmap scans, BloodHound output, error messages, and configuration files directly into your prompts.
- **Provide engagement context.** Tell the agent whether this is an internal test, external test, web application assessment, red team exercise, or compliance audit. Context shapes the response.
- **Declare scope for Tier 2 agents.** Any agent with execution capability (Bash tool) will require you to declare your authorized scope before composing commands. Do this at the start of the session to avoid interruptions.
- **Review every command.** Claude Code shows you the full command before it runs. Read it. If a command looks wrong, deny it and ask the agent to explain its reasoning.
- **Iterate.** If the first response does not cover what you need, follow up with more specific questions. The agents maintain conversation context and can refine their output.
- **Chain agents deliberately.** The output from one agent often serves as ideal input for the next. Copy relevant output from one agent's response and paste it into your next prompt for the following phase.
