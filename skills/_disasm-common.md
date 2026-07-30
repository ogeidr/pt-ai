## Shared disassembly workflow (common to every disasm skill)

You are running a full **static disassembly analysis** of a single binary and producing a
report. Annotations mutate the **Ghidra project database**, never the original sample file.

The **Evidence directory** shown in the preamble above is `ENGAGEMENT_DIR`. Use it as an
absolute path prefix for every output file — never relative paths.

### Confirm scope and authorization (MANDATORY)

1. Read `/engagements/scope.md`. If missing, STOP and tell the user to run `/scope-declare`.
2. Extract `ENGAGEMENT_DIR` from the "Evidence directory:" line.
3. Reverse engineering a binary can carry legal/licensing constraints separate from network
   scope. Confirm the sample is authorized for RE before proceeding; if in doubt, ask the user.
4. If this skill's tool is not installed (see the availability preamble above), STOP and tell
   the user to re-provision without the tool's `PTAI_SKIP_*` flag.

### Resolve the target binary

Determine the sample to analyze, in this order:
1. An explicit path the user/agent supplied.
2. Otherwise, look under `$ENGAGEMENT_DIR/samples/` and present candidates.

Confirm the chosen path exists and is a binary (`file <path>`). Do not analyze anything outside
the engagement without explicit confirmation.

### Set up evidence paths and triage

```sh
test -d /engagements && test -w /engagements || { echo "ERROR: /engagements not mounted/writable"; exit 1; }
ENGAGEMENT_DIR=$(grep -m1 'Evidence directory:' /engagements/scope.md | sed 's/.*Evidence directory: //')
[ -z "$ENGAGEMENT_DIR" ] && ENGAGEMENT_DIR="/engagements"
SAMPLE="<resolved path from above>"
OUT="$ENGAGEMENT_DIR/re/$(basename "$SAMPLE")"
mkdir -p "$OUT"
{ file "$SAMPLE"; echo "sha256: $(sha256sum "$SAMPLE" | awk '{print $1}')"; \
  echo "size:   $(stat -c %s "$SAMPLE") bytes"; } | tee "$OUT/00-triage.txt"
```

Then set up the tool-specific project path and verify the CLI surface — see this skill's
**Tool setup** step below.

### Report structure (assemble at the end)

Write a consolidated report with the Write tool to the absolute path `$OUT/REPORT.md`, containing:
- Sample identification (from `00-triage.txt`) and engagement ID from `/engagements/scope.md`.
- Program metadata, memory map, function count (and top/most-referenced functions).
- Strings/imports and API/capability assessment with xref evidence.
- Decompiled bodies of key functions (from the `07-*` artifacts).
- Findings, any annotations applied, and any patch/diff performed (with its authorization noted).
- An appendix listing the raw artifacts under `$OUT/`.

Then present a concise summary table (function count, notable APIs, key findings) and remind the
user the evidence is under `$OUT/` and synced to the host.
