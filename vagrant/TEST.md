# Full Vagrant Solution Test Plan

All platforms use the `vmware_desktop` Vagrant provider.

| Platform | Hypervisor | Box |
|---|---|---|
| Apple Silicon Mac | VMware Fusion 13+ | `kali-arm64` (built from `box/build.sh`) |
| Intel Mac | VMware Fusion 13+ | `kalilinux/rolling` (official, no build needed) |
| Linux | VMware Workstation | `kalilinux/rolling` (official, no build needed) |

Work through phases in order. Stop and fix before continuing if anything fails.

---

## Phase 0 — Prerequisites

**All platforms:**
```sh
vagrant --version           # 2.x
vagrant plugin list         # vagrant-vmware-desktop present
vmrun --version             # vmrun in PATH
```

Install the VMware Utility if not already done:
- Mac: https://developer.hashicorp.com/vagrant/install/vmware
- Linux: same URL, Linux package

**Apple Silicon — confirm no stale build artifacts:**
```sh
vagrant box list            # should NOT show kali-arm64
# Open VMware Fusion → Virtual Machine Library
# Delete kali-ptai-build if it exists
```

**All platforms — confirm no stale Vagrant state:**
```sh
# from repo root:
ls vagrant/.vagrant         # should not exist
# if it does: cd vagrant && vagrant destroy -f
```

**Pass:** Tools present, no leftover box or VM state.

---

## Phase 1 — Build the ARM64 box (Apple Silicon only)

> **Intel Mac and Linux: skip to Phase 2.** The official `kalilinux/rolling` box is used automatically.

```sh
cd vagrant
./box/build.sh
```

Checkpoints during the run:

1. ISO download begins — `==> Detecting latest Kali ARM64 ISO...`
2. Download completes — `Checksum OK` prints
3. VMware Fusion opens with the Kali installer — follow exactly:
   - Hostname: `kali-ptai` | Domain: (blank)
   - Username: `vagrant` | Password: `vagrant`
   - Partition: Guided — entire disk, all files in one partition
   - Software: keep defaults; ensure **SSH server** and **open-vm-tools** are selected
   - GRUB: install to primary EFI partition
4. After reboot into Kali, log in as `vagrant` and run:
   ```sh
   sudo systemctl enable --now ssh
   ip a    # note the NAT IP — needed next
   ```
5. Return to terminal, press Enter when prompted.
6. Script auto-detects IP (or you paste it) — type `vagrant` password once.
7. `==> Guest configuration done` prints, box is packaged.
8. `==> Done. Use with: KALI_BOX=kali-arm64 ...` prints.

Verify:
```sh
vagrant box list        # kali-arm64  (vmware_desktop, 0)
ls box/kali-arm64.box   # file exists
```

**Pass:** Box registered, `.box` file present.

---

## Phase 2 — Environment config

```sh
cp config/engagement.env.example config/.env
```

Edit `config/.env` for your platform:

**Apple Silicon:**
```sh
export KALI_BOX=kali-arm64
export VAGRANT_PROVIDER=vmware_desktop
```

**Intel Mac / Linux:**
```sh
export KALI_BOX=kalilinux/rolling
export VAGRANT_PROVIDER=vmware_desktop
```

Source it:
```sh
source config/.env
echo $KALI_BOX $VAGRANT_PROVIDER   # verify both set
```

**Pass:** Variables exported correctly.

---

## Phase 3 — First boot and provision

```sh
./kali up
```

Expected duration: 30–60 min. Milestones in order:

| Provisioner | Expected output |
|---|---|
| Inline | `kali-ptai` hostname set, resolv.conf written |
| `00-update.sh` | NodeSource repo added, `nodejs` installed, system updated |
| `01-tools.sh` | `kali-linux-default` and extras installed |
| `02-claude.sh` | Claude Code installed, CLAUDE.md written |
| `03-network.sh` | iptables policy set, openvpn/proxychains configured |
| `04-harden.sh` | SSH key-only, vagrant password locked, unattended-upgrades enabled |
| `05-opencode.sh` | opencode installed, agents converted, opencode.json written |
| `06-cloud.sh` | pipx/unzip installed, AWS CLI v2 unpacked, trufflehog binary fetched, prowler + scoutsuite pipx venvs created |

Completes with no `ERROR` lines and the shell prompt returns.

**Pass:** `./kali status` shows `running`.

---

## Phase 4 — Smoke tests inside VM

```sh
./kali ssh
```

```sh
# Identity
hostname                        # kali-ptai
whoami                          # vagrant

# DNS
cat /etc/resolv.conf            # nameserver 8.8.8.8 at top
curl -s https://example.com | head -5   # returns HTML

# Node / Claude Code
node --version                  # v20.x
which claude                    # /home/vagrant/.npm-global/bin/claude
claude --version                # prints version
echo $PATH | grep -o '\.npm-global/bin'   # .npm-global/bin

# Network tools
which nmap masscan proxychains4 openvpn   # all found

# Hardening (04-harden.sh)
sudo grep -E '^PasswordAuthentication|^PermitRootLogin' /etc/ssh/sshd_config
                                # PasswordAuthentication no
                                # PermitRootLogin no
sudo passwd -S vagrant          # 'L' in field 2 (password locked)
systemctl is-enabled unattended-upgrades   # enabled
systemctl is-active  unattended-upgrades   # active

# Claude config
ls ~/.claude/                   # CLAUDE.md  agents@  skills@
ls -la ~/.claude/agents         # symlink → /opt/pt-ai/agents
ls -la ~/.claude/skills         # symlink → /opt/pt-ai/skills

# opencode config
which opencode                  # /home/vagrant/.npm-global/bin/opencode
opencode --version              # prints version
ls ~/.config/opencode/          # commands/  opencode.json
ls ~/.config/opencode/commands/ | head   # recon-advisor.md, vuln-scanner.md, ...
cat ~/.config/opencode/opencode.json     # anthropic/claude-sonnet-4-6

# Synced dir
ls /engagements/                # synced from host ../engagements/

# Cloud-audit toolset (06-cloud.sh)
echo $PATH | grep -o '\.local/bin'         # .local/bin present
aws --version                              # aws-cli/2.x
which trufflehog                           # /usr/local/bin/trufflehog
trufflehog --version                       # prints version
which prowler scout                        # both under /home/vagrant/.local/bin
prowler --version                          # prints version
scout --help | head -1                     # Scout Suite usage banner

# Cloud companions (apt via tools.txt)
which pacu kube-hunter                     # both found
pacu --help        2>&1 | head -1          # banner / usage
kube-hunter --help 2>&1 | head -1          # banner / usage
```

```sh
exit
```

**Pass:** All checks return expected output with no errors.

---

## Phase 5 — Claude OAuth auth

```sh
./kali claude
```

1. Claude Code starts in `/engagements/`.
2. First run prints a URL — open it in your host browser and complete login.
3. Claude Code prints "Login successful" and shows the prompt.
4. Test prompt: `say hello` — Claude responds.
5. Exit: `/exit`
6. Run `./kali claude` again — no login prompt this time.

**Pass:** Second invocation starts without re-authentication.

---

## Phase 6 — API key auth

**Session-only (key forwarded, never stored in VM):**
```sh
export ANTHROPIC_API_KEY=sk-ant-YOUR-KEY
./kali claude
# Claude starts; exit with /exit
```

**Persistent key (store / verify / clear):**
```sh
# Store
export ANTHROPIC_API_KEY=sk-ant-YOUR-KEY
./kali key store
./kali key status       # API key stored in VM

# Verify key is used without env var
unset ANTHROPIC_API_KEY
./kali claude           # starts without login prompt; exit with /exit

# Clear
./kali key clear
./kali key status       # No API key stored in VM
```

**Pass:** All three subcommands work; key persists when stored, absent after clear.

---

## Phase 7 — Snapshot / restore cycle

```sh
./kali snapshot pre-engagement

./kali ssh
touch /tmp/engagement-artifact.txt
exit

./kali ssh -- "ls /tmp/engagement-artifact.txt"     # exists

./kali restore pre-engagement

./kali ssh -- "ls /tmp/engagement-artifact.txt 2>&1"   # No such file
```

**Pass:** Artifact absent after restore.

---

## Phase 8 — Halt and cold-boot verification

```sh
./kali halt
./kali status      # poweroff

./kali up          # fast boot, no provisioning output
./kali status      # running
```

**Pass:** Boot completes in under 2 minutes without re-provisioning.

---

## Phase 9 — Destroy and re-provision (optional)

Verifies full reprovisioning from the registered box:

```sh
./kali destroy
./kali up          # full provision (~30–60 min)
```

Repeat Phase 4 smoke tests.

**Pass:** Clean provision produces a fully working VM.

---

## Phase 10 — opencode

Requires an Anthropic API key (Pro/Max OAuth does not work for opencode).

```sh
export ANTHROPIC_API_KEY=sk-ant-YOUR-KEY
./kali opencode
```

1. opencode starts in `/engagements/` with no prompt about missing auth.
2. At the prompt, type `/` — the slash-command list shows pt-ai commands
   (e.g. `/recon-advisor`, `/vuln-scanner`, `/scope-declare`).
3. Run `/recon-advisor` — model responds (confirms provider + key are wired).
4. Exit with `Ctrl-C` or opencode's quit binding.

**Model override:**
```sh
export PT_AI_OPENCODE_MODEL=anthropic/claude-opus-4-7
./kali opencode    # prompt header should show the opus model
```

**Persistent key path:**
```sh
export ANTHROPIC_API_KEY=sk-ant-YOUR-KEY
./kali key store
unset ANTHROPIC_API_KEY
./kali opencode    # starts without prompting; uses stored key
```

**Agent edit re-sync:**
```sh
# On host: edit agents/recon-advisor.md (add a marker line)
./kali provision   # re-runs 05-opencode.sh
./kali ssh -- "grep -c MARKER ~/.config/opencode/commands/recon-advisor.md"
```

**Pass:** opencode starts, slash commands listed, model responds, model override visible in UI, stored key honored after unset, agent edits propagate after `./kali provision`.

---

## Phase 11 — Cloud-audit tool dry-run

Confirms the tools actually execute end-to-end, not just that the binaries resolve.
No AWS credentials are needed for these checks — every command is read-only and
local (no API calls to AWS/Azure/GCP).

```sh
./kali ssh
```

```sh
# Working dir for any output artifacts
mkdir -p /tmp/cloud-test && cd /tmp/cloud-test

# AWS CLI v2 — config + sts work locally; STS will fail without creds, that's fine.
aws configure list                          # 'not set' for credentials is OK
aws sts get-caller-identity 2>&1 | head -1  # expected: "Unable to locate credentials"

# prowler — list providers + checks (no scan run)
prowler --list-providers                    # aws / azure / gcp / kubernetes
prowler aws --list-checks | head -3         # at least one check listed

# scoutsuite — list supported providers
scout --help    | grep -A1 "{aws,azure,gcp" # provider choices visible

# trufflehog — scan a tiny local repo (this one) for secrets
trufflehog filesystem /vagrant --no-update --fail 2>&1 | tail -5
                                            # exits 0 if no verified secrets

# pacu — DB init + module list (no AWS calls)
pacu --list-modules 2>&1 | head -3          # modules enumerate

# kube-hunter — passive list (no scan)
kube-hunter --list 2>&1 | head -5           # known hunters listed
```

```sh
exit
```

**Pass:** Every tool prints its own output (not a "command not found" or Python
import error). STS / scan calls that need real creds may fail with explicit
"missing credentials" messages — that confirms the tool is wired up correctly.

---

## Summary checklist

- [ ] Phase 0 — prerequisites clean
- [ ] Phase 1 — `kali-arm64` box built and registered *(Apple Silicon only)*
- [ ] Phase 2 — env vars configured
- [ ] Phase 3 — provision completed without errors
- [ ] Phase 4 — all smoke tests pass
- [ ] Phase 5 — OAuth auth persists across sessions
- [ ] Phase 6 — API key store/clear/status all work
- [ ] Phase 7 — snapshot/restore cycle works
- [ ] Phase 8 — halt + cold boot skips provisioning
- [ ] Phase 10 — opencode session works end-to-end
- [ ] Phase 11 — cloud-audit tools (aws v2 / prowler / scoutsuite / trufflehog / pacu / kube-hunter) execute
