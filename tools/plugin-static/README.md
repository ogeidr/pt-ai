# pt-ai (Claude Code plugin)

**This directory is generated** by `tools/build-plugin.sh` from the canonical
sources (`agents/`, `skills/`, `vagrant/config/claude/hooks/`). Do not edit files
here directly — edit the source and rebuild. `test/plugin-parity.sh` fails CI if
this tree drifts from source.

pt-ai turns Claude Code into a scope-guarded penetration-testing environment:
operator-gated engagement phases, specialist subagents, and runtime safety hooks
(credential-exfil block, catastrophic-`rm` block, OPSEC ceiling, ROE surfacing).

## Two install options

- **VM (batteries included):** a fully-provisioned Kali/apt VM with the whole
  toolchain and an ephemeral sandbox — and the local-model (opencode) path. See
  the repo `README.md`.
- **Plugin (this):** drops the same skills/agents/hooks into your own Claude Code.
  **Claude Code only. Bring your own tools** — pt-ai ships intelligence and
  guardrails, not scanners. The VM is recommended when testing untrusted targets.

## Prerequisites

- **`jq` or `python3`** on `PATH`. The Bash/Read safety hook fails **closed**
  (denies) without a JSON parser, so every command would be blocked otherwise.
- Whatever offensive tooling your engagement needs (nmap, the AWS CLI, ghidra, …).
  The reverse-engineering skills (`disasm-ghidrasql`, `disasm-ghidra-rpc`) expect
  the VM's ghidra build and are not functional under the plugin alone.

## Engagement workspace

Run Claude Code from a dedicated working directory and stay there — pt-ai keeps
all engagement state under **`./engagements/`** relative to that directory (the VM
uses an absolute `/engagements` mount instead). Start with `/scope-declare`, then
`/engagement`, then the `/engage-*` phase skills.

## OPSEC ceiling

The guard's OPSEC ceiling is set with the **`PT_AI_OPSEC_LIMIT`** environment
variable (`QUIET` | `MODERATE` | `LOUD`, default `MODERATE`) in plugin mode. The
`engagements/.opsec_ceiling` file override is VM-only.

## Security posture

The plugin runs in your own environment with your real credentials present and no
sandbox — a weaker posture than the VM. The runtime hooks are defense-in-depth,
not a jail. Only use against targets you are authorized to test.
