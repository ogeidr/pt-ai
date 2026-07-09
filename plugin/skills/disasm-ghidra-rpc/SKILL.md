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

!`cat engagements/scope.md 2>/dev/null || echo "No scope declared yet. Run /scope-declare before any analysis."`

## Evidence directory for this engagement

!`grep -m1 'Evidence directory:' engagements/scope.md 2>/dev/null | sed 's/.*Evidence directory: //' || echo "engagements (no scope declared — run /scope-declare first)"`

## ghidra-rpc availability

!`command -v ghidra-rpc 2>/dev/null || echo "ghidra-rpc NOT installed — re-provision without PTAI_SKIP_GHIDRA_RPC"`

## Ghidra runtime

!`ls -d /opt/ghidra_*_PUBLIC 2>/dev/null || echo "Ghidra not installed"`

## Decompiler native (aarch64 check)

!`ls /opt/ghidra_*_PUBLIC/Ghidra/Features/Decompiler/os/linux_arm_64/decompile 2>/dev/null || echo "(no linux_arm_64 decompiler — expected on x86_64; on ARM the decompile command may fail)"`

## Instructions

You are running a full **static disassembly analysis** of a single binary with
**ghidra-rpc** and producing a report. ghidra-rpc is a warm PyGhidra daemon driven
by a verb CLI that returns JSON (`{ok, result}`). All commands accept `--project`
(or the `GHIDRA_RPC_PROJECT` env var). Annotations mutate the **Ghidra project
database**, never the original sample. Binary patching and cross-build diffing are
supported but **off by default** (Step 9) — they require explicit user authorization.

The **Evidence directory** shown above is `ENGAGEMENT_DIR`. Use it as an absolute
path prefix for every output file. Never use relative paths.

### Step 1 — Confirm scope and authorization (MANDATORY)

1. Read `engagements/scope.md`. If missing, STOP and tell the user to run `/scope-declare`.
2. Extract `ENGAGEMENT_DIR` from the "Evidence directory:" line.
3. Reverse engineering a binary can carry legal/licensing constraints separate from
   network scope. Confirm the sample is authorized for RE before proceeding; if in
   doubt, ask the user.
4. If `ghidra-rpc` is not installed (see preamble), STOP and tell the user to
   re-provision without `PTAI_SKIP_GHIDRA_RPC`.

### Step 2 — Resolve the target binary

Determine the sample to analyze, in this order:
1. An explicit path the user/agent supplied.
2. Otherwise, look under `$ENGAGEMENT_DIR/samples/` and present candidates.

Confirm the chosen path exists and is a binary (`file <path>`). Do not analyze
anything outside the engagement without explicit confirmation.

### Step 3 — Set up paths and verify the CLI surface

```sh
test -d engagements && test -w engagements || { echo "ERROR: engagements not mounted/writable"; exit 1; }
ENGAGEMENT_DIR=$(grep -m1 'Evidence directory:' engagements/scope.md | sed 's/.*Evidence directory: //')
[ -z "$ENGAGEMENT_DIR" ] && ENGAGEMENT_DIR="engagements"
SAMPLE="<resolved path from Step 2>"
OUT="$ENGAGEMENT_DIR/re/$(basename "$SAMPLE")"
GPR="$OUT/grpc.gpr"             # absolute project file
mkdir -p "$OUT"
ghidra-rpc --help 2>&1 | sed -n '1,60p'   # confirm verbs/JSON shape on THIS build
```

### Step 4 — Triage

```sh
{ file "$SAMPLE"; echo "sha256: $(sha256sum "$SAMPLE" | awk '{print $1}')"; \
  echo "size:   $(stat -c %s "$SAMPLE") bytes"; } | tee "$OUT/00-triage.txt"
```

### Step 5 — Start the daemon and load the binary

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

### Step 6 — Static extraction (read phase)

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

### Step 7 — Decompilation of focus functions

Pick targets from the largest/most-referenced functions. On bad-instruction warnings,
fall back to `pcode --high`.

```sh
for fn in main; do
  ghidra-rpc decompile "$BIN" "$fn" --timeout 120 --project "$GPR" \
    | jq -r '.result.code // .result' > "$OUT/07-decomp-$fn.c"
done
```

### Step 8 — Annotation / define (OPTIONAL — agent applies as findings solidify)

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

### Step 9 — Patch / diff (OPTIONAL, EXCLUSIVE, OFF BY DEFAULT — explicit request only)

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

### Step 10 — Stop the daemon

```sh
ghidra-rpc stop --project "$GPR" | tee "$OUT/grpc-stop.json"
```

### Step 11 — Assemble and present the report

Write a consolidated report with the Write tool to the absolute path
`$OUT/REPORT.md`, containing:
- Sample identification (from `00-triage.txt`) and engagement ID from `engagements/scope.md`.
- Program metadata, memory map, relocations summary, function count.
- Imports/strings and API/capability assessment with xref evidence.
- Decompiled bodies of key functions (from `07-*`).
- Findings, annotations applied (Step 8), and any patch/diff performed (Step 9, with the
  authorization noted).
- An appendix listing the raw artifacts under `$OUT/`.

Then present a concise summary table (function count, notable APIs, key findings) and
remind the user the evidence is under `$OUT/` and synced to the host. Note that
`/disasm-ghidrasql` can analyze the same sample for bulk/relational cross-validation.
