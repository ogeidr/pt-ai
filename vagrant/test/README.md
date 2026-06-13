# pt-ai VM — deployment test (Kali + Debian)

End-to-end test that the VM provisions correctly on **two boxes** and that the
multi-box decoupling (feature: `features/choose-vagrant-box.md`) behaves as
designed:

| Case | Box | Expectation |
|---|---|---|
| **kali** | `kali-arm64` (built via `./box/build.sh`) | Full provision; **Kali-only steps run** (kali-rolling repo, `kali-linux-default`, Kali-pinned unattended-upgrades). |
| **debian** | `bento/debian-13` (Debian 13 "trixie", arm64) | Framework layer provisions identically; **Kali-only steps skip**; ghidrasql + ghidra-rpc still build (apt-gated). |

Target environment (per decision): **Apple Silicon + VMware Fusion**
(`vmware_desktop`), arm64, **full** Debian run including ghidrasql and ghidra-rpc.

---

## Safety — this will NOT touch your working VM

The runner isolates all of its Vagrant state under `test/.vagrant-test/` using
`VAGRANT_DOTFILE_PATH`. Your normal `./pt-ai` VM, its OAuth credentials, and its
snapshots live under the default `.vagrant/` and are **never read, modified, or
destroyed** by this test. The two cases run sequentially against the isolated
machine and it is destroyed between cases (unless `KEEP=1`).

> Recommended: `./pt-ai halt` your working VM before running, to avoid two
> VMware VMs competing for CPU/RAM.

On startup the runner does a **preflight**: `vagrant global-status --prune`
plus a best-effort destroy of any leftover isolated test machine. This makes a
"start over" automatic after an interrupted run (e.g. a network drop). Prune
only removes index entries whose machine state is already gone, so your normal
`./pt-ai` VM is never affected.

---

## Prerequisites

1. macOS on Apple Silicon, VMware Fusion 13+ with the Vagrant plugin:
   ```sh
   vagrant plugin install vagrant-vmware-desktop
   ```
2. The **Kali ARM64 box built and registered** (one-time, ~30–60 min, interactive):
   ```sh
   cd vagrant
   ./box/build.sh        # produces/registers the kali-arm64 box
   vagrant box list      # confirm 'kali-arm64' is listed
   ```
3. A **Debian arm64 box that supports `vmware_desktop`**. Default is
   `bento/debian-13`. ⚠️ Verify it has an arm64 / vmware variant on Vagrant
   Cloud before running; if not, override with another box you trust:
   ```sh
   export TEST_DEBIAN_BOX=your/debian-arm64-box
   ```
   (Official `debian/*` boxes are amd64/VirtualBox only and will not work here.)

---

## Run it

The harness is a single script with two modes: on the host it drives `vagrant`;
inside the guest (`--assert`) it runs the checks. You only ever call the host form:

```sh
cd vagrant
./test/provision-test.sh both       # or: kali | debian
```

Useful overrides:

```sh
KEEP=1            ./test/provision-test.sh both       # leave the test VM up to inspect
TEST_DEBIAN_GHIDRA=0 ./test/provision-test.sh debian  # skip ghidrasql + ghidra-rpc on Debian (faster)
TEST_DEBIAN_BOX=foo/bar ./test/provision-test.sh debian
```

With `KEEP=1` the VM stays up, so you can re-run just the assertions (no
re-provision) against it:

```sh
VAGRANT_DOTFILE_PATH=test/.vagrant-test PTAI_BOX=bento/debian-13 \
  VAGRANT_PROVIDER=vmware_desktop \
  ./pt-ai ssh -c "EXPECT_GHIDRASQL=1 EXPECT_GHIDRA_RPC=1 bash /vagrant/test/provision-test.sh --assert"
```

---

## What gets asserted (`provision-test.sh --assert`, run inside each VM)

**Framework layer — must pass on BOTH boxes**

- `node` is v20+, `claude --version` runs, `opencode` present
- `~/.claude/CLAUDE.md` exists and carries the **Evidence path rules**
- `~/.claude/agents/*.md` populated; `recon-advisor.md` references
  `/engagements` and has **no** legacy `/work/` path
- **opencode parity:** `~/.config/opencode/agents/*.md` subagents generated and
  carry the injected scope guard; advisory agents (e.g. `report-generator`)
  get `bash: deny` while Tier-2 agents (e.g. `recon-advisor`) do not; skills are
  discovered via the `~/.claude/skills` Claude-compat symlink; the legacy
  `~/.config/opencode/commands/` dir is **absent**
- `/engagements` exists and is **writable** (real touch/rm probe)
- `net.ipv4.ip_forward=1`; SSH password auth + root login disabled
- `unattended-upgrades` installed; `aws` (v2), `trufflehog`, `prowler` present
- `/vagrant/provision/_lib.sh` present and detects `IS_APT`

**Kali case — Kali-only steps PRESENT**

- kali-rolling apt source present; `kali-linux-default` installed
- unattended-upgrades pinned to `origin=Kali`; `_lib.sh` reports `IS_KALI=true`

**Debian case — Kali-only steps ABSENT**

- no kali-rolling source; `kali-linux-default` **not** installed
- no `origin=Kali` in unattended-upgrades; `_lib.sh` reports `IS_KALI=false`

**ghidrasql (when expected)**

- `/usr/local/bin/ghidrasql` present and `--help` runs

**ghidra-rpc (when expected)**

- `/usr/local/bin/ghidra-rpc` present and `--version` runs

---

## Outputs & pass criteria

```
test/results/
├── kali-provision.log     # full ./pt-ai up output
├── kali-assert.log        # assertion results
├── debian-provision.log
├── debian-assert.log
└── summary.txt            # one PASS/FAIL line per case
```

**Pass:** `summary.txt` shows `PASS` for both cases (provision succeeded and
every assertion passed). The runner's exit code is non-zero if any case failed.

---

## Fix loop

1. You run `./test/provision-test.sh both`.
2. The logs above are written to `test/results/` (host-side, gitignored).
3. I read them, fix any provisioning/assertion failure, and you re-run — until
   `summary.txt` is all-PASS.

---

## Known risk / open item

- **Debian arm64 + VMware box availability.** This is the only external
  unknown. If `bento/debian-13` lacks an arm64/vmware variant, the `debian`
  case fails at `vagrant up` (clear box-not-found error). Resolve by setting
  `TEST_DEBIAN_BOX` to a working box, or by adding a Debian build path
  analogous to `box/build.sh`. Flagged here rather than guessed.
