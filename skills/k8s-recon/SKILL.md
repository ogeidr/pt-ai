---
name: k8s-recon
description: >
  Map the attack surface of an authorized Kubernetes cluster using kube-hunter —
  exposed API server, kubelet, etcd, dashboards, tokens and known CVEs. Defaults
  to passive hunting; active (intrusive) mode is gated behind explicit authorization.
  Invoke after /scope-declare so the cluster/hosts being scanned are confirmed in scope.
disable-model-invocation: false
allowed-tools: Bash, Read, Write
---

## Current scope for this engagement

!`cat /work/scope.md 2>/dev/null || echo "No scope declared yet. Run /scope-declare before scanning any cluster or host."`

## Current kube context (if kubectl is configured)

!`kubectl config current-context 2>/dev/null || echo "No kubectl context set (fine for remote/CIDR scans — confirm targets against scope manually)."`

## Tool availability

!`command -v kube-hunter >/dev/null 2>&1 && echo "kube-hunter: $(command -v kube-hunter)" || echo "kube-hunter: NOT FOUND"`

## Instructions

You are mapping a Kubernetes attack surface. **Passive** hunting is reconnaissance
(probe + identify). **Active** hunting (`--active`) can exploit findings and modify
cluster state — it is gated separately below. Note: kube-hunter is archived upstream;
treat CVE mappings as a starting point and confirm versions independently.

### Step 1 — Confirm scope and authorization (MANDATORY)

1. Read `/work/scope.md`. If missing, STOP and tell the user to run `/scope-declare`.
2. Confirm every target — each remote host, CIDR, or the local cluster — is named in
   the declared scope. If any target is out of scope, REFUSE it.
3. **CIDR caution:** `--cidr` scans an entire range and will happily hit hosts the
   engagement does not cover. Only use it when the *whole range* is in scope; otherwise
   prefer `--remote` against specific authorized IPs.

### Step 2 — Active-mode gate (MANDATORY)

Do NOT pass `--active` unless the user explicitly authorizes intrusive testing for
this run. Active hunting attempts exploitation (e.g., creating/deleting resources,
accessing secrets) and can alter or disrupt the cluster.
- Default to **passive** hunting.
- If the user requests `--active`, restate that it is intrusive and may change cluster
  state, get explicit confirmation, and record the authorization in the summary.

### Step 3 — OPSEC briefing

OPSEC: passive remote/CIDR scan is **MODERATE** — active probing of Kubernetes
components (API server, kubelet, etcd, dashboard), visible to cluster audit logging
and any IDS in path. `--active` is **LOUD** and state-changing. Confirm depth first.

### Step 4 — Choose scan vector

Always add `--report json` and `--log INFO` for clean, parseable evidence.

**Remote host(s)** — specific in-scope IPs/hostnames (preferred):

```
kube-hunter --remote TARGET --report json --log INFO \
  > kubehunter_{target}_{YYYYMMDD_HHMMSS}.json
```

**Network range** — ONLY when the entire CIDR is in scope:

```
kube-hunter --cidr CIDR --report json --log INFO \
  > kubehunter_{cidr}_{YYYYMMDD_HHMMSS}.json
```

**From inside a pod** — internal attack-surface view (e.g., for a compromised-pod
scenario, where allowed):

```
kube-hunter --pod --report json --log INFO \
  > kubehunter_pod_{YYYYMMDD_HHMMSS}.json
```

**Active (intrusive) — ONLY with explicit authorization from Step 2:**

```
kube-hunter --remote TARGET --active --report json --log INFO \
  > kubehunter_active_{target}_{YYYYMMDD_HHMMSS}.json
```

### Step 5 — Save evidence

The redirected `*.json` files are the raw evidence — keep them. Then write a markdown
summary with the Write tool:

- `k8srecon_{label}_{YYYYMMDD_HHMMSS}.md`

Header must note: scan vector and target, passive vs. active (and active authorization
if used), engagement ID from `/work/scope.md`, and the collection timestamp.

### Step 6 — Present findings

Parse the JSON (vulnerabilities + nodes/services) into a severity-ranked table:

| Severity | Location | Vulnerability | Component | Why it matters / next step |
|----------|----------|---------------|-----------|----------------------------|

Prioritize the high-impact exposures:
- Anonymous/unauthenticated **API server** or **kubelet** (`:10250`) read/exec access.
- Exposed **etcd**, **Kubernetes dashboard**, or metrics endpoints.
- Reachable **service-account tokens** / mounted secrets.
- Known CVEs tied to the detected component versions (verify versions independently).

### Step 7 — Recommend next steps

- An exposed kubelet/API path → confirm what it grants (read-only enumeration) before
  any authorized exploitation.
- Cross-reference exposed node IPs with `aws-ec2-recon` and security-group findings
  from `cloud-audit` to map cloud-side reachability.
- Exploitation of a finding (including `--active` follow-through) is a separate,
  explicitly authorized phase — passive `k8s-recon` only maps surface.

Remind the user to secure or transfer the evidence files at session end.
