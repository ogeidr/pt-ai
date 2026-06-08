# RedSun LPE — Static Analysis Report

**Engagement:** redsun  
**Engagement Type:** Defensive Review  
**Files Analyzed:** `RedSun.cpp`, `redsun.jpg`

---

> **Sanitisation note — all items removed:**
>
> | Item | Action |
> |------|--------|
> | Analyst email | **Removed** |
> | Analysis date | **Removed** |
> | Local filesystem paths (project dir, Ghidra install) | **Removed** — replaced with `<project_dir>` / `<ghidra_install_dir>` |
> | Daemon socket path | **Removed** — replaced with `<runtime_socket>` |
> | Timestamped evidence filenames | **Removed** — replaced with generic names |

---

## Executive Summary

RedSun is a **Windows Local Privilege Escalation (LPE)** exploit targeting a race condition between a Cloud Files API placeholder, an opportunistic lock (OPLOCK), and an AV scanner callback. The exploit abuses **Windows Storage Spaces Tier Management Engine** (`TieringEngineService.exe`) to obtain a privileged impersonation token, then spawns `conhost.exe` via `CreateProcessAsUser` with a duplicated SYSTEM-level token.

The attack chain relies on three interacting Windows subsystems:

1. **Cloud Files API (CfAPI)** — creates an OneDrive-style placeholder file that causes an AV scanner to open and scan the file, triggering a callback
2. **Opportunistic Lock (OPLOCK)** — holds the placeholder file open via `FSCTL_REQUEST_BATCH_OPLOCK`, preventing the AV scan from completing until the exploit releases it
3. **NTFS Reparse Point (junction)** — replaces the working temp directory with a junction pointing to `C:\Windows\System32`, so that when the OPLOCK is released and the AV scanner resumes walking the path, it operates in System32 rather than the temp dir

The net effect is a rename collision: the AV scanner (running as a privileged service) renames what it thinks is a file in `%TEMP%\RS-<x>` but is actually renaming a file within `C:\Windows\System32`, overwriting `TieringEngineService.exe` with attacker-controlled content. A subsequent COM activation of the Storage Spaces GUID launches the replaced binary as SYSTEM.

The accompanying `redsun.jpg` file is a clean JPEG image — decorative/thematic only, with no embedded code or secondary format content.

---

## File Inventory

| File | Size | Type |
|------|------|------|
| `RedSun.cpp` | 27,276 bytes | C++ Windows LPE source code |
| `redsun.jpg` | 65,750 bytes | JPEG image (1111×693, baseline) |

---

## Analysis 1 — ghidrasql (SQL Interface / Headless Ghidra)

**Tool:** ghidrasql via Ghidra 12.0.4  
**Method:** Raw Binary loader, x86-64 LE, Windows compiler spec  
**Project:** `<project_dir>/redsun_sql.gpr`

### Program Options (applied to both files)

| Key | Value |
|-----|-------|
| `analysis.headless` | `true` |
| `analysis.language_id` | `x86:LE:64:default` |
| `analysis.compiler_spec` | `windows` |
| `analysis.image_base` | `0` |

### Program 1: `RedSun.cpp` (27,276 bytes)

**Memory Blocks**

| Start | End | Name | Class | Size | Executable |
|-------|-----|------|-------|------|------------|
| `0x0` | `0x6a8b` | ram | CODE | 27,276 | Yes |

**Functions:** 0  
**Instructions:** 0  
**Strings (Ghidra scanner):** 0

> Ghidra's built-in string scanner finds null-terminated byte sequences. Source code strings are CRLF-delimited text — no null terminators are present in the raw file content. The scanner result of 0 is expected and correct; supplemental `strings` CLI extraction was performed.

**Key strings extracted via `strings` CLI:**

| Category | Value |
|----------|-------|
| Author comment | `// It gets funnier as time passes...` |
| Named pipe (IPC) | `\\??\pipe\REDSUN` |
| Temp directory | `%TEMP%\RS-` |
| Target binary | `TieringEngineService.exe` |
| Target NT path | `\\??\C:\Windows\System32\TieringEngineService.exe` |
| Reparse junction target | `\\??\C:\Windows\System32` |
| CF provider name | `SERIOUSLYMSFT` |
| COM GUID | `{0x50d185b9, 0xfff3, 0x4656, {0x92,0xc7,0xe4,0x01,0x8d,0xa4,0x36,0x1d}}` |
| VSS detection string | `HarddiskVolumeShadowCopy` |
| EICAR (reversed) | `*H+H$!ELIF-TSET-SURIVITNA-DRADNATS-RACIE$}7)CC7)^P(45XZP\4[PA@%P!O5X` |
| Success message | `The red sun shall prevail.` |
| Spawned process | `C:\Windows\System32\conhost.exe` |
| Runtime-resolved NTDLL functions | `NtOpenDirectoryObject`, `NtQueryDirectoryObject`, `NtSetInformationFile` |

### Program 2: `redsun.jpg` (65,750 bytes)

**Memory Blocks:** `0x0`–`0x100d5`, 65,750 bytes  
**Functions:** 0 | **Instructions:** 0 | **Strings:** 0

No strings found via either Ghidra scanner or `strings` CLI (only JPEG quantization artifact bytes). The file is a clean JPEG image.

---

## Analysis 2 — ghidra-rpc (RPC Daemon Interface)

**Tool:** ghidra-rpc / Ghidra 12.0.4 headless daemon  
**Socket:** `<runtime_socket>`  
**Project:** `<project_dir>/redsun_sql.gpr`

### Metadata Summary

| Program | Arch | Bits | Endian | Format | Functions |
|---------|------|------|--------|--------|-----------|
| `RedSun.cpp` | x86 | 64 | LE | Raw Binary | 0 |
| `redsun.jpg` | x86 | 64 | LE | Raw Binary | 0 |

No imports, no exports, no functions across either file.

### `RedSun.cpp` — Raw Header Bytes

```
00000000  0d 0a 0d 0a 2f 2f 20 49  74 20 67 65 74 73 20 66  |....// It gets f|
00000010  75 6e 6e 69 65 72 20 61  73 20 74 69 6d 65 20 70  |unnier as time p|
00000020  61 73 73 65 73 2e 2e 2e  0d 0a 0d 0a 23 64 65 66  |asses.......#def|
00000030  69 6e 65 20 5f 43 52 54  5f 53 45 43 55 52 45 5f  |ine _CRT_SECURE_|
00000040  4e 4f 5f 57 41 52 4e 49  4e 47 53 0d 0a 23 69 6e  |NO_WARNINGS..#in|
00000050  63 6c 75 64 65 20 3c 69  6f 73 74 72 65 61 6d 3e  |clude <iostream>|
00000060  0d 0a 23 69 6e 63 6c 75  64 65 20 3c 57 69 6e 64  |..#include <Wind|
00000070  6f 77 73 2e 68 3e 0d 0a  23 69 6e 63 6c 75 64 65  |ows.h>..#include|
```

`0d 0a` CRLF preamble confirms Windows UTF-8 text format. No binary magic bytes present.

**find-bytes — all searched patterns: 0 matches**

Source string literals appear as ASCII source-code characters, not as packed raw bytes. The sequence `L"\\??\pipe\REDSUN"` encodes in the file as `4c 22 5c 5c 3f 3f 5c 70 69 70 65 5c 52 45 44 53 55 4e 22` — never as the raw bytes `52 45 44 53 55 4e`. This is a structural property of source files vs. compiled binaries.

### `redsun.jpg` — JPEG Structure

**Header (first 64 bytes):**
```
00000000  ff d8 ff db 00 43 00 03  02 02 03 02 02 03 03 03  |.....C..........|
00000010  03 04 03 03 04 05 08 05  05 04 04 05 0a 07 07 06  |................|
```
- `ff d8` — SOI (Start of Image)
- `ff db 00 43` — DQT (Quantization Table), length 67 bytes

**Tail (last 32 bytes, at `0x100b6`):**
```
000100c6  cf cd a7 50 31 45 14 57  44 b4 7a 1c f7 3f ff d9  |...P1E.WD.z..?.|
```
- `ff d9` at `0x100d4` — EOI (End of Image): clean JPEG termination, no appended data

**Polyglot / secondary format checks:** ZIP magic (`50 4b 03 04`), PE magic (`4d 5a`), and `REDSUN` ASCII all absent. The file is a clean, standard JPEG.

---

## Technical Exploit Mechanism

### LPE Attack Chain

The exploit uses a **six-stage** race condition to achieve a write into `C:\Windows\System32` via a privileged service:

```
Stage 1: Setup
  - Create temp directory %TEMP%\RS-<random>
  - Register Cloud Files sync root (CfRegisterSyncRoot, provider: "SERIOUSLYMSFT")
  - Connect sync root callback (CfConnectSyncRoot)

Stage 2: OPLOCK Setup
  - Create placeholder file in sync root: TieringEngineService.exe
  - Request batch OPLOCK on the placeholder (FSCTL_REQUEST_BATCH_OPLOCK)

Stage 3: Trigger AV Scan
  - CfCreatePlaceholders — OneDrive-style placeholder creation triggers
    real-time AV scanner to open and inspect the new "cloud file"
  - AV scanner acquires handle, blocks on OPLOCK (OPLOCK held by exploit)

Stage 4: Reparse Point Swap
  - While AV scanner is blocked on OPLOCK:
    - MoveFileEx renames temp dir aside
    - CreateDirectory creates new temp dir with same name
    - FSCTL_SET_REPARSE_POINT sets reparse junction:
      temp\RS-<x>  →  \\??\C:\Windows\System32

Stage 5: OPLOCK Release + Race
  - Exploit releases OPLOCK
  - AV scanner continues, now walking the reparse junction into System32
  - NtSetInformationFile(class 10 = FileRenameInformation): renames
    "TieringEngineService.exe" inside what it thinks is the temp dir,
    but is now System32 — overwriting the real binary

Stage 6: Privilege Execution
  - CoCreateInstance({50d185b9...}, CLSCTX_LOCAL_SERVER) activates
    Storage Spaces Tier Management via COM
  - Replaced TieringEngineService.exe runs as SYSTEM
  - CreateProcessAsUser(hnewtoken, conhost.exe) spawns shell
  - "The red sun shall prevail."
```

### Key Technical Components

**Cloud Files API (CfAPI)**

The `cfapi.h` / `CldApi.lib` Cloud Files API is a documented but rarely-exploited Windows subsystem used by OneDrive and similar cloud storage providers to create virtual "placeholder" files that appear in the filesystem but are not yet fully downloaded. When a new placeholder is created, the system triggers callbacks including real-time scanning by security products registered for filesystem events.

The exploit registers a sync root with the name `SERIOUSLYMSFT` (a comment in the source reads: *"let's see how long you can play this game, I'm willing to go as far as you want"*) and creates a single placeholder named `TieringEngineService.exe`. The placeholder name was chosen to match the target binary.

**Opportunistic Lock (OPLOCK)**

`FSCTL_REQUEST_BATCH_OPLOCK` (Batch Oplock) causes the kernel to notify the lock holder when any other process tries to open the file. The AV scanner's attempt to open the placeholder for scanning triggers the OPLOCK notification — but the exploit holds the oplock, so the scanner blocks in the kernel until the exploit releases it. This gives the exploit a precise synchronization point: the scanner is guaranteed to be mid-open when the reparse point swap happens.

**NTFS Reparse Point Junction**

After the OPLOCK notification fires (confirming the scanner is blocked), the exploit:
1. Renames the temp directory away (`MoveFileEx`)
2. Creates a new directory at the same path
3. Sets `IO_REPARSE_TAG_MOUNT_POINT` (junction) pointing to `\\??\C:\Windows\System32`

When the OPLOCK is released and the scanner resumes opening `%TEMP%\RS-<x>\TieringEngineService.exe`, the kernel resolves the junction and the path becomes `C:\Windows\System32\TieringEngineService.exe`.

**NtSetInformationFile — Two Uses**

- **Class 10 (`FileRenameInformation`):** Used to rename `TieringEngineService.exe` within what is now System32 (via reparse point). The scanner service, running as SYSTEM/LocalSystem, performs this rename on behalf of the exploit.
- **Class 64 (`FileDispositionInformationEx`):** Used for controlled file deletion as part of cleanup.

**VSS Monitoring Thread**

`ShadowCopyFinderThread` runs in parallel, opening the `\Device` object namespace via `NtOpenDirectoryObject` and polling for new `HarddiskVolumeShadowCopy` entries via `NtQueryDirectoryObject`. The VSS monitor appears to be a fallback or secondary trigger mechanism — if a VSS snapshot is created during exploit execution, it creates an additional attack window through the shadow copy device path.

**COM Activation**

`CoCreateInstance` with GUID `{50d185b9-fff3-4656-92c7-e4018da4361d}` and `CLSCTX_LOCAL_SERVER` activates the replaced binary as the Storage Spaces Tier Management Engine COM server. This causes Windows' COM infrastructure to launch `TieringEngineService.exe` (now attacker-controlled) in its expected privileged context.

**EICAR String Obfuscation**

The EICAR test string is stored reversed in the source:
```
char eicar[] = "*H+H$!ELIF-TSET-SURIVITNA-DRADNATS-RACIE$}7)CC7)^P(45XZP\4[PA@%P!O5X";
```
When reversed, this decodes to the standard EICAR test string. It is written to the placeholder file to ensure real-time AV scanners detect and attempt to remediate it — this is what triggers the callback that the OPLOCK races. Without an AV scanner responding to this string, the exploit would not fire.

**Named Pipe IPC**

`\\??\pipe\REDSUN` is used for synchronization between the main thread and worker threads. The server side creates with `CreateNamedPipe(PIPE_ACCESS_DUPLEX | FILE_FLAG_FIRST_PIPE_INSTANCE)`; the client side opens via `CreateFile`.

---

## Key Findings

| # | Finding | Severity | Detail |
|---|---------|----------|--------|
| 1 | **LPE via OPLOCK + CfAPI + reparse point race** | Critical | Three-way race writes attacker-controlled content to `C:\Windows\System32\TieringEngineService.exe` via a privileged AV scanner callback |
| 2 | **AV scanner is the attack vector** | Critical | The exploit *requires* AV real-time scanning to be active. Disabling AV does not protect — it prevents the exploit from firing at all. The AV is weaponized as a privilege escalation carrier. |
| 3 | **COM activation provides SYSTEM execution** | Critical | GUID `{50d185b9-fff3-4656-92c7-e4018da4361d}` (Storage Spaces) launches the replaced binary as a privileged COM server |
| 4 | **EICAR reversed to evade static AV on source** | High | The test string is stored reversed to prevent AV from flagging the exploit source file itself; this confirms intent to evade detection tooling |
| 5 | **VSS monitoring as secondary trigger** | Medium | `ShadowCopyFinderThread` watches for Volume Shadow Copy creation, providing an additional race window |
| 6 | **CfAPI abuse via undocumented provider** | Medium | `SERIOUSLYMSFT` sync root registration abuses the Cloud Files API in a way not intended for non-cloud-storage use |
| 7 | **Runtime NTDLL function resolution** | Medium | `NtSetInformationFile`, `NtQueryDirectoryObject`, `NtOpenDirectoryObject` resolved via `GetProcAddress` to avoid static import table inspection |
| 8 | **No compiled binary provided** | Informational | Only source code provided; exploit must be compiled before it can be run. No pre-compiled `.exe` or shellcode present. |
| 9 | **JPEG is clean** | Informational | `redsun.jpg` is a standard baseline JPEG with no embedded content, polyglot format, or secondary payload |

---

## Defensive Recommendations

1. **Monitor for CfAPI sync root registration** by non-cloud-storage processes. `CfRegisterSyncRoot` from unusual parent processes (non-OneDrive, non-Teams, non-SharePoint) should alert. ETW provider `Microsoft-Windows-CloudFiles` emits events for sync root registration.

2. **Monitor for OPLOCK + reparse point combinations.** An OPLOCK batch request (`FSCTL_REQUEST_BATCH_OPLOCK`) followed within seconds by `FSCTL_SET_REPARSE_POINT` (junction creation) in the same directory path is a high-confidence indicator of this attack class.

3. **Alert on `TieringEngineService.exe` file modification.** The binary at `C:\Windows\System32\TieringEngineService.exe` should never be written by user-mode processes. EDR rules or Windows Defender ATP custom detections should fire on file-write events targeting this path.

4. **Restrict COM activation of Storage Spaces GUID.** AppLocker or WDAC policies can restrict which processes may activate COM servers by GUID. The GUID `{50d185b9-fff3-4656-92c7-e4018da4361d}` should be restricted to SYSTEM or service-level callers only.

5. **Apply relevant Microsoft patches.** This LPE class (CfAPI race + reparse) has been the subject of multiple CVEs in the 2023–2024 timeframe. Ensure the system is fully patched and `StorageTiers`-related security updates are applied.

6. **AV scanner hardening.** AV callbacks that perform file rename/delete operations while holding elevated privileges should verify the full resolved path (including reparse targets) before committing the operation. Checking for reparse points along the path before rename would break this race.

7. **Named pipe monitoring.** Creation of `\\??\pipe\REDSUN` by a non-system process is a direct indicator of this specific exploit. Named pipe creation events (ETW `Microsoft-Windows-Kernel-File`) can alert on this exact name.

---

## Evidence Files

| File | Description |
|------|-------------|
| `ghidrasql_analysis.txt` | ghidrasql full analysis (memory blocks, functions, strings, program options for both files) |
| `ghidra_rpc_analysis.txt` | ghidra-rpc analysis (metadata, memory map, strings, imports, exports, read-bytes, find-bytes for both files) |
| `report_ghidrasql.md` | ghidrasql per-tool report |
| `report_ghidra_rpc.md` | ghidra-rpc per-tool report |
| `<project_dir>/redsun_sql.gpr` | Persisted Ghidra project (both programs) |
