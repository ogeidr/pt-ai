# cloud-secrets-scan

Hunt for leaked credentials and secrets in authorized cloud storage and code using
trufflehog — S3/GCS buckets, git repos, and looted filesystems. Reading sources is
read-only; secret verification is NOT (see the verification warning below).

## Check scope, identity, and tool first

Use the read tool to check `/work/scope.md`. If it does not exist, STOP and tell the
user to run `/scope-declare` first.

Confirm identity and that the tool is present:

```
aws sts get-caller-identity --output json
command -v trufflehog && trufflehog --version
```

Every source you scan — each S3/GCS bucket, git repo, or account — MUST be named in
the declared scope. Out-of-scope targets: REFUSE. If ambiguous, ask the user to
confirm the exact buckets/repos before scanning.

## Verification warning (READ TO THE USER, MANDATORY)

trufflehog can **verify** a found secret by sending it to its provider (AWS, GitHub,
Slack, Stripe, etc.) to test whether it is live. Verification proves validity but
generates an authentication event on the provider — possibly a **third party outside
the engagement scope** — and may lock accounts or trigger alerts.

- Default to `--results=unknown,unverified` (detect without authenticating).
- Only use `--only-verified` / verification when the secret's provider is itself in
  scope, or the user gives explicit per-run authorization. Flag this each time.

## OPSEC briefing

OPSEC: **MODERATE**. Listing/reading objects is read-only but recorded in CloudTrail
(S3 data events) and may trip GuardDuty. Verification is **LOUD** — it authenticates
against live services. Confirm depth before running.

## Choose source and scan

Always include `--no-update` and `--json`.

**S3 bucket:**

```
trufflehog s3 --bucket=BUCKET_NAME --no-update --results=unknown,unverified --json \
  > trufflehog_s3_BUCKET_{YYYYMMDD_HHMMSS}.json
```

```
# All reachable buckets (broader; mind CloudTrail volume)
trufflehog s3 --no-update --results=unknown,unverified --json \
  > trufflehog_s3_{accountid}_{YYYYMMDD_HHMMSS}.json
```

**GCS bucket:**

```
trufflehog gcs --bucket=BUCKET_NAME --no-update --results=unknown,unverified --json \
  > trufflehog_gcs_BUCKET_{YYYYMMDD_HHMMSS}.json
```

**Git repository:**

```
trufflehog git REPO_URL --no-update --results=unknown,unverified --json \
  > trufflehog_git_{repo}_{YYYYMMDD_HHMMSS}.json
```

**Filesystem (looted data):**

```
trufflehog filesystem PATH --no-update --results=unknown,unverified --json \
  > trufflehog_fs_{label}_{YYYYMMDD_HHMMSS}.json
```

Only if verification is explicitly authorized for an in-scope provider, swap to
`--results=verified` (or add `--only-verified`) and record the authorization.

## Save evidence

The redirected `*.json` files are the raw evidence — keep them. Then write a markdown
summary:

- `secretsscan_{label}_{YYYYMMDD_HHMMSS}.md`

Header must note: source type and target, engagement ID from `/work/scope.md`,
whether verification was used (and its authorization), and the collection timestamp.

**Handle findings as sensitive material.** Do NOT paste full secret values into chat
or the summary — redact to a prefix (e.g., `AKIA...XXXX`), record the detector type,
file/object path, and verification status. Raw values stay only in the evidence files.

## Present findings

| Detector | Verified? | Source / path | Secret (redacted) | Why it matters / next step |
|----------|-----------|---------------|-------------------|----------------------------|

Prioritize live cloud access keys, write/admin tokens, and any credential whose
provider is in scope and could enable pivot or privilege escalation.

## Recommend next steps

- A found AWS key → confirm its permissions via the cloud-audit / cloud-security path
  (read-only) before any authorized use.
- Cross-reference with cloud-audit IAM findings to map what the leaked identity can do.
- Active use of a recovered credential is a separate, explicitly authorized phase —
  this skill only discovers and catalogs.

Remind the user that evidence files contain plaintext secrets — secure or destroy
them at session end.
