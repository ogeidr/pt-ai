# Vagrant Pentest VM

Reproducible, fully-provisioned pentest VM for pt-ai engagements — Kali by
default, any apt-family box supported (Ubuntu, Debian, Parrot, Mint, …).
One command to boot; `vagrant snapshot` for clean-state management between engagements.

## Architecture

```
Host (macOS)
└── Pentest VM (Kali by default · VMware Fusion / VirtualBox / Parallels)
    ├── Claude Code          — API key or OAuth (claude.ai/pro)
    ├── opencode             — API key only (Anthropic provider default)
    ├── kali-linux-default   — core Kali toolset + extras (Kali boxes; see config/tools.txt)
    └── /engagements/        — synced from host engagements/
```

Both Claude Code and opencode run directly inside the VM and invoke Kali tools via their built-in shells — no MCP bridge needed.

---

## First-time setup

### Prerequisites

| Platform | Provider | Notes |
|---|---|---|
| Apple Silicon Mac | VMware Fusion 13+ (free) | Default — tested; needs the `kali-arm64` box (Step 1) |
| Intel Mac / Linux | VMware Workstation/Fusion (free) | Default; uses the official `kalilinux/rolling` box |
| Any platform | VirtualBox | Opt out: `VAGRANT_PROVIDER=virtualbox` — no plugin needed |
| macOS | Parallels Desktop | `VAGRANT_PROVIDER=parallels` — requires plugin |

`vmware_desktop` is the default provider on every platform. VirtualBox remains
supported as a no-plugin fallback via `VAGRANT_PROVIDER=virtualbox`.

```sh
# All platforms
brew install vagrant

# VMware (default provider — all platforms)
vagrant plugin install vagrant-vmware-desktop
# Also install the VMware Utility: https://developer.hashicorp.com/vagrant/install/vmware

# Parallels
vagrant plugin install vagrant-parallels
```

On Windows, run the `pt-ai` wrapper from WSL. The only macOS-only piece is `box/build.sh` (Step 1).

---

### Step 1 — Build the Kali ARM64 box (Apple Silicon only)

**Skip on Intel Mac / Linux** — the official `kalilinux/rolling` box (which ships a `vmware_desktop` variant) is used automatically. `box/build.sh` exists only because there is no official Kali ARM64 VMware box.

```sh
./box/build.sh
```

Downloads the Kali ARM64 installer ISO (~4 GB), installs it inside VMware Fusion, and packages a local Vagrant box. **One-time — takes 30–60 min.** When prompted, type `vagrant` as the SSH password.

---

### Step 2 — Configure your environment

```sh
cp config/engagement.env.example config/.env
```

For Apple Silicon, set the box (`vmware_desktop` is already the default provider,
so it no longer needs to be set explicitly):

```sh
# config/.env
export PTAI_BOX=kali-arm64
```

To build on a non-Kali, apt-family box instead, set `PTAI_BOX` to any such box
(e.g. `ubuntu/jammy`); Kali-specific provisioning auto-skips. See
[Using a different box](#using-a-different-box) below. `KALI_BOX` is still
honored for back-compat.

Source it before using the VM:

```sh
source config/.env
```

---

### Step 3 — Boot and provision

```sh
./pt-ai up
```

First run provisions the VM automatically (~30–60 min depending on network):
- System update + base dependencies
- Kali toolset (`kali-linux-default`, Kali boxes only) + apt extras from `config/tools.txt`, plus a few non-apt offensive tools (`frida`, `objection`, `kerbrute`)
- Claude Code CLI (installed as the vagrant user so self-updates work)
- Network config: IP forwarding, iptables open policy, openvpn/proxychains
- opencode CLI + pt-ai skills (read natively) and agents (as opencode subagents)
- Cloud-audit toolset: AWS CLI v2 (GPG-signature verified), prowler, scoutsuite, trufflehog, gitleaks, gcloud, kubeaudit (plus apt pacu, kubectl, trivy, azure-cli, kube-hunter)
- ghidrasql: Ghidra 12.0.4 + libghidra + ghidrasql (on aarch64, the native decompiler is built from source — adds time to the first provision)
- ghidra-rpc: PyGhidra-backed RE daemon (cellebrite-labs/ghidra-rpc via `uv`), provisioned alongside ghidrasql and sharing the same Ghidra install

Subsequent `./pt-ai up` calls boot in seconds — provisioning is skipped.

---

### Step 4 — Authenticate Claude Code

Two options. Pick one per VM.

#### Option A — API key (Anthropic API)

Bills against your Anthropic API key, not a Pro/Max subscription.

```sh
# Session-only (key forwarded for this run, never stored in VM):
export ANTHROPIC_API_KEY=sk-ant-...
./pt-ai claude

# Persistent (stored in VM, picked up by all future sessions):
export ANTHROPIC_API_KEY=sk-ant-...
./pt-ai key store
./pt-ai claude

# Remove a stored key:
./pt-ai key clear
```

#### Option B — OAuth (Claude Pro / Max)

```sh
./pt-ai claude
```

On first run, Claude Code prints a URL — open it in your host browser to complete the OAuth login. **You only need to do this once per VM.** Credentials are stored in `~/.claude/` inside the VM and persist across `halt`/`up` cycles and snapshots.

**Precedence:** if both a stored API key and OAuth credentials exist, the API key wins.

After authenticating, exit Claude Code (`/exit`) and take your baseline snapshot:

```sh
./pt-ai snapshot pre-engagement
```

This captures the fully-provisioned, authenticated state. Restore to it between engagements.

---

### Step 5 — (Optional) opencode

opencode is installed alongside Claude Code. Use it when you want a provider-agnostic CLI: pt-ai's skills are discovered natively (model-invoked, same as in Claude Code) and its agents are available as opencode subagents (e.g. `@recon-advisor`).

```sh
./pt-ai opencode
```

**Auth — read this before first use.** opencode does **not** consume Claude Code's `~/.claude/` OAuth tokens. It requires an Anthropic API key, supplied in one of three ways:

| Method | How |
|---|---|
| Session-only | `export ANTHROPIC_API_KEY=sk-ant-... && ./pt-ai opencode` |
| Persistent (shared with Claude Code) | `./pt-ai key store` |
| opencode's own OAuth | Inside the VM: `opencode auth login anthropic` |

**Billing:** opencode bills against your API key. A Pro/Max subscription covers Claude Code only — opencode usage is pay-as-you-go.

**Model:** defaults to `anthropic/claude-sonnet-4-6`. Override per session:

```sh
export PT_AI_OPENCODE_MODEL=anthropic/claude-opus-4-7
./pt-ai opencode
```

Skills are read natively (via the `~/.claude/skills` symlink) and agents are generated as opencode subagents at provision time. To pick up host-side skill/agent edits, re-run `./pt-ai provision`.

---

## Daily workflow

```sh
# Boot
source config/.env
./pt-ai up

# Start a Claude Code session (opens in /engagements)
./pt-ai claude

# Or start an opencode session (opens in /engagements)
./pt-ai opencode

# Drop to a shell if needed
./pt-ai ssh

# Restore clean state after an engagement
./pt-ai restore pre-engagement

# Shut down when done
./pt-ai halt
```

The host `engagements/` directory is synced to `/engagements/` inside the VM. Run
`/scope-declare` at the start of every Claude Code session — it creates the per-engagement
subdirectory and writes `scope.md` there. All agents and skills save evidence to that
directory using absolute paths, so files appear on the host in real time and survive
snapshot restores.

```sh
./pt-ai claude
# Inside Claude Code, run:
/scope-declare      # sets engagement ID, creates /engagements/{id}/, writes scope.md
```

---

## Tool customisation

Edit `config/tools.txt` (one apt package per line) then re-provision:

```sh
./pt-ai provision
```

---

## Reverse engineering: ghidrasql + ghidra-rpc

Two complementary RE engines over Ghidra are provisioned **side by side** so you can
use whichever fits the task (or run both and cross-validate). They share the same
Ghidra install and, on aarch64, the same self-built native decompiler.

- **ghidrasql** — declarative **SQL** over the program DB (57 tables / 77 views).
  Best for bulk/relational work and set-based annotation (`UPDATE … ; save_database()`).
- **ghidra-rpc** — imperative **verb CLI** (68 commands, JSON out) over a warm PyGhidra
  daemon. Best for step-by-step RE, struct reconstruction, byte patching, and function
  diffing.

Each can be skipped independently (`PTAI_SKIP_GHIDRASQL`, `PTAI_SKIP_GHIDRA_RPC`).
Two model-invocable skills wrap the end-to-end "full static disassembly analysis +
report" workflow for each engine: **`/disasm-ghidrasql`** and **`/disasm-ghidra-rpc`**
(authored once under `skills/`, read natively by both Claude Code and opencode).

### ghidrasql

[`ghidrasql`](https://github.com/0xeb/ghidrasql) exposes a SQL interface over a
binary's Ghidra analysis database — query functions, strings, decompiled pseudocode,
and more, one-shot or over HTTP; write-through annotation via `UPDATE`/`DELETE` +
`save_database()`. The toolchain (Ghidra 12.0.4, JDK 21, the libghidra
extension, and the ghidrasql binary) is provisioned by `provision/07-ghidrasql.sh`.

**aarch64 note.** The official Ghidra release ships no `linux_arm_64` native
decompiler, so on Apple Silicon `provision/07-ghidrasql.sh` builds it from the
decompiler source bundled in the release. This is the slowest step of the first
provision. If the build fails, ghidrasql still runs but decompiler-backed tables
(`pseudocode`, `decomp_*`) will error.

ghidrasql runs inside the VM — open a shell with `./pt-ai ssh` (a login shell that
sources its env) and run it from `/engagements`, so `--binary` relative paths resolve
there. The **`--project` path must be absolute** — Ghidra rejects any path element
starting with `.` (so `./proj` fails; use `/tmp/…` or `/engagements/…`).

```sh
# One-shot query against a binary
ghidrasql --binary ./samples/target --project /tmp/gsql --project-name demo \
  --analyze -q "SELECT name, printf('0x%X', address) AS addr FROM funcs ORDER BY size DESC LIMIT 5"

# Background HTTP mode, then query over curl (from the same VM shell)
ghidrasql --binary ./samples/target --project /tmp/gsql --project-name demo \
  --analyze --http --port 8081 --max-runtime 0
# curl -s -X POST http://127.0.0.1:8081/query --data "SELECT COUNT(*) FROM funcs;"
```

`GHIDRA_INSTALL_DIR` is exported VM-wide, so `--ghidra` is auto-filled. For
`--url` attach mode (which conflicts with that var), prefix the call with
`env -u GHIDRA_INSTALL_DIR`.

`provision/07-ghidrasql.sh` carries local patches for two upstream bugs
([#1](https://github.com/0xeb/ghidrasql/issues/1),
[#2](https://github.com/0xeb/ghidrasql/issues/2)) and for GCC 15 / libxsql
build compatibility. Drop the relevant patch once a fix lands upstream.

Override pinned versions at provision time via VM env (`GHIDRA_VERSION`,
`GHIDRA_RELEASE_TAG`, `GHIDRA_ZIP`, `GRADLE_VERSION`). The Ghidra and Gradle zips are
verified against pinned SHA-256 sums (`GHIDRA_SHA256`, `GRADLE_SHA256`) before install
and provisioning **fails closed** on mismatch — bump the SHA whenever you bump the version.

> **Security note.** ghidrasql's `--http`/`--serve` mode opens a local network
> surface. It binds `127.0.0.1` by default — keep it there, and use `--auth <token>`
> if your build supports it. The `/disasm-ghidrasql` skill does this and tears the
> host down when done.

### ghidra-rpc

[`ghidra-rpc`](https://github.com/cellebrite-labs/ghidra-rpc) is a persistent RE
daemon that embeds Ghidra in-process via PyGhidra and exposes a verb CLI returning
JSON. Provisioned by `provision/08-ghidra-rpc.sh` (pure Python: `uv tool install` —
no C++/Gradle build). Unlike ghidrasql it talks over a **Unix socket** (no network
surface), supports **binary patching** (`assemble`/`write-bytes`) and **function
diffing** (`function-diff`/`match-function`), and keeps the analysis session warm.

The daemon has its own lifecycle, driven inside the VM (`./pt-ai ssh`, then from
`/engagements`) via the `ghidra-rpc` binary:

```sh
# Start the warm daemon (--headless --detach so it survives the shell), load, query
ghidra-rpc start --headless --detach --project /engagements/demo.gpr
ghidra-rpc load ./samples/target
ghidra-rpc functions ls --limit 5
ghidra-rpc decompile target main
ghidra-rpc stop
```

Pass `--headless --detach` so the daemon survives the shell session.
`GHIDRA_INSTALL_DIR` is exported VM-wide; the daemon needs it. The daemon is stopped
automatically before `./pt-ai snapshot` and after `./pt-ai restore` so a live
JVM/socket isn't captured in (or left stale across) a VM image.

Override the source revision with `GHIDRA_RPC_REF` (a tag/commit; defaults to `main`).

---

## Using a different box

The VM is Kali by default but works on any **apt-family** box (Ubuntu, Debian,
Parrot, Linux Mint, …). Set `PTAI_BOX` to the box you want:

```sh
export PTAI_BOX=ubuntu/jammy
./pt-ai up
```

A capability probe (`provision/_lib.sh`) detects the guest from `/etc/os-release`
and runs the Kali-only steps — the `kali-rolling` repo, `kali-linux-default`, and
the Kali-pinned `unattended-upgrades` origin — **only on a Kali guest**. The
pt-ai framework layer (Claude Code, opencode, agents, network config, SSH
hardening, cloud tooling) provisions identically on every apt-family box.
Kali-only package names in `config/tools.txt` simply warn-and-skip elsewhere;
add box-appropriate tools there.

Non-apt boxes (Fedora, Arch, …) are out of scope: provisioning warns and skips
its package steps rather than failing. `KALI_BOX` is still honored as a fallback
for `PTAI_BOX`.

To skip the heavy Ghidra-backed builds on any box, set `PTAI_SKIP_GHIDRASQL=1`
and/or `PTAI_SKIP_GHIDRA_RPC=1` (they are independent).

---

## Environment variables

| Variable | Default | Description |
|---|---|---|
| `PTAI_BOX` | `kalilinux/rolling` | Vagrant box. Any apt-family box; Kali-only steps auto-skip (use `kali-arm64` on Apple Silicon) |
| `PTAI_SKIP_GHIDRASQL` | — | Set to any value to skip the heavy ghidrasql provisioner |
| `PTAI_SKIP_GHIDRA_RPC` | — | Set to any value to skip the ghidra-rpc provisioner |
| `GHIDRA_RPC_REF` | `main` | ghidra-rpc source revision (tag/commit) to install |
| `KALI_BOX` | — | Legacy alias for `PTAI_BOX` (still honored as a fallback) |
| `VAGRANT_PROVIDER` | `vmware_desktop` | Set `virtualbox` to use VirtualBox (no plugin needed) |
| `VAGRANT_MEMORY` | `4096` | VM RAM in MB |
| `VAGRANT_CPUS` | `4` | vCPU count |
| `ANTHROPIC_API_KEY` | — | Optional — forwarded per-session if set; see `./pt-ai key` for persistent storage. Used by both Claude Code and opencode |
| `PT_AI_OPENCODE_MODEL` | `anthropic/claude-sonnet-4-6` | Optional — overrides opencode's default model per session |

---

## Subcommands

```
./pt-ai up                    Boot VM (provision on first run)
./pt-ai claude [--fresh] [-- <args>]    Start Claude Code session inside VM (--fresh wipes prior session history; creds preserved)
./pt-ai opencode [--fresh] [-- <args>]  Start opencode session inside VM (--fresh wipes prior session history; auth preserved)
./pt-ai ssh                   Interactive shell inside VM
./pt-ai key store             Store ANTHROPIC_API_KEY from host env into VM
./pt-ai key clear             Remove stored API key from VM
./pt-ai key status            Show whether an API key is stored in VM
./pt-ai engagement list       List engagements and their on-disk sizes
./pt-ai engagement purge <id> Delete one engagement's data (-y to skip prompt)
./pt-ai engagement purge --all Delete all engagement data
./pt-ai snapshot <name>       Save a VM snapshot
./pt-ai restore  <name>       Restore a VM snapshot
./pt-ai halt                  Shut down the VM
./pt-ai destroy               Destroy the VM and all state
./pt-ai provision             Re-run all provisioners
./pt-ai status                Show VM status
```

Engagement data (findings, evidence, scope) is stored under `engagements/` on the
host (a synced folder, plaintext). See [docs/data-at-rest.md](../docs/data-at-rest.md)
for the at-rest threat model, FileVault guidance, and teardown with `engagement purge`.
