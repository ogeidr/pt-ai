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
| Apple Silicon Mac | VMware Fusion 13+ Pro (free) | Recommended — tested |
| Intel Mac / Linux | VirtualBox | Default, no extra config |
| macOS (either) | Parallels Desktop | Requires plugin |

```sh
# All platforms
brew install vagrant

# VMware Fusion (Apple Silicon)
vagrant plugin install vagrant-vmware-desktop
# Also install the VMware Utility: https://developer.hashicorp.com/vagrant/install/vmware

# Parallels
vagrant plugin install vagrant-parallels
```

On Windows, run the `kali` wrapper from WSL. The only macOS-only piece is `box/build.sh` (Step 1).

---

### Step 1 — Build the Kali ARM64 box (Apple Silicon only)

**Skip on Intel Mac / Linux** — VirtualBox uses the official `kalilinux/rolling` box automatically. `box/build.sh` exists only because there is no official Kali ARM64 VMware box.

```sh
./box/build.sh
```

Downloads the Kali ARM64 installer ISO (~4 GB), installs it inside VMware Fusion, and packages a local Vagrant box. **One-time — takes 30–60 min.** When prompted, type `vagrant` as the SSH password.

---

### Step 2 — Configure your environment

```sh
cp config/engagement.env.example config/.env
```

For Apple Silicon, set the provider and box:

```sh
# config/.env
export PTAI_BOX=kali-arm64
export VAGRANT_PROVIDER=vmware_desktop
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
./kali up
```

First run provisions the VM automatically (~30–60 min depending on network):
- System update + base dependencies
- Kali toolset (`kali-linux-default`, Kali boxes only) + extras from `config/tools.txt`
- Claude Code CLI (installed as the vagrant user so self-updates work)
- Network config: IP forwarding, iptables open policy, openvpn/proxychains
- opencode CLI + pt-ai agents converted to opencode slash commands
- Cloud-audit toolset: AWS CLI v2, prowler, scoutsuite, trufflehog (plus apt pacu, kube-hunter)
- ghidrasql: Ghidra 12.0.4 + libghidra + ghidrasql (on aarch64, the native decompiler is built from source — adds time to the first provision)

Subsequent `./kali up` calls boot in seconds — provisioning is skipped.

---

### Step 4 — Authenticate Claude Code

Two options. Pick one per VM.

#### Option A — API key (Anthropic API)

Bills against your Anthropic API key, not a Pro/Max subscription.

```sh
# Session-only (key forwarded for this run, never stored in VM):
export ANTHROPIC_API_KEY=sk-ant-...
./kali claude

# Persistent (stored in VM, picked up by all future sessions):
export ANTHROPIC_API_KEY=sk-ant-...
./kali key store
./kali claude

# Remove a stored key:
./kali key clear
```

#### Option B — OAuth (Claude Pro / Max)

```sh
./kali claude
```

On first run, Claude Code prints a URL — open it in your host browser to complete the OAuth login. **You only need to do this once per VM.** Credentials are stored in `~/.claude/` inside the VM and persist across `halt`/`up` cycles and snapshots.

**Precedence:** if both a stored API key and OAuth credentials exist, the API key wins.

After authenticating, exit Claude Code (`/exit`) and take your baseline snapshot:

```sh
./kali snapshot pre-engagement
```

This captures the fully-provisioned, authenticated state. Restore to it between engagements.

---

### Step 5 — (Optional) opencode

opencode is installed alongside Claude Code. Use it when you want a provider-agnostic CLI or want to invoke pt-ai agents as slash commands (e.g. `/recon-advisor`, `/vuln-scanner`).

```sh
./kali opencode
```

**Auth — read this before first use.** opencode does **not** consume Claude Code's `~/.claude/` OAuth tokens. It requires an Anthropic API key, supplied in one of three ways:

| Method | How |
|---|---|
| Session-only | `export ANTHROPIC_API_KEY=sk-ant-... && ./kali opencode` |
| Persistent (shared with Claude Code) | `./kali key store` |
| opencode's own OAuth | Inside the VM: `opencode auth login anthropic` |

**Billing:** opencode bills against your API key. A Pro/Max subscription covers Claude Code only — opencode usage is pay-as-you-go.

**Model:** defaults to `anthropic/claude-sonnet-4-6`. Override per session:

```sh
export PT_AI_OPENCODE_MODEL=anthropic/claude-opus-4-7
./kali opencode
```

Agents are converted to opencode commands at provision time. To pick up agent edits made on the host, re-run `./kali provision`.

---

## Daily workflow

```sh
# Boot
source config/.env
./kali up

# Start a Claude Code session (opens in /engagements)
./kali claude

# Or start an opencode session (opens in /engagements)
./kali opencode

# Drop to a shell if needed
./kali ssh

# Restore clean state after an engagement
./kali restore pre-engagement

# Shut down when done
./kali halt
```

The host `engagements/` directory is synced to `/engagements/` inside the VM. Run
`/scope-declare` at the start of every Claude Code session — it creates the per-engagement
subdirectory and writes `scope.md` there. All agents and skills save evidence to that
directory using absolute paths, so files appear on the host in real time and survive
snapshot restores.

```sh
./kali claude
# Inside Claude Code, run:
/scope-declare      # sets engagement ID, creates /engagements/{id}/, writes scope.md
```

---

## Tool customisation

Edit `config/tools.txt` (one apt package per line) then re-provision:

```sh
./kali provision
```

---

## ghidrasql

[`ghidrasql`](https://github.com/0xeb/ghidrasql) exposes a SQL interface over a
binary's Ghidra analysis database — query functions, strings, decompiled pseudocode,
and more, one-shot or over HTTP. The toolchain (Ghidra 12.0.4, JDK 21, the libghidra
extension, and the ghidrasql binary) is provisioned by `provision/07-ghidrasql.sh`.

**aarch64 note.** The official Ghidra release ships no `linux_arm_64` native
decompiler, so on Apple Silicon `provision/07-ghidrasql.sh` builds it from the
decompiler source bundled in the release. This is the slowest step of the first
provision. If the build fails, ghidrasql still runs but decompiler-backed tables
(`pseudocode`, `decomp_*`) will error.

The command runs in `/engagements`, so `--binary` relative paths resolve there.
The **`--project` path must be absolute** — Ghidra rejects any path element
starting with `.` (so `./proj` fails; use `/tmp/…` or `/engagements/…`).

```sh
# One-shot query against a binary
./kali ghidrasql -- --binary ./samples/target --project /tmp/gsql --project-name demo \
  --analyze -q "SELECT name, printf('0x%X', address) AS addr FROM funcs ORDER BY size DESC LIMIT 5"

# Background HTTP mode, then query over curl from inside the VM
./kali ghidrasql -- --binary ./samples/target --project /tmp/gsql --project-name demo \
  --analyze --http --port 8081 --max-runtime 0
# (from ./kali ssh) curl -s -X POST http://127.0.0.1:8081/query --data "SELECT COUNT(*) FROM funcs;"
```

`GHIDRA_INSTALL_DIR` is exported VM-wide, so `--ghidra` is auto-filled. For
`--url` attach mode (which conflicts with that var), prefix the call with
`env -u GHIDRA_INSTALL_DIR`.

`provision/07-ghidrasql.sh` carries local patches for two upstream bugs
([#1](https://github.com/0xeb/ghidrasql/issues/1),
[#2](https://github.com/0xeb/ghidrasql/issues/2)) and for GCC 15 / libxsql
build compatibility. Drop the relevant patch once a fix lands upstream.

Override pinned versions at provision time via VM env (`GHIDRA_VERSION`,
`GHIDRA_RELEASE_TAG`, `GHIDRA_ZIP`, `GRADLE_VERSION`).

---

## Using a different box

The VM is Kali by default but works on any **apt-family** box (Ubuntu, Debian,
Parrot, Linux Mint, …). Set `PTAI_BOX` to the box you want:

```sh
export PTAI_BOX=ubuntu/jammy
./kali up
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

To skip the heavy ghidrasql build on any box, set `PTAI_SKIP_GHIDRASQL=1`.

---

## Environment variables

| Variable | Default | Description |
|---|---|---|
| `PTAI_BOX` | `kalilinux/rolling` | Vagrant box. Any apt-family box; Kali-only steps auto-skip (use `kali-arm64` on Apple Silicon) |
| `PTAI_SKIP_GHIDRASQL` | — | Set to any value to skip the heavy ghidrasql provisioner |
| `KALI_BOX` | — | Legacy alias for `PTAI_BOX` (still honored as a fallback) |
| `VAGRANT_PROVIDER` | `virtualbox` | `vmware_desktop` for Apple Silicon |
| `VAGRANT_MEMORY` | `4096` | VM RAM in MB |
| `VAGRANT_CPUS` | `4` | vCPU count |
| `ANTHROPIC_API_KEY` | — | Optional — forwarded per-session if set; see `./kali key` for persistent storage. Used by both Claude Code and opencode |
| `PT_AI_OPENCODE_MODEL` | `anthropic/claude-sonnet-4-6` | Optional — overrides opencode's default model per session |

---

## Subcommands

```
./kali up                    Boot VM (provision on first run)
./kali claude [-- <args>]    Start Claude Code session inside VM
./kali opencode [-- <args>]  Start opencode session inside VM
./kali ghidrasql [args...]   Run ghidrasql inside VM (Ghidra SQL/HTTP interface)
./kali ssh                   Interactive shell inside VM
./kali key store             Store ANTHROPIC_API_KEY from host env into VM
./kali key clear             Remove stored API key from VM
./kali key status            Show whether an API key is stored in VM
./kali snapshot <name>       Save a VM snapshot
./kali restore  <name>       Restore a VM snapshot
./kali halt                  Shut down the VM
./kali destroy               Destroy the VM and all state
./kali provision             Re-run all provisioners
./kali status                Show VM status
```
