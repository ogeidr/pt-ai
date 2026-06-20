---
name: scope-declare
description: >
  Declare engagement scope, authorization, and targets at the start of a
  penetration testing session. Invoke this before using any offensive agent
  so that scope context is set once and available to all agents.
disable-model-invocation: false
allowed-tools: Write
---

## Current scope for this engagement

!`cat /engagements/scope.md 2>/dev/null || echo "No scope declared yet for this engagement."`

## Instructions

Walk the user through scope declaration interactively. Ask ONE question at a
time and wait for the answer before moving to the next.

**Step 1 — Engagement identifier**
Ask: "What is your engagement identifier? (engagement ID, project name, client
reference, or for CTF/lab work: the platform and challenge name)"

**Step 2 — Authorized scope**
Ask: "What is the authorized scope? (IP ranges, domains, URLs, cloud accounts,
applications, SSIDs, or other in-scope assets)"

**Step 3 — Engagement type**
Ask: "What is the engagement type? (external, internal, web app, cloud,
wireless, mobile, social engineering, red team, CTF, defensive review, or other)"

**Step 4 — Written authorization**
Ask: "Do you confirm you possess written authorization (signed rules of
engagement, scope letter, or equivalent legal document) for the declared scope?
(yes/no)"

**If the user answers no to Step 4:**
- Output: "⚠ Scope declaration aborted. Written authorization is required before
  any offensive guidance can be provided. Obtain authorization and re-run
  /scope-declare."
- Do NOT produce the [SCOPE DECLARED] log line.
- Do NOT write any files.
- Stop here.

**If the user confirms authorization (yes):**

Derive a safe directory name from the engagement ID: lowercase the ID, replace
spaces and `/` with `-`, strip all characters except `a-z 0-9 - _`. Call this
`{safe_id}`. Example: "Acme Corp / External 2026" → `acme-corp-external-2026`.

Output the declaration in this exact format (agents use this to detect that
scope has been set):

```
[SCOPE DECLARED] Engagement: {id}, Type: {type}, Scope: {summary}, Authorization confirmed: yes
```

Then write to TWO locations using the Write tool, **in this order**:

**1. `/engagements/{safe_id}/scope.md`** — the **canonical** engagement record
(the Write tool creates the directory automatically). This is the source of truth:

```markdown
# Engagement Scope

- **Engagement:** {id}
- **Type:** {type}
- **Scope:** {summary}
- **Authorization confirmed:** yes
- **Evidence directory:** /engagements/{safe_id}

---

[SCOPE DECLARED] Engagement: {id}, Type: {type}, Scope: {summary}, Authorization confirmed: yes
```

**2. `/engagements/scope.md`** — a small **pointer** to the active engagement,
overwritten on each re-declaration. It is NOT the canonical record; it only tells
agents and skills where the active engagement lives. Keep the `Evidence directory:`
line verbatim — every reader resolves the engagement directory by grepping it from
this file, then reads the canonical scope from `{dir}/scope.md`:

```markdown
# Active Engagement Pointer

> Pointer only. Canonical scope record: /engagements/{safe_id}/scope.md

Engagement: {id}
Evidence directory: /engagements/{safe_id}
```

Write the `Evidence directory:` line **plain** (no `-`, no `**` bold) exactly as
shown — readers strip it with `sed 's/.*Evidence directory: //'`, which markdown
bold would break.

Finally, confirm to the user: "Scope is set. Evidence will be saved to
`/engagements/{safe_id}/`, organized into `scans/` (raw tool output), `reports/`
(consolidated summaries), and `exploit/` (PoC/exploitation artifacts). All agents
will operate within the declared boundaries. You can update scope at any time by
re-running `/scope-declare`."
