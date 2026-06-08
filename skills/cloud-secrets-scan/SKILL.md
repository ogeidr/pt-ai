---
name: cloud-secrets-scan
description: >
  Hunt for leaked credentials and secrets in authorized cloud storage and code
  using trufflehog — S3/GCS buckets, git repos, and looted filesystems. Finds
  API keys, access keys, tokens and passwords. Invoke after /scope-declare so the
  buckets/repos/accounts being scanned are confirmed in scope.
disable-model-invocation: false
allowed-tools: Bash, Read, Write
---

## Current scope for this engagement

!`cat /engagements/scope.md 2>/dev/null || echo "No scope declared yet. Run /scope-declare before scanning any bucket, repo, or account."`

## Evidence directory for this engagement

!`grep -m1 'Evidence directory:' /engagements/scope.md 2>/dev/null | sed 's/.*Evidence directory: //' || echo "/engagements (no scope declared — run /scope-declare first)"`

## Caller identity (which AWS account these credentials belong to)

!`aws sts get-caller-identity --output json 2>&1 || echo "AWS CLI not authenticated. For GCS/other sources, confirm the active credentials before running."`

## Tool availability

!`command -v trufflehog || echo "trufflehog: NOT FOUND — install before scanning."`

## Instructions

You are hunting for leaked secrets in authorized cloud storage and code. Reading
sources (S3/GCS list+get, git clone, filesystem read) is read-only. **Secret
verification is not** — see the verification warning in Step 2.

The **Evidence directory** shown above is `ENGAGEMENT_DIR`. Use it as an absolute
path prefix for every output file in this skill. Never use relative paths.

### Step 1 — Confirm scope and authorization (MANDATORY)

1. Read `/engagements/scope.md`. If missing, STOP and tell the user to run `/scope-declare`.
2. Confirm every source you will scan — each S3/GCS bucket, git repo, or account —
   is named in the declared scope. If any target is out of scope, REFUSE it.
3. If scope is ambiguous, ask the user to confirm the exact buckets/repos before scanning.

### Step 2 — Verification warning (READ TO THE USER, MANDATORY)

trufflehog can **verify** a found secret by sending it to its provider (AWS, GitHub,
Slack, Stripe, etc.) to test whether it is live. Verification:
- proves the credential is valid (high-signal), BUT
- generates an authentication event on the provider — possibly a **third party
  outside the engagement scope** — and may lock accounts or trigger alerts.

Rules:
- Default to **`--results=unknown,unverified`** (detect without authenticating) unless
  the user explicitly authorizes verification.
- Only use `--only-verified` / verification when the secret's provider is itself in
  scope, or the user gives explicit per-run authorization. Flag this each time.

### Step 3 — OPSEC briefing

OPSEC: **MODERATE**. Listing and reading bucket objects is read-only but recorded in
CloudTrail (S3 data events, if enabled) and may trip GuardDuty. Verification (Step 2)
is **LOUD** by nature — it authenticates against live services. Confirm depth before running.

### Step 4 — Choose source and scan

First, verify the evidence directory and set `ENGAGEMENT_DIR`:

```sh
test -d /engagements && test -w /engagements || { echo "ERROR: /engagements not mounted or not writable"; exit 1; }
ENGAGEMENT_DIR=$(grep -m1 'Evidence directory:' /engagements/scope.md | sed 's/.*Evidence directory: //')
[ -z "$ENGAGEMENT_DIR" ] && ENGAGEMENT_DIR="/engagements"
mkdir -p "$ENGAGEMENT_DIR"
```

Always include `--no-update` (don't self-update mid-engagement) and `--json` (for evidence).
All output files use `$ENGAGEMENT_DIR/` as the absolute prefix.

**S3 bucket** (single bucket, or whole account if authorized):

```
# Detect only, no verification (default-safe)
trufflehog s3 --bucket=BUCKET_NAME --no-update --results=unknown,unverified --json \
  > "$ENGAGEMENT_DIR/trufflehog_s3_BUCKET_{YYYYMMDD_HHMMSS}.json"
```

```
# Scan all buckets the in-scope role can reach (broader; mind CloudTrail volume)
trufflehog s3 --no-update --results=unknown,unverified --json \
  > "$ENGAGEMENT_DIR/trufflehog_s3_{accountid}_{YYYYMMDD_HHMMSS}.json"
```

**GCS bucket:**

```
trufflehog gcs --bucket=BUCKET_NAME --no-update --results=unknown,unverified --json \
  > "$ENGAGEMENT_DIR/trufflehog_gcs_BUCKET_{YYYYMMDD_HHMMSS}.json"
```

**Git repository** (in-scope source repo):

```
trufflehog git REPO_URL --no-update --results=unknown,unverified --json \
  > "$ENGAGEMENT_DIR/trufflehog_git_{repo}_{YYYYMMDD_HHMMSS}.json"
```

**Filesystem** (data already looted to disk during the engagement):

```
trufflehog filesystem PATH --no-update --results=unknown,unverified --json \
  > "$ENGAGEMENT_DIR/trufflehog_fs_{label}_{YYYYMMDD_HHMMSS}.json"
```

**Only if verification is explicitly authorized for an in-scope provider**, swap to:
`--results=verified` (or add `--only-verified`). State the authorization in the summary.

### Step 5 — Save evidence

The redirected `*.json` files above are the raw evidence — keep them. Then write a
markdown summary with the Write tool using an absolute path:

- `$ENGAGEMENT_DIR/secretsscan_{label}_{YYYYMMDD_HHMMSS}.md`

Header must note: source type and target, engagement ID from `/engagements/scope.md`,
whether verification was used (and its authorization), and the collection timestamp.

**Handle findings as sensitive material.** Do NOT paste full secret values into chat
or the summary — redact to a prefix (e.g., `AKIA...XXXX`), record the detector type,
file/object path, and verification status. The raw values stay only in the evidence
files, which the user secures.

### Step 6 — Present findings

| Detector | Verified? | Source / path | Secret (redacted) | Why it matters / next step |
|----------|-----------|---------------|-------------------|----------------------------|

Prioritize: live cloud access keys, tokens granting write/admin, and any credential
whose provider is in scope and could enable pivot or privilege escalation.

### Step 7 — Recommend next steps

- A found AWS key → confirm its permissions via the `cloud-audit` / `cloud-security`
  path (read-only) before any authorized use.
- Cross-reference with `cloud-audit` IAM findings to map what the leaked identity can do.
- Active use of a recovered credential is a separate, explicitly authorized phase —
  this skill only discovers and catalogs.

Remind the user that the evidence files contain plaintext secrets — secure or
destroy them at session end. Evidence is in `$ENGAGEMENT_DIR/` and synced to the host.
