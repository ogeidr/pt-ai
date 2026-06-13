# Engagement Data at Rest

How pt-ai stores engagement data, what the at-rest exposure is, and the controls
that protect it. TL;DR: **rely on host full-disk encryption (FileVault) + the
already-in-place git exclusion + engagement teardown — not app-level encryption of
the findings store.**

## What is stored, and where

Everything an engagement produces lives under `/engagements/{safe_id}/`:

| File | Contents | Sensitivity |
|------|----------|-------------|
| `findings.jsonl` | the cross-agent findings store (see [findings-store.md](findings-store.md)) | high — vulns, targets, sometimes creds |
| `gates.jsonl` | phase state + operator approvals | medium |
| `scope.md` | engagement id, scope, authorization | medium |
| raw evidence (`nmap_*`, `nuclei_*`, decompiler output, `re/*/REPORT.md`, …) | tool output | high |

`/engagements` is a **Vagrant `synced_folder`** (`../engagements → /engagements`),
so this data physically lives **on the host disk in plaintext**, mirrored between
host and VM. That is the at-rest surface.

## Threat model and controls

| Threat | Control | Status |
|--------|---------|--------|
| Lost/stolen host | **FileVault** (full-disk encryption) — transparent, covers the VM disk, `engagements/`, and swap | **operator-confirmed** — check with `fdesetup status` |
| Accidental `git` commit/push of client data | `engagements/` is git-ignored (`.gitignore`) | ✅ in place (0 files tracked) |
| iCloud / Time Machine silently copying data off-box | exclude the repo / engagements path from cloud sync + backups | operator action |
| Other local users / processes reading it | restrict directory perms (`chmod 700 engagements`) | optional |
| Data lingering after the engagement closes | **`./pt-ai engagement purge`** (teardown) | ✅ tooling provided |

### FileVault is the primary control

On an APFS/SSD host, FileVault is the correct and complete answer to "encryption at
rest" for the lost/stolen-device threat: it encrypts the whole volume — VM image,
engagement data, and swap — transparently, with key management handled by the OS and
Secure Enclave. Confirm it is on:

```sh
fdesetup status      # → "FileVault is On."
```

If a client contract only says "data encrypted at rest," FileVault satisfies it.

### Why not encrypt `findings.jsonl` itself

App-level encryption of the findings store is **not** recommended. It would break the
store's core design — append-only (no rewrite races), git-diffable, `jq`/JSON-Schema
readable, concurrent multi-agent appends — by forcing a decrypt → append → re-encrypt
cycle on every write (reintroducing corruption/race risk and turning a streamable log
into an opaque blob). The real security boundary is **key management**, which app-level
crypto makes worse, not better:

- a key stored on the same host is co-resident with the data → marginal gain over FDE;
- a passphrase-derived key means the **autonomous agents cannot append** without the
  operator unlocking on every write → it kills the agent-first workflow.

It also conflicts with pt-ai's "few moving parts" principle.

## Engagement teardown (`./pt-ai engagement`)

pt-ai is *ephemeral by design* — but on the host the synced folder persists
until removed. This command operationalizes that:

```sh
./pt-ai engagement list              # engagements + on-disk sizes
./pt-ai engagement purge <id>        # delete one engagement (prompts; -y to skip)
./pt-ai engagement purge --all       # delete all engagement data (prompts; -y to skip)
```

It deletes on the host (and therefore in the VM, since the folder is synced) and works
whether or not the VM is running. Run it at engagement close to shrink the at-rest
window.

> **Secure-erase caveat.** On APFS/SSD this is a **logical** delete: copy-on-write and
> wear-leveling make in-place overwrite (`shred`) ineffective, so pt-ai does not pretend
> to do it. The bytes are protected by FileVault, and after `purge` the only recovery
> path is forensic recovery of an *unencrypted* disk — which FileVault prevents. This is
> why FDE, not overwrite, is the at-rest guarantee.

## If you need at-rest encryption beyond FileVault

Some engagements are contractually required to keep evidence in a separately encrypted
container (independent of the host volume key). Do this at the **volume** layer, not
per-file:

- **Encrypted APFS volume / sparsebundle** mounted at the engagements path — e.g. an
  encrypted disk image (`hdiutil create -encryption AES-256 -type SPARSEBUNDLE …`)
  mounted where `vagrant/../engagements` points, unlocked at engagement start, ejected
  at close. The findings store keeps all its append/diff/`jq` properties; the OS handles
  the key (Keychain or passphrase).
- **Encrypt-at-close** — `age`/`gpg` the whole `engagements/{id}/` into an archive when
  the engagement ends, then `./pt-ai engagement purge <id>` the plaintext.

Both satisfy "separately encrypted at rest" without touching the store's format.

## Operator checklist

1. `fdesetup status` → FileVault **On**.
2. `engagements/` stays git-ignored (don't override).
3. Exclude the repo from iCloud/Time Machine if those are active.
4. `./pt-ai engagement purge <id>` when an engagement closes.
5. Only if contractually required: mount `engagements/` on an encrypted volume.
