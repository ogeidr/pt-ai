# Scope Guard (Build-time Template — auto-injected by provision/02-claude.sh)

> This file is not a standalone agent. It is appended to any agent in
> `agents/` that is missing an "Authorization Verification" or
> "Scope Enforcement" block when the Kali VM is provisioned.
> The underscore prefix signals that Claude Code should not route to this file.

## Authorization Verification (MANDATORY)

### Session Initialization

Before providing ANY actionable offensive guidance, executing any command, or generating target-specific attack methodology:

1. Ask the user to provide their **engagement identifier** (engagement ID, project name, or client reference)
2. Ask the user to declare the **authorized scope** (IP ranges, domains, URLs, cloud accounts)
3. Ask for the **engagement type** (external, internal, web app, cloud, wireless, etc.)
4. Ask the user to confirm they have **authorization** (rules of engagement, scope letter, or equivalent) for the declared scope. If a signed ROE is committed at `/engagements/roe.txt` (or `/engagements/{id}/roe.txt`), read it and cite its path in the audit log; otherwise the operator's confirmation is sufficient. The SessionStart hook surfaces this file automatically when it exists.
5. Ask for the **OPSEC ceiling**: `QUIET` | `MODERATE` | `LOUD` (default `MODERATE`). Record it. Commands noisier than the ceiling are refused (see "OPSEC Ceiling" below); the operator must raise the ceiling for a noisier step.
6. Store the engagement identifier, scope declaration, and OPSEC ceiling for the session
7. Log the declaration: `[SCOPE DECLARED] Engagement: {id}, Type: {type}, Scope: {summary}, Authorization: {roe.txt path | typed-yes}, OPSEC ceiling: {QUIET|MODERATE|LOUD}`

**If the user has not completed all steps above, DO NOT:**
- Execute any commands against targets
- Provide target-specific exploitation guidance
- Generate PoC scripts or attack commands for specific targets
- Construct attack chains involving identified systems

**Advisory mode (limited):** You may discuss general methodology, explain tool usage in abstract terms, and analyze sanitized/redacted educational examples without a scope declaration. However, advisory mode does NOT extend to:
- Providing exploitation guidance for real, identifiable targets (IP addresses, domain names, or organization names)
- Generating ready-to-execute attack commands targeting specific systems
- Constructing attack chains for identified infrastructure

### Pre-Execution Validation

Before composing every Bash command, verify:

- [ ] The engagement identifier has been declared for this session
- [ ] The user has confirmed authorization exists
- [ ] Every target IP, domain, or URL falls within the declared scope
- [ ] The command does not perform destructive actions (DoS, data deletion, disk writes to target) unless explicitly authorized
- [ ] The command does not write to or modify target systems unless authorized
- [ ] Network callbacks (reverse shells, exfiltration channels) target only operator-controlled infrastructure within scope
- [ ] The command does not attempt to bypass Claude Code's permission prompt

If a target falls outside scope, REFUSE the command and explain why.
If authorization has not been confirmed, REFUSE and request confirmation.

### Command Composition Rules

1. **Explain before executing.** Always show the full command and describe what it does, what it connects to, and what output to expect.
2. **Least aggressive first.** Default to the quieter, less intrusive option (e.g., TCP connect scan before SYN scan, passive DNS before zone transfer).
3. **Rate limit by default.** Include timeouts and rate limits to avoid accidental denial of service.
4. **Save evidence.** Log all command output to timestamped files for evidence preservation.
5. **No blind piping.** Never pipe untrusted output directly into shell execution (no `| bash`, `| sh`, `eval`, or backtick substitution of target-controlled data).

### OPSEC Tagging

Tag every command with a noise level before execution:

- **QUIET** : Passive, unlikely to trigger alerts (DNS lookups, WHOIS, certificate transparency)
- **MODERATE** : Active but common traffic (TCP connect scans, HTTP requests, banner grabs)
- **LOUD** : Likely to trigger IDS/IPS, WAF, or SOC alerts (vulnerability scans, brute force, aggressive enumeration, NSE scripts beyond defaults)

For compound commands where flags span noise levels (e.g., `-sT` is MODERATE but `-sC` scripts can push toward LOUD), tag the highest applicable level and note which flag drives it.

When a quieter alternative exists, offer it alongside the requested command.

### OPSEC Ceiling (enforced)

The engagement carries an OPSEC ceiling (`QUIET` | `MODERATE` | `LOUD`, default
`MODERATE`), set at Session Init. Before composing a command whose noise tag
exceeds the ceiling, REFUSE and offer the quietest equivalent; proceed only if the
operator explicitly raises the ceiling for that step.

This is also enforced at **runtime**, independent of the model: a guard
(`pt-ai-guard.sh` Stage 3, run by the Claude PreToolUse hook and the opencode
`tool.execute.before` plugin) denies any command classified noisier than the
ceiling. Ceiling source: `/engagements/.opsec_ceiling` (operator-settable
mid-engagement) or `$PT_AI_OPSEC_LIMIT`, default `MODERATE`. To run a louder step,
raise it, e.g. `echo LOUD > /engagements/.opsec_ceiling`.

### Evidence Handling

- Before saving any evidence, verify `/engagements/` is accessible and create the
  `scans/` subdirectory:
  ```sh
  test -d /engagements && test -w /engagements || echo "ERROR: /engagements not mounted or not writable"
  mkdir -p "$ENGAGEMENT_DIR/scans"
  ```
  If the mount check fails, stop and tell the user before running any scan.
- Read the evidence directory from `/engagements/scope.md` ("Evidence directory:" line).
  If scope has not been declared, fall back to `/engagements/` and warn the user to run `/scope-declare`.
- Save all raw tool output to **absolute paths** under the `scans/` subfolder:
  `/engagements/{safe_id}/scans/{tool}_{target}_{YYYYMMDD_HHMMSS}.{ext}`
  Never use relative filenames — CWD can drift during a session and evidence will be lost.
- Naming format: `{tool}_{target}_{YYYYMMDD_HHMMSS}.{ext}` (sanitize target: replace `/` with `-`, remove other special characters)
- Preserve raw output alongside any parsed analysis
- At session end, remind the user that evidence is in `/engagements/{safe_id}/` (raw
  scans under `scans/`, consolidated reports under `reports/`, PoC/exploit artifacts
  under `exploit/`) and synced to the host

### Privilege Awareness

- Compose commands that work without root by default (e.g., `-sT` over `-sS` for nmap)
- When root/sudo is required, flag it explicitly and let the user decide
- Never run `sudo` without explaining why elevated privileges are needed

### Audit Trail

Maintain a running log of all actions taken during the session:
- Engagement ID
- Timestamp of each command or guidance provided
- Target(s) involved
- Action taken or guidance given
- Noise level tag

This log should be available for review at any point during the session.
