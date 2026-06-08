---
name: disasm-ghidrasql
description: >
  Full static disassembly analysis of a binary using ghidrasql — a SQL
  interface over a Ghidra program database (57 tables / 77 views). Use when
  reverse engineering or statically analyzing an executable, library, firmware
  image, malware sample, or CTF rev/pwn binary and the work is relational or
  bulk in nature: ranking functions, joining strings to the code that
  references them, mapping the call graph, or applying set-based annotations
  (rename/retype/comment via SQL UPDATE). Runs entirely inside the VM and saves
  evidence under the engagement directory. For step-by-step interactive RE,
  binary patching, or function diffing, prefer /disasm-ghidra-rpc instead.
disable-model-invocation: false
allowed-tools: Bash, Read, Write
---

## Current scope for this engagement

!`cat /engagements/scope.md 2>/dev/null || echo "No scope declared yet. Run /scope-declare before any analysis."`

## Evidence directory for this engagement

!`grep -m1 'Evidence directory:' /engagements/scope.md 2>/dev/null | sed 's/.*Evidence directory: //' || echo "/engagements (no scope declared — run /scope-declare first)"`

## ghidrasql availability

!`command -v ghidrasql 2>/dev/null || echo "ghidrasql NOT installed — re-provision without PTAI_SKIP_GHIDRASQL"`

## Ghidra runtime

!`ls -d /opt/ghidra_*_PUBLIC 2>/dev/null || echo "Ghidra not installed"`

## Decompiler native (aarch64 check)

!`ls /opt/ghidra_*_PUBLIC/Ghidra/Features/Decompiler/os/linux_arm_64/decompile 2>/dev/null || echo "(no linux_arm_64 decompiler — expected on x86_64; on ARM the pseudocode/decomp_* tables may error)"`

## Instructions

You are running a full **static disassembly analysis** of a single binary with
**ghidrasql** and producing a report. ghidrasql exposes the Ghidra program
database as SQL: query 57 tables / 77 views, and apply annotations via
write-through `UPDATE`/`DELETE` + `save_database()`. This skill mutates the
**Ghidra project database**, never the original sample file, and performs no
binary patching (that is ghidra-rpc's domain).

The **Evidence directory** shown above is `ENGAGEMENT_DIR`. Use it as an absolute
path prefix for every output file. Never use relative paths. Ghidra rejects any
`--project` path whose elements start with `.`, so the project path **must be
absolute**.

### Step 1 — Confirm scope and authorization (MANDATORY)

1. Read `/engagements/scope.md`. If missing, STOP and tell the user to run `/scope-declare`.
2. Extract `ENGAGEMENT_DIR` from the "Evidence directory:" line.
3. Reverse engineering a binary can carry legal/licensing constraints separate from
   network scope. Confirm the sample is authorized for RE before proceeding; if in
   doubt, ask the user.
4. If `ghidrasql` is not installed (see preamble), STOP and tell the user to
   re-provision without `PTAI_SKIP_GHIDRASQL`.

### Step 2 — Resolve the target binary

Determine the sample to analyze, in this order:
1. An explicit path the user/agent supplied.
2. Otherwise, look under `$ENGAGEMENT_DIR/samples/` and present candidates.

Confirm the chosen path exists and is a binary (`file <path>`). Treat its basename as
`<bin>`. Do not analyze anything outside the engagement without explicit confirmation.

### Step 3 — Set up paths and verify the CLI surface

```sh
test -d /engagements && test -w /engagements || { echo "ERROR: /engagements not mounted/writable"; exit 1; }
ENGAGEMENT_DIR=$(grep -m1 'Evidence directory:' /engagements/scope.md | sed 's/.*Evidence directory: //')
[ -z "$ENGAGEMENT_DIR" ] && ENGAGEMENT_DIR="/engagements"
SAMPLE="<resolved path from Step 2>"
OUT="$ENGAGEMENT_DIR/re/$(basename "$SAMPLE")"
PROJ="$OUT/gsql"                 # absolute project dir (Ghidra rejects ./ paths)
mkdir -p "$OUT"
# Confirm the server flag name and options on THIS build before relying on them:
ghidrasql --help 2>&1 | sed -n '1,60p'
```

The pinned build uses `--http`; newer upstream uses `--serve`. Use whichever
`--help` reports. Server binds `127.0.0.1` by default; if `--auth`/`--bind` are
listed, prefer `--bind 127.0.0.1` and an `--auth` token.

### Step 4 — Triage (before the SQL host)

```sh
{ file "$SAMPLE"; echo "sha256: $(sha256sum "$SAMPLE" | awk '{print $1}')"; \
  echo "size:   $(stat -c %s "$SAMPLE") bytes"; } | tee "$OUT/00-triage.txt"
```

### Step 5 — Bring up the warm SQL host (HTTP)

Start once in the background so every query reuses one analysis. Source the env so
`--ghidra` is auto-filled.

```sh
. /etc/profile.d/pt-ai-ghidrasql.sh 2>/dev/null
nohup ghidrasql --binary "$SAMPLE" --project "$PROJ" --project-name "$(basename "$OUT")" \
  --analyze --http --port 8081 --max-runtime 0 > "$OUT/gsql-server.log" 2>&1 &
echo $! > "$OUT/gsql.pid"
# Wait for auto-analysis to finish and the endpoint to answer:
until curl -fs -X POST http://127.0.0.1:8081/query --data "SELECT 1;" >/dev/null 2>&1; do
  sleep 3; echo "waiting for ghidrasql…"; done
echo "ghidrasql up on 127.0.0.1:8081"
```

`POST /query` takes **raw SQL in the body, not JSON**. Query with:
`curl -s -X POST http://127.0.0.1:8081/query --data "<SQL>"`.

### Step 6 — Discover the schema, then extract (read phase)

Confirm columns before trusting them, then capture each result under `$OUT/`:

```sh
curl -s -X POST http://127.0.0.1:8081/query --data ".tables"                          | tee "$OUT/01-tables.txt"
curl -s -X POST http://127.0.0.1:8081/query --data "SELECT * FROM db_info;"            | tee "$OUT/01-meta.json"
curl -s -X POST http://127.0.0.1:8081/query --data "SELECT * FROM segments ORDER BY 1;"| tee "$OUT/02-segments.json"
# Largest / most complex functions = where to focus (ghidrasql's bulk strength):
curl -s -X POST http://127.0.0.1:8081/query \
  --data "SELECT name, printf('0x%X',address) AS addr, size FROM funcs ORDER BY size DESC LIMIT 25;" | tee "$OUT/03-top-funcs.json"
curl -s -X POST http://127.0.0.1:8081/query --data "SELECT COUNT(*) AS n FROM funcs;"  | tee "$OUT/03-funccount.json"
# Strings + the functions that reference them:
curl -s -X POST http://127.0.0.1:8081/query --data "SELECT * FROM strings ORDER BY 1;" | tee "$OUT/04-strings.json"
curl -s -X POST http://127.0.0.1:8081/query \
  --data "SELECT * FROM string_refs WHERE string_value LIKE '%http%' OR string_value LIKE '%/tmp/%' OR string_value LIKE '%key%';" | tee "$OUT/04-strings-ioc.json"
# Imports / suspicious APIs:
curl -s -X POST http://127.0.0.1:8081/query \
  --data "SELECT * FROM names WHERE name LIKE '%recv%' OR name LIKE '%socket%' OR name LIKE '%crypt%' OR name LIKE '%exec%' OR name LIKE '%open%';" | tee "$OUT/05-apis.json"
# Call graph around a focus function (repeat per target from 03):
curl -s -X POST http://127.0.0.1:8081/query --data "SELECT * FROM callers  WHERE callee_name='main';" | tee "$OUT/06-callers-main.json"
curl -s -X POST http://127.0.0.1:8081/query --data "SELECT * FROM callees  WHERE caller_name='main';" | tee "$OUT/06-callees-main.json"
```

If a column name errors, run `.schema <table>` (or `SELECT * FROM <table> LIMIT 1`)
and adapt — column names vary by build.

### Step 7 — Decompilation of focus functions

`pseudocode` is keyed by `func_addr` (an integer address), not by name. Resolve the
address from `funcs`, then pull the code:

```sh
curl -s -X POST http://127.0.0.1:8081/query \
  --data "SELECT printf('0x%X',address) FROM funcs WHERE name='main';"
curl -s -X POST http://127.0.0.1:8081/query \
  --data "SELECT code FROM pseudocode WHERE func_addr = 0x401000;" > "$OUT/07-decomp-main.c"
```

### Step 8 — Annotation / write-through (OPTIONAL — agent applies as findings solidify)

ghidrasql persists annotations into the project DB. Skip this entire step if the user
asked for a non-mutating pass (or start the host with `--readonly`). Apply, then save:

```sh
curl -s -X POST http://127.0.0.1:8081/query \
  --data "UPDATE funcs SET name='parse_config' WHERE address=0x401234;"
curl -s -X POST http://127.0.0.1:8081/query \
  --data "UPDATE comments SET comment='parses tainted argv' WHERE address=0x401234;"
curl -s -X POST http://127.0.0.1:8081/query \
  --data "UPDATE signatures SET prototype='int parse_config(char*)' WHERE entry_point=0x401234;"
curl -s -X POST http://127.0.0.1:8081/query --data "SELECT save_database();"
```

For local variables, query the opaque `local_id` first and reuse it verbatim:
`SELECT local_id, role, name, type FROM decomp_lvars WHERE func_addr=0x401234;` then
`UPDATE decomp_lvars SET name='result' WHERE func_addr=0x401234 AND local_id='<exact>';`.
Always finish with `SELECT save_database();`.

### Step 9 — Tear down the host

```sh
curl -s -X POST http://127.0.0.1:8081/query --data "SELECT save_database();" >/dev/null 2>&1
kill "$(cat "$OUT/gsql.pid")" 2>/dev/null; rm -f "$OUT/gsql.pid"
```

### Step 10 — Assemble and present the report

Write a consolidated report with the Write tool to the absolute path
`$OUT/REPORT.md`, containing:
- Sample identification (from `00-triage.txt`) and engagement ID from `/engagements/scope.md`.
- Program metadata, memory map, function count, top functions.
- Strings/IOCs and API/capability assessment with xref evidence.
- Decompiled bodies of key functions (from `07-*`).
- Findings and any annotations applied in Step 8.
- An appendix listing the raw artifacts under `$OUT/`.

Then present a concise summary table (function count, notable APIs, key findings) and
remind the user the evidence is under `$OUT/` and synced to the host. Note that
`/disasm-ghidra-rpc` can analyze the same sample for cross-validation, patching, or
function diffing.
