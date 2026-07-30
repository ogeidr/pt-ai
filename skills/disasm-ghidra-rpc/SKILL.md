---
name: disasm-ghidra-rpc
description: >
  Full static disassembly analysis of a binary using ghidra-rpc — an imperative
  verb CLI (68 commands, JSON output) backed by a warm PyGhidra daemon. Use when
  reverse engineering or statically analyzing an executable, library, firmware
  image, malware sample, or CTF rev/pwn binary and the work is interactive and
  step-by-step: decompiling functions, tracing xrefs, reconstructing structs,
  annotating, and (on explicit request) patching bytes or diffing two builds.
  Runs entirely inside the VM and saves evidence under the engagement directory.
  For bulk/relational queries over the whole program (ranking, joins, set-based
  edits), prefer /disasm-ghidrasql instead.
disable-model-invocation: false
allowed-tools: Bash, Read, Write
---

## Current scope for this engagement

!`cat /engagements/scope.md 2>/dev/null || echo "No scope declared yet. Run /scope-declare before any analysis."`

## Evidence directory for this engagement

!`grep -m1 'Evidence directory:' /engagements/scope.md 2>/dev/null | sed 's/.*Evidence directory: //' || echo "/engagements (no scope declared — run /scope-declare first)"`

## ghidra-rpc availability

!`command -v ghidra-rpc 2>/dev/null || echo "ghidra-rpc NOT installed — re-provision without PTAI_SKIP_GHIDRA_RPC"`

## Ghidra runtime

!`ls -d /opt/ghidra_*_PUBLIC 2>/dev/null || echo "Ghidra not installed"`

## Decompiler native (aarch64 check)

!`ls /opt/ghidra_*_PUBLIC/Ghidra/Features/Decompiler/os/linux_arm_64/decompile 2>/dev/null || echo "(no linux_arm_64 decompiler — expected on x86_64; on ARM the decompile command may fail)"`

## Shared disassembly workflow (authoritative)

!`cat /opt/pt-ai/skills/_disasm-common.md 2>/dev/null || echo "⚠ Shared disasm workflow missing at /opt/pt-ai/skills/_disasm-common.md — STOP and re-provision before analyzing."`

## Instructions (ghidra-rpc specifics)

Follow the **shared disassembly workflow** above for scope/authorization, target resolution,
evidence-path setup, triage, and report structure. This skill drives **ghidra-rpc** — a warm
PyGhidra daemon driven by a verb CLI that returns JSON (`{ok, result}`). All commands accept
`--project` (or the `GHIDRA_RPC_PROJECT` env var). Binary patching and cross-build diffing are
supported but **off by default** (patch/diff step) — they require explicit user authorization.

### Tool setup — project path and CLI surface

After the shared "Set up evidence paths and triage" step (which defines `$ENGAGEMENT_DIR`,
`$SAMPLE`, and `$OUT`), add the ghidra-rpc project file and confirm the CLI on this build:

```sh
GPR="$OUT/grpc.gpr"             # absolute project file
ghidra-rpc --help 2>&1 | sed -n '1,60p'   # confirm verbs/JSON shape on THIS build
```

### Start the daemon and load the binary

The daemon needs `GHIDRA_INSTALL_DIR`; source the env, then start headless+detached.
Pass `--project "$GPR"` on every subsequent command (each Bash call is a fresh shell),
or export `GHIDRA_RPC_PROJECT` at the top of each block.

```sh
. /etc/profile.d/pt-ai-ghidra-rpc.sh 2>/dev/null
ghidra-rpc start --project "$GPR" --headless --detach | tee "$OUT/grpc-start.json"
ghidra-rpc status --project "$GPR"
ghidra-rpc load "$SAMPLE" --project "$GPR" | tee "$OUT/grpc-load.json"
BIN=$(jq -r '.result.binary' "$OUT/grpc-load.json")   # binary key, e.g. /target-a1b2c3
echo "binary key: $BIN"
```

Binary/function targets are flexible: use the full key, its name part, an
unambiguous substring, a function name, or a hex address.

### Static extraction (read phase)

Capture each as JSON under `$OUT/`:

```sh
ghidra-rpc metadata    "$BIN" --project "$GPR" | tee "$OUT/01-meta.json"
ghidra-rpc memory-map  "$BIN" --project "$GPR" | tee "$OUT/02-memory.json"
ghidra-rpc relocations "$BIN" --project "$GPR" > "$OUT/02-relocs.json"
ghidra-rpc functions   "$BIN" --with-body --project "$GPR" > "$OUT/03-functions.json"
jq '.result | length' "$OUT/03-functions.json" | tee "$OUT/03-funccount.txt"
ghidra-rpc imports "$BIN" --project "$GPR" | tee "$OUT/05-imports.json"
ghidra-rpc exports "$BIN" --project "$GPR" > "$OUT/05-exports.json"
ghidra-rpc strings "$BIN" "" --limit 500 --project "$GPR" > "$OUT/04-strings.json"
ghidra-rpc strings "$BIN" "http" --limit 100 --project "$GPR" | tee "$OUT/04-strings-http.json"
```

Xrefs and basic blocks around focus functions (repeat per interesting target):

```sh
ghidra-rpc xrefs-to   "$BIN" main --project "$GPR"            | tee "$OUT/06-xrefs-to-main.json"
ghidra-rpc xrefs-from "$BIN" main --no-stack --project "$GPR" | tee "$OUT/06-xrefs-from-main.json"
ghidra-rpc basic-blocks "$BIN" main --project "$GPR"          > "$OUT/06-blocks-main.json"
```

### Decompilation of focus functions

Pick targets from the largest/most-referenced functions. On bad-instruction warnings,
fall back to `pcode --high`.

```sh
for fn in main; do
  ghidra-rpc decompile "$BIN" "$fn" --timeout 120 --project "$GPR" \
    | jq -r '.result.code // .result' > "$OUT/07-decomp-$fn.c"
done
```

### Annotation / define (OPTIONAL — agent applies as findings solidify)

Non-destructive to the sample; mutates the project DB (auto-saved). Skip if the user
wants a read-only pass.

```sh
ghidra-rpc rename-function "$BIN" FUN_00401234 parse_config --project "$GPR"
ghidra-rpc set-comment "$BIN" 0x00401234 "parses tainted argv" --type pre --project "$GPR"
ghidra-rpc set-signature "$BIN" parse_config "int parse_config(char *)" --project "$GPR"
ghidra-rpc retype-variable "$BIN" parse_config local_18 "char *" --project "$GPR"
# Reconstructed types:
ghidra-rpc create-struct "$BIN" Config int flags "char *" name --project "$GPR"
ghidra-rpc save --project "$GPR"
```

### Patch / diff (OPTIONAL, EXCLUSIVE, OFF BY DEFAULT — explicit request only)

These mutate program bytes or compare two builds. **Do not run without explicit user
authorization**, and state the OPSEC/integrity implication first.

```sh
# Patching (e.g. NOP out a check) — quote multi-word instructions:
ghidra-rpc assemble    "$BIN" 0x401234 "NOP" "NOP" --project "$GPR"
ghidra-rpc write-bytes "$BIN" 0x401234 "90 90" --project "$GPR"
# Diff against a second build loaded into the same project:
ghidra-rpc function-diff "$BIN" "<other-binary-key>" main --project "$GPR"
ghidra-rpc match-function "$BIN" "<other-binary-key>" --project "$GPR"
```

### Stop the daemon

```sh
ghidra-rpc stop --project "$GPR" | tee "$OUT/grpc-stop.json"
```

### Assemble and present the report

Assemble the report per the shared **Report structure** above. Include the ghidra-rpc specifics:
a relocations summary, the annotations applied, and any patch/diff performed (with its
authorization noted). Note that `/disasm-ghidrasql` can analyze the same sample for
bulk/relational cross-validation.
