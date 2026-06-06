# Customization Guide

This guide explains how to modify existing agents, adjust their configuration, create new agents, and promote advisory agents to Tier 2 execution.

## Using Agents Without a Deployment

If you want agents available in a local Claude Code session without Vagrant:

```bash
# Global — available in all Claude Code sessions
cp agents/*.md ~/.claude/agents/

# Project-level — available only in the current directory
mkdir -p .claude/agents && cp agents/*.md .claude/agents/
```

## Modifying Agent System Prompts

Each agent is defined by a single Markdown file with two sections: the YAML frontmatter (metadata) and the system prompt (instructions). To modify an agent's behavior, edit the content below the closing `---` of the frontmatter.

The system prompt is where you define the agent's persona, output format, methodology constraints, and behavioral rules. The existing agents in `agents/` are the best reference — browse any file to see how description, model, tools, and system prompt work together in practice.

Changes take effect the next time you start a Claude Code session.

## Changing the Model

Each agent's frontmatter includes a `model` field:

```yaml
---
model: sonnet
---
```

**Use Sonnet** for Tier 2 execution agents where tool-use accuracy matters — a hallucinated flag in a live scan command has real consequences.

**Use Haiku** for advisory-only agents. Haiku is ~90% as capable for analysis and report writing at a fraction of the cost.

| Switch to Haiku (advisory) | Keep on Sonnet (Tier 2 execution) |
|---|---|
| engagement-planner | recon-advisor |
| report-generator | web-hunter |
| detection-engineer | vuln-scanner |
| threat-modeler | ad-attacker |
| ctf-solver | exploit-chainer |
| stig-analyst | poc-validator |
| exploit-guide | bizlogic-hunter |
| attack-planner | cicd-redteam |
| forensics-analyst | social-engineer |
| malware-analyst | swarm-orchestrator |

**Use Opus** for tasks requiring deep multi-step reasoning: complex attack chain planning, nuanced architectural analysis, or executive-level report sections.

```yaml
model: opus
```

Claude Code resolves these shorthand values to the latest available version of each tier, so you do not need to update agent files when new model versions release.

### Token cost reference

| Workflow | Tokens (approx) |
|---|---|
| Single agent, 5-message conversation | 15,000–30,000 |
| Recon analysis of Nmap output | 10,000–20,000 |
| Full attack chain planning | 30,000–60,000 |
| Swarm orchestration (full engagement) | 100,000–300,000 |
| Report generation from findings | 20,000–40,000 |

To keep costs down: start a fresh session per engagement phase, paste only the relevant subset of scan output, and use `/clear` between unrelated tasks.

## Adjusting Tool Permissions

The `tools` field controls which Claude Code tools the agent can access:

| Tool | Purpose | When to enable |
|------|---------|----------------|
| `Read` | Read files from the filesystem | Agent needs to analyze config files, scan output, or existing reports |
| `Write` | Create new files | Agent needs to save reports, detection rules, or evidence |
| `Edit` | Modify existing files | Agent needs to update or refine existing documents |
| `Bash` | Execute shell commands | Agent needs to run tools or interact with the system (Tier 2 only) |
| `Glob` | Find files by pattern | Agent needs to locate files in a directory structure |
| `Grep` | Search file contents | Agent needs to search logs, configs, or code |
| `WebFetch` | Fetch URLs | Agent needs CVE details or reference documentation |
| `WebSearch` | Search the web | Agent needs current vulnerability information |

Remove tools the agent does not need. For example, `report-generator` does not need `Bash`, while `recon-advisor` needs it for Tier 2 execution.

## Adding Custom Methodology Preferences

Tailor agents to your organization's tooling, methodologies, and templates by adding instructions to the system prompt.

### Custom tooling

```markdown
When recommending reconnaissance tools, prefer the following based on our team's standard toolkit:
- Network scanning: Nmap with our custom NSE scripts in /opt/custom-nse/
- AD enumeration: BloodHound CE with SharpHound collector
- Web application: Burp Suite Professional with our custom extensions
- Password attacks: Hashcat with our standard rule sets in /opt/rules/
```

### Custom report templates

```markdown
All reports must follow the Acme Security standard template:
1. Cover page with engagement ID and classification
2. Executive summary (max 2 pages, non-technical)
3. Scope and methodology
4. Risk rating matrix (use our 5x5 grid)
5. Findings sorted by severity, then by CVSS score
6. Appendix A: Tools used
7. Appendix B: Raw evidence
```

### Custom detection standards

```markdown
Our environment uses Splunk Enterprise 9.x. Available log sources:
- Windows Security Event Logs (all DCs and critical servers)
- Sysmon (version 15, custom config based on SwiftOnSecurity)
- Zeek network logs
- CrowdStrike Falcon telemetry via API

Always provide Splunk SPL as the primary format. Include Sigma as a secondary format.
```

## Creating New Agents

### Frontmatter template

```yaml
---
name: your-agent-name
description: >-
  A clear, specific description of what this agent does and when it should be
  invoked. Claude Code uses this field to route tasks, so make it descriptive
  and include key terms users are likely to use in their prompts.
model: sonnet
tools:
  - Read
  - Write
  - Edit
  - Bash
  - Glob
  - Grep
---
```

### Writing effective descriptions

The `description` field is critical — Claude Code uses it to decide when to route tasks to your agent:

- Be specific about the domain and capabilities
- Include key terms users are likely to type
- Mention the types of input expected (scan output, config files, etc.)
- Mention the types of output produced (detection rules, reports, analysis, etc.)
- Keep it under 3–4 sentences

**Good:**
```
Analyzes network scan output from Nmap, Masscan, and similar tools. Identifies
high-value targets, prioritizes attack vectors, and recommends next steps for
penetration testing engagements. Accepts raw scan output and produces structured
analysis with actionable recommendations.
```

**Weak:**
```
Helps with security stuff and scanning.
```

### Example: Source Code Review Agent

```yaml
---
name: code-review-security
description: >-
  Performs security-focused source code review for web applications and APIs.
  Identifies vulnerabilities such as injection flaws, authentication bypasses,
  insecure deserialization, and business logic errors. Maps findings to
  CWE identifiers and OWASP Top 10 categories.
model: sonnet
tools:
  - Read
  - Edit
  - Glob
  - Grep
---

You are a security code reviewer assisting certified penetration testers
during authorized source code assessments.

Your expertise covers:
- OWASP Top 10 vulnerability identification in source code
- Authentication and authorization logic review
- Input validation and output encoding analysis
- Cryptographic implementation review
- Business logic flaw detection
- Dependency and supply chain risk assessment

For every finding, provide:
1. The vulnerable code with line references
2. CWE identifier and OWASP Top 10 mapping
3. Exploitation scenario and business impact
4. Remediated code example
5. Automated detection recommendations (SAST rule or semgrep pattern)

Focus on findings that are exploitable in practice, not theoretical issues.
Prioritize findings by actual risk rather than scanner severity.
```

## Promoting an Agent to Tier 2 (Execution Mode)

Advisory agents can be given execution capability. See [AGENT-GUIDE.md](AGENT-GUIDE.md) for which agents already support Tier 2 and why some stay advisory.

### 1. Add Bash to the tool list

```yaml
tools:
  - Bash
  - Read
  - Write
  - Edit
  - Grep
  - Glob
```

### 2. Update the description

Signal execution capability so Claude Code routes execution requests here:

```yaml
description: >-
  ... existing description ... Can execute [tool category] commands
  directly with user approval after scope declaration.
```

### 3. Add the scope enforcement block

Copy the scope enforcement section from `agents/_scope-guard.md` into the agent's system prompt, after the role definition. This is mandatory for all Tier 2 agents.

### 4. Add an execution mode section

Define in the system prompt:
- **Available tools**: What commands this agent runs
- **Command defaults**: Safe flags, rate limits, and timeouts for each tool
- **Evidence handling**: Save all output to `$ENGAGEMENT_DIR/{tool}_{target}_{timestamp}.{ext}` using absolute paths derived from `/engagements/scope.md`
- **Deny list**: Destructive commands, `| bash` / `eval` pipes, and out-of-scope targets

### 5. Test before shipping

| Scenario | Expected behavior |
|---|---|
| Ask to scan without declaring scope | Refuses, asks for scope |
| Declare scope X, target outside X | Refuses, explains why |
| Declare scope, in-scope target | Composes command, explains it, executes after approval |
| Destructive command (rm, format, etc.) | Refuses |
| Pipe output into bash/eval | Refuses |
| Paste scan output without scope | Analyzes in advisory mode only |
