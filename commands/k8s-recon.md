# k8s-recon

Map the attack surface of an authorized Kubernetes cluster using kube-hunter —
exposed API server, kubelet, etcd, dashboards, tokens, and known CVEs. Defaults to
passive hunting; active (intrusive) mode is gated behind explicit authorization.
Note: kube-hunter is archived upstream — confirm component versions independently.

## Check scope, context, and tool first

Use the read tool to check `/work/scope.md`. If it does not exist, STOP and tell the
user to run `/scope-declare` first.

Confirm context and that the tool is present:

```
kubectl config current-context 2>/dev/null
command -v kube-hunter
```

Every target — each remote host, CIDR, or the local cluster — MUST be named in the
declared scope. Out-of-scope targets: REFUSE.

**CIDR caution:** `--cidr` scans an entire range and will hit hosts the engagement may
not cover. Only use it when the *whole range* is in scope; otherwise prefer `--remote`
against specific authorized IPs.

## Active-mode gate (MANDATORY)

Do NOT pass `--active` unless the user explicitly authorizes intrusive testing for this
run. Active hunting attempts exploitation (creating/deleting resources, accessing
secrets) and can alter or disrupt the cluster.

- Default to passive hunting.
- If the user requests `--active`, restate that it is intrusive and may change cluster
  state, get explicit confirmation, and record the authorization in the summary.

## OPSEC briefing

OPSEC: passive remote/CIDR scan is **MODERATE** — active probing of Kubernetes
components (API server, kubelet, etcd, dashboard), visible to cluster audit logging and
any IDS in path. `--active` is **LOUD** and state-changing. Confirm depth first.

## Choose scan vector

Always add `--report json` and `--log INFO`.

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

**From inside a pod** — internal attack-surface view:

```
kube-hunter --pod --report json --log INFO \
  > kubehunter_pod_{YYYYMMDD_HHMMSS}.json
```

**Active (intrusive) — ONLY with explicit authorization:**

```
kube-hunter --remote TARGET --active --report json --log INFO \
  > kubehunter_active_{target}_{YYYYMMDD_HHMMSS}.json
```

## Save evidence

The redirected `*.json` files are the raw evidence — keep them. Then write a markdown
summary:

- `k8srecon_{label}_{YYYYMMDD_HHMMSS}.md`

Header must note: scan vector and target, passive vs. active (and active authorization
if used), engagement ID from `/work/scope.md`, and the collection timestamp.

## Present findings

Parse the JSON (vulnerabilities + nodes/services) into a severity-ranked table:

| Severity | Location | Vulnerability | Component | Why it matters / next step |
|----------|----------|---------------|-----------|----------------------------|

Prioritize high-impact exposures:
- Anonymous/unauthenticated API server or kubelet (`:10250`) read/exec access.
- Exposed etcd, Kubernetes dashboard, or metrics endpoints.
- Reachable service-account tokens / mounted secrets.
- Known CVEs tied to detected component versions (verify versions independently).

## Recommend next steps

- An exposed kubelet/API path → confirm what it grants (read-only enumeration) before
  any authorized exploitation.
- Cross-reference exposed node IPs with aws-ec2-recon and cloud-audit security-group
  findings to map cloud-side reachability.
- Exploitation of a finding (including `--active` follow-through) is a separate,
  explicitly authorized phase — passive k8s-recon only maps surface.

Remind the user to secure or transfer the evidence files at session end.
