# scope-declare

Declare engagement scope and authorization before starting a penetration
testing session. Run this once at session start so all agents operate
within declared boundaries.

## Check existing scope

Use the read tool to check if /work/scope.md exists. If it does, show
the user their current scope and ask if they want to keep it or update it.
If it does not exist, proceed with the declaration flow below.

## Declaration flow

Ask ONE question at a time. Wait for the answer before asking the next.

**Step 1 — Engagement identifier**
"What is your engagement identifier? (engagement ID, project name, client
reference, or for CTF/lab work: the platform and challenge name)"

**Step 2 — Authorized scope**
"What is the authorized scope? (IP ranges, domains, URLs, cloud accounts,
applications, SSIDs, or other in-scope assets)"

**Step 3 — Engagement type**
"What is the engagement type? (external, internal, web app, cloud, wireless,
mobile, social engineering, red team, CTF, defensive review, or other)"

**Step 4 — Written authorization**
"Do you confirm you possess written authorization (signed rules of engagement,
scope letter, or equivalent legal document) for the declared scope? (yes/no)"

## If authorization is not confirmed (no)

Output exactly:
"⚠ Scope declaration aborted. Written authorization is required before any
offensive guidance can be provided. Obtain authorization and re-run
/scope-declare."

Do NOT write /work/scope.md. Stop here.

## If authorization is confirmed (yes)

Output the declaration in this exact format:

```
[SCOPE DECLARED] Engagement: {id}, Type: {type}, Scope: {summary}, Authorization confirmed: yes
```

Write to /work/scope.md:

```markdown
# Engagement Scope

- **Engagement:** {id}
- **Type:** {type}
- **Scope:** {summary}
- **Authorization confirmed:** yes

---

[SCOPE DECLARED] Engagement: {id}, Type: {type}, Scope: {summary}, Authorization confirmed: yes
```

Confirm: "Scope is set. All agents will operate within the declared boundaries.
You can update scope at any time by re-running /scope-declare."
