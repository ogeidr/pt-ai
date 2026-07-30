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

## Shared disassembly workflow (authoritative)

!`cat /opt/pt-ai/skills/_disasm-common.md 2>/dev/null || echo "⚠ Shared disasm workflow missing at /opt/pt-ai/skills/_disasm-common.md — STOP and re-provision before analyzing."`

## Instructions (ghidrasql specifics)

Follow the **shared disassembly workflow** above for scope/authorization, target resolution,
evidence-path setup, triage, and report structure. This skill drives **ghidrasql** — it exposes
the Ghidra program database as SQL: query 57 tables / 77 views, and apply annotations via
write-through `UPDATE`/`DELETE` + `save_database()`. It performs no binary patching (that is
ghidra-rpc's domain). Treat the sample's basename as `<bin>`.

### Tool setup — project path and CLI surface

After the shared "Set up evidence paths and triage" step (which defines `$ENGAGEMENT_DIR`,
`$SAMPLE`, and `$OUT`), add the ghidrasql project dir and confirm the CLI on this build. Ghidra
rejects any `--project` path whose elements start with `.`, so the project path **must be
absolute**:

```sh
PROJ="$OUT/gsql"                 # absolute project dir (Ghidra rejects ./ paths)
# Confirm the server flag name and options on THIS build before relying on them:
ghidrasql --help 2>&1 | sed -n '1,60p'
```

The pinned build uses `--http`; newer upstream uses `--serve`. Use whichever `--help` reports.
Server binds `127.0.0.1` by default; if `--auth`/`--bind` are listed, prefer `--bind 127.0.0.1`
and an `--auth` token.

### Bring up the warm SQL host (HTTP)

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

### Discover the schema, then extract (read phase)

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

### Decompilation of focus functions

`pseudocode` is keyed by `func_addr` (an integer address), not by name. Resolve the
address from `funcs`, then pull the code:

```sh
curl -s -X POST http://127.0.0.1:8081/query \
  --data "SELECT printf('0x%X',address) FROM funcs WHERE name='main';"
curl -s -X POST http://127.0.0.1:8081/query \
  --data "SELECT code FROM pseudocode WHERE func_addr = 0x401000;" > "$OUT/07-decomp-main.c"
```

### Annotation / write-through (OPTIONAL — agent applies as findings solidify)

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

### Tear down the host

```sh
curl -s -X POST http://127.0.0.1:8081/query --data "SELECT save_database();" >/dev/null 2>&1
kill "$(cat "$OUT/gsql.pid")" 2>/dev/null; rm -f "$OUT/gsql.pid"
```

### Assemble and present the report

Assemble the report per the shared **Report structure** above. Include the ghidrasql specifics:
top functions (by size), strings/IOCs, and the annotations applied. Note that
`/disasm-ghidra-rpc` can analyze the same sample for cross-validation, patching, or function
diffing.
