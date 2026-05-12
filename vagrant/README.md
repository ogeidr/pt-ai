# Vagrant Kali VM

Reproducible, fully-provisioned Kali Linux VM for pt-ai engagements.
One command to boot; `vagrant snapshot` for clean-state management between engagements.

## Architecture

```
Host (macOS)
└── Kali VM (VMware Fusion / VirtualBox / Parallels)
    ├── Claude Code          — authenticated via OAuth (claude.ai/pro)
    ├── ghidrasql            — binary analysis via SQL for AI agents
    ├── kali-linux-default   — core Kali toolset + extras (see config/tools.txt)
    └── /engagements/        — synced from host engagements/
```

Claude Code runs directly inside the VM and invokes Kali tools via its built-in shell — no MCP bridge needed.

---

## First-time setup

### Prerequisites

Install the provider for your platform:

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

---

### Step 1 — Build the Kali ARM64 box (Apple Silicon only)

Skip this step on Intel/Linux — VirtualBox uses the official `kalilinux/rolling` box automatically.

```sh
./box/build.sh
```

This downloads the Kali ARM64 installer ISO (~4 GB), runs an automated install inside VMware Fusion, and packages the result as a local Vagrant box. **One-time operation — takes 30–60 min.**

When prompted, type `vagrant` as the SSH password.

---

### Step 2 — Configure your environment

```sh
cp config/engagement.env.example config/.env
```

For Apple Silicon, set the provider and box:

```sh
# config/.env
export KALI_BOX=kali-arm64
export VAGRANT_PROVIDER=vmware_desktop
```

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
- Kali toolset (`kali-linux-default` + extras from `config/tools.txt`)
- Claude Code CLI (installed as the vagrant user so self-updates work)
- Network config: IP forwarding, iptables open policy, openvpn/proxychains
- Ghidra + ghidrasql for binary analysis via SQL

Subsequent `./kali up` calls boot in seconds — provisioning is skipped.

---

### Step 4 — Authenticate Claude Code

```sh
./kali claude
```

On first run, Claude Code prints a URL — open it in your host browser to complete the OAuth login. **You only need to do this once per VM.**

After authenticating, exit Claude Code (`/exit`) and take your baseline snapshot:

```sh
./kali snapshot pre-engagement
```

This captures the fully-provisioned, authenticated state. Restore to it between engagements.

---

## Daily workflow

```sh
# Boot
source config/.env
./kali up

# Start a Claude Code session (opens in /engagements)
./kali claude

# Drop to a shell if needed
./kali ssh

# Restore clean state after an engagement
./kali restore pre-engagement

# Shut down when done
./kali halt
```

---

## Engagement directories

The host `engagements/` directory is synced to `/engagements/` inside the VM. Create one directory per engagement on the host — it appears immediately inside the VM.

```sh
mkdir ../engagements/client-abc
./kali claude   # Claude Code starts in /engagements
```

---

## Tool customisation

Edit `config/tools.txt` (one apt package per line) then re-provision:

```sh
./kali provision
```

---

## Environment variables

| Variable | Default | Description |
|---|---|---|
| `KALI_BOX` | `kalilinux/rolling` | Vagrant box (use `kali-arm64` on Apple Silicon) |
| `VAGRANT_PROVIDER` | `virtualbox` | `vmware_desktop` for Apple Silicon |
| `VAGRANT_MEMORY` | `4096` | VM RAM in MB |
| `VAGRANT_CPUS` | `4` | vCPU count |
| `ANTHROPIC_API_KEY` | — | Optional — forwarded via SSH if set; OAuth used otherwise |

---

## Subcommands

```
./kali up                  Boot VM (provision on first run)
./kali claude [-- <args>]  Start Claude Code session inside VM
./kali ssh                 Interactive shell inside VM
./kali snapshot <name>     Save a VM snapshot
./kali restore  <name>     Restore a VM snapshot
./kali halt                Shut down the VM
./kali destroy             Destroy the VM and all state
./kali provision           Re-run all provisioners
./kali status              Show VM status
```
