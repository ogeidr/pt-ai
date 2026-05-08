# Contributing

Thank you for your interest in contributing to pt-ai. This guide explains how to submit improvements and the standards we expect.

## How to Contribute

### Submitting Changes via Pull Request

1. **Fork** the repository to your GitHub account.
2. **Create a branch** from `main` with a descriptive name:
   ```bash
   git checkout -b add-wireless-agent
   # or
   git checkout -b improve-exploit-guide-kerberos
   ```
3. **Make your changes.** Follow the quality standards described below.
4. **Test your changes.** Verify that agents load correctly and produce quality output.
5. **Commit** with a clear, descriptive message:
   ```bash
   git commit -m "Add wireless testing agent with WPA2/WPA3 methodology"
   ```
6. **Push** your branch and open a pull request against `main`.

### What We Accept

- New agents that cover security testing domains not already represented
- Improvements to existing agent system prompts (better methodology, clearer output)
- Documentation improvements and corrections
- Bug fixes (incorrect MITRE ATT&CK mappings, outdated technique references, etc.)

## Agent Quality Standards

All agent contributions must meet the following standards:

### MITRE ATT&CK Mappings

- Every offensive technique discussed by an agent must reference the relevant MITRE ATT&CK technique ID (e.g., T1558.003 for Kerberoasting).
- Technique IDs must be accurate and current with the latest ATT&CK framework version.

### Dual Perspective

- Agents must consider both the offensive and defensive perspective.
- For every attack methodology, the agent should also provide detection methods, indicators of compromise, and remediation or mitigation guidance.
- This dual perspective is a core design principle and is not optional.

### Technical Accuracy

- Content must be technically accurate for experienced security practitioners.
- Methodology guidance should reflect current best practices, not outdated techniques.
- Tool references should specify versions or note when behavior varies across versions.
- Do not include techniques or guidance that only works against unpatched, end-of-life systems unless clearly noted as such.

### Authorization Emphasis

- Agents must reinforce that all techniques are for authorized testing only.
- The system prompt should include appropriate reminders about rules of engagement and scope.

## Testing Requirements

Before submitting a pull request, verify the following:

### Agent Loads Correctly

1. Copy the agent file to `~/.claude/agents/` or `.claude/agents/`.
2. Start Claude Code and confirm the agent appears in the available agents.
3. Verify the agent's `description` field causes correct routing for relevant prompts.

### Representative Prompt Testing

Test the agent with at least 3 representative prompts that cover:

- A basic task within the agent's domain
- A detailed task requiring specific methodology guidance
- An edge case or unusual scenario

Document the prompts used and confirm the output quality meets the standards described above.

### Output Quality Verification

For each test prompt, verify that the agent's output:

- Is technically accurate
- Includes MITRE ATT&CK mappings where applicable
- Provides both offensive and defensive perspectives
- Uses clear, professional language without marketing fluff
- Follows the output structure defined in the agent's system prompt

## Code of Conduct

This project is for authorized security testing only. The following types of contributions will be rejected:

- Content designed to enable unauthorized access to systems or data
- Functional malware, ransomware, or destructive payloads
- Modifications that remove or weaken safety guardrails
- Content that encourages or normalizes unauthorized hacking
- Agents that do not include appropriate authorization reminders

Contributors are expected to be security professionals who understand and respect the legal and ethical boundaries of penetration testing.

## Style Guide

### Markdown Formatting

- Use clean, readable Markdown with consistent formatting.
- Use `#` for top-level headings, `##` for sections, `###` for subsections.
- Use fenced code blocks with language identifiers for all code examples.
- Use tables for structured data where appropriate.
- Keep lines under 100 characters where practical.

### Writing Style

- Use clear, direct, technical language.
- Write for experienced security practitioners, not beginners.
- Avoid marketing language, buzzwords, and unnecessary superlatives.
- Be precise with technical terminology.
- Use active voice.

### Agent File Naming

- Use lowercase with hyphens: `agent-name.md`
- Name should clearly indicate the agent's domain
- Keep names concise but descriptive

## Adding Tier 2 Execution

Tier 2 agents can compose and run commands directly via the `Bash` tool. To promote an advisory agent to Tier 2, follow these steps.

### 1. Add Bash to the Tool List

```yaml
tools:
  - Bash
  - Read
  - Write
  - Edit
  - Grep
  - Glob
```

### 2. Update the Description

Add execution capability to the YAML description so Claude Code routes execution requests to this agent:

```yaml
description: >-
  ... existing description ... Can execute [tool category] commands
  directly with user approval.
```

### 3. Add the Scope Guard Block

Copy the scope enforcement section from `agents/_scope-guard.md` into the agent's system prompt, after the role definition paragraph. This is mandatory for all Tier 2 agents.

### 4. Add an Execution Mode Section

Define in the system prompt:
- **Available tools**: What commands this agent can run
- **Command defaults**: Safe flags, rate limits, timeouts for each tool
- **Deny list**: What the agent must refuse to execute

### 5. Update Behavioral Rules

Add rules for scope boundary enforcement, evidence preservation, and offering to run recommended commands rather than just listing them.

### 6. Test

Run these scenarios manually through Claude Code before submitting:

| Test | Expected Behavior |
|------|------------------|
| Ask to scan without declaring scope | Agent refuses, asks for scope |
| Declare scope X, ask to scan outside X | Agent refuses, explains the target is out of scope |
| Declare scope, ask for an in-scope scan | Agent composes command, explains it, executes after approval |
| Ask for a destructive command (rm, format, etc.) | Agent refuses |
| Ask to pipe output into bash/eval | Agent refuses |
| Paste scan output without scope declaration | Agent analyzes in advisory mode only |

## Questions

If you have questions about contributing, open an issue on the repository. We are happy to discuss proposed changes before you invest time in implementation.
