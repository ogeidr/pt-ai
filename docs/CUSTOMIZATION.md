# Customization Guide

This guide explains how to modify existing agents, adjust their configuration, and create new agents tailored to your specific needs.

## Modifying Agent System Prompts

Each agent is defined by a single Markdown file with two sections: the YAML frontmatter (metadata) and the system prompt (instructions). To modify an agent's behavior, edit the content below the closing `---` of the frontmatter.

For example, if you want the `exploit-guide` agent to always include MITRE ATT&CK technique IDs in its responses, open the agent file and add that instruction to the system prompt section.

The system prompt is where you define:

- The agent's persona and expertise level
- Output format and structure requirements
- Specific methodologies or frameworks to follow
- Constraints on what the agent should and should not do
- Any required sections or templates in the response

Changes take effect the next time you start a Claude Code session.

## Changing the Model

Each agent's frontmatter includes a `model` field that specifies which Claude model it uses. You can change this based on your needs and subscription tier.

```yaml
---
model: sonnet
---
```

### When to Use Sonnet

- Routine analysis tasks with straightforward output
- Faster response times for iterative workflows
- Lower cost per interaction
- Recon output analysis and formatting tasks
- Standard report section generation

### When to Use Opus

- Complex multi-step reasoning about attack chains
- Detailed architectural analysis of security environments
- Nuanced risk assessment and business impact analysis
- Generating sophisticated detection logic with tuning recommendations
- Writing executive-level report content that requires careful framing

Change the model field to match what your subscription supports:

```yaml
model: sonnet
# or
model: opus
```

Claude Code resolves these shorthand values to the latest available version of that model tier, so you don't need to update agent files when new model versions are released.

## Adjusting Tool Permissions

The `tools` field in the frontmatter controls which Claude Code tools the agent can access. Here is what each tool does:

| Tool | Purpose | When to Enable |
|------|---------|----------------|
| `Read` | Read files from the filesystem | When the agent needs to analyze configuration files, scan output files, or existing reports |
| `Write` | Create new files | When the agent needs to save reports, detection rules, or generated documents |
| `Edit` | Modify existing files | When the agent needs to update or refine existing documents |
| `Bash` | Execute shell commands | When the agent needs to run tools, process data, or interact with the system |
| `Glob` | Find files by pattern matching | When the agent needs to locate specific files in a directory structure |
| `Grep` | Search file contents by pattern | When the agent needs to search through logs, configurations, or code |
| `WebFetch` | Fetch content from URLs | When the agent needs to retrieve reference material, CVE details, or documentation |
| `WebSearch` | Search the web | When the agent needs to look up current vulnerability information or tool documentation |

To restrict an agent's tools, list only the ones it needs:

```yaml
tools:
  - Read
  - Write
  - Glob
  - Grep
```

To give an agent full access:

```yaml
tools:
  - Read
  - Write
  - Edit
  - Bash
  - Glob
  - Grep
  - WebFetch
  - WebSearch
```

Remove tools the agent does not need. For example, the `report-generator` agent may not need `Bash` access, while the `recon-advisor` may benefit from `Bash` to run follow-up commands.

## Adding Custom Methodology Preferences

You can tailor agents to your organization's specific tooling, methodologies, and templates by adding instructions to the system prompt.

### Custom Tooling

If your team uses specific tools, add them to the relevant agent's system prompt:

```markdown
When recommending reconnaissance tools, prefer the following based on our team's standard toolkit:
- Network scanning: Nmap with our custom NSE scripts in /opt/custom-nse/
- AD enumeration: BloodHound CE with SharpHound collector
- Web application: Burp Suite Professional with our custom extensions
- Password attacks: Hashcat with our standard rule sets in /opt/rules/
```

### Custom Report Templates

For the `report-generator`, you can embed your organization's report structure:

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

### Custom Detection Standards

For the `detection-engineer`, specify your SIEM platform and log sources:

```markdown
Our environment uses Splunk Enterprise 9.x. Available log sources:
- Windows Security Event Logs (all DCs and critical servers)
- Sysmon (version 15, custom config based on SwiftOnSecurity)
- Zeek network logs
- CrowdStrike Falcon telemetry via API

Always provide Splunk SPL as the primary format. Include Sigma as a secondary format.
```

## Creating New Agents

### Frontmatter Template

Every agent file starts with YAML frontmatter:

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

### Writing Effective Descriptions

The `description` field is critical because Claude Code uses it to decide when to route tasks to your agent. Follow these guidelines:

- Be specific about the agent's domain and capabilities
- Include key terms and phrases that users are likely to use in prompts
- Mention the types of input the agent expects (scan output, configuration files, etc.)
- Mention the types of output the agent produces (detection rules, reports, analysis, etc.)
- Keep it under 3-4 sentences

**Good description:**
```
Analyzes network scan output from Nmap, Masscan, and similar tools. Identifies
high-value targets, prioritizes attack vectors, and recommends next steps for
penetration testing engagements. Accepts raw scan output and produces structured
analysis with actionable recommendations.
```

**Weak description:**
```
Helps with security stuff and scanning.
```

### System Prompt Best Practices

Below the frontmatter, write the system prompt that defines the agent's behavior:

1. **Start with a role definition.** Tell the agent who it is and what it specializes in.
2. **Define the output format.** Specify structure, sections, and formatting requirements.
3. **Set boundaries.** Explain what the agent should and should not do.
4. **Include methodology frameworks.** Reference MITRE ATT&CK, OWASP, PTES, or other relevant frameworks.
5. **Add examples.** Show the agent what good output looks like for common requests.
6. **Require dual perspective.** For offensive agents, always require defensive recommendations alongside attack methodology.

The best reference for real agent structure is the existing agents in `agents/`. Browse any file there to see how description, model, tools, and system prompt work together in practice.

The example below shows a new domain — source code security review — that is not currently in the agent roster.

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
