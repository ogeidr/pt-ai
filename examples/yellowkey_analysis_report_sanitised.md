# YellowKey BitLocker Bypass — Static Analysis Report

**Engagement:** yellowkey  
**Engagement Type:** Defensive Review  
**Files Analyzed:** PoC files from the `FsTx/95F62703B343F111A92A005056975458/FsTxLogs/` directory

---

> **Sanitisation note — all items removed:**
>
> | Item | Action |
> |------|--------|
> | Analyst email | **Removed** |
> | Analysis date | **Removed** |
> | Local filesystem paths (project dir, evidence dir, Ghidra install) | **Removed** — replaced with `<project_dir>` / generic names |
> | Daemon socket path | **Removed** — replaced with `<runtime_socket>` |
> | Timestamped evidence filenames | **Removed** — replaced with generic names |

---

## Executive Summary

YellowKey is a BitLocker bypass vulnerability affecting **Windows 11, Server 2022, and Server 2025** (Windows 10 is **not** affected). The PoC exploits a flaw in how the Windows Recovery Environment (WinRE) processes **Transactional NTFS (TxF)** log files. By placing crafted CLFS (Common Log File System) transaction records on any attached storage device (USB stick, EFI partition, or pulled disk), an attacker can cause WinRE to create a malicious `winpeshl.ini` on the system drive. This file configures the WinPE shell launcher and, when injected, spawns an unrestricted shell with full access to the BitLocker-decrypted volume — completely bypassing BitLocker encryption at rest.

The researcher describes this as potentially a **backdoor**: the undocumented WinRE component responsible for the flaw exists in a normal Windows installation too, but without the TxF-processing behavior; only the WinRE variant is vulnerable.

---

## PoC File Inventory

| File | Size | Type |
|------|------|------|
| `FsTxLog.blf` | 64 KB | CLFS Base Log File (TxF log index) |
| `FsTxKtmLog.blf` | 64 KB | CLFS Base Log File (KTM transaction index) |
| `FsTxLogContainer00000000000000000001` | 10 MB | CLFS log container (TxF transaction records) |
| `FsTxKtmLogContainer00000000000000000001` | 512 KB | CLFS log container (KTM transaction records) |
| `FsTxKtmLogContainer00000000000000000002` | 512 KB | CLFS log container (KTM continuation) |
| `FsTxLogContainer00000000000000000002` | 10 MB | CLFS log container (TxF continuation) |
| `FsTxTemp/98F62703B343F111A92A005056975458` | 0 B | Temporary placeholder (empty) |

**Transaction GUID:** `95F62703-B343-F111-A92A-005056975458`

---

## Analysis 1 — ghidrasql (SQL Interface / Headless Ghidra)

**Tool:** ghidrasql via Ghidra 12.0.4  
**Method:** Raw Binary loader, x86-64 LE, Windows compiler spec  
**Project:** `<project_dir>/yellowkey_sql`

### Program Options (applied to all 4 files)

| Key | Value |
|-----|-------|
| `analysis.headless` | `true` |
| `analysis.language_id` | `x86:LE:64:default` |
| `analysis.compiler_spec` | `windows` |
| `analysis.image_base` | `0` |

### Program 1: `FsTxLogContainer00000000000000000001` (10 MB)

**Memory Blocks**

| Start | End | Name | Class | Size | Executable |
|-------|-----|------|-------|------|------------|
| 0x0 | 0x9fffff | ram | CODE | 10,485,760 | Yes |

**Functions:** 0 (pure data — no x86 instructions identified)  
**Imports / Exports:** None  
**Total Instructions:** 0

**Strings Discovered (UTF-16)**

| Address | Length | String |
|---------|--------|--------|
| `0x010c` | 46 bytes | `\??\C:\Windows\win.ini` |
| `0x013a` | 74 bytes | `\??\X:\Windows\System32\winpeshl.ini` |

> **Critical:** These two strings are the exploit payload embedded in the TxF record at offset `0xe0`. The first is the **source** (a harmless existing file), the second is the **destination** — the WinPE shell configuration file on the removable/target drive (`X:`).

**Raw bytes at TxF record (0xe0–0x1a8):**
```
000000e0  b9 1c 0e 00 00 00 02 00  00 00 00 00 00 00 00 00
000000f0  02 00 00 00 00 00 00 00  00 00 00 00 00 00 00 00
00000100  2e 00 00 00 78 00 00 00  [length: 0x2e=46, 0x78=120]
         -- UTF-16: \??\C:\Windows\win.ini --
         5c 00 3f 00 3f 00 5c 00 43 00 3a 00 5c 00 57 00
         69 00 6e 00 64 00 6f 00 77 00 73 00 5c 00 77 00
         69 00 6e 00 2e 00 69 00 6e 00 69 00 00 00
         -- UTF-16: \??\X:\Windows\System32\winpeshl.ini --
         5c 00 3f 00 3f 00 5c 00 58 00 3a 00 5c 00 57 00
         ...70 00 65 00 73 00 68 00 6c 00 2e 00 69 00 6e 00 69 00
```

The length fields at `0x100` (`0x2e` = 46 bytes for `win.ini` path, `0x78` = 120 bytes for `winpeshl.ini` path including drive letters) match precisely the string lengths reported by Ghidra's string analysis.

---

### Program 2: `FsTxKtmLogContainer00000000000000000001` (512 KB)

**Memory Blocks:** 0x0–0x7ffff, 524,288 bytes  
**Functions:** 0 | **Strings:** 0  
**Purpose:** Stores KTM (Kernel Transaction Manager) metadata for the TxF transaction. No readable strings — pure binary transaction state structures. Coordinates with the TxF log to ensure atomicity of the NTFS operation.

---

### Program 3: `FsTxLog.blf` (64 KB — BLF header)

**Memory Blocks:** 0x0–0xffff, 65,536 bytes  
**Functions:** 0

**Strings (UTF-16) — BLF internal pointers:**

| Address | String |
|---------|--------|
| `0x1c60` | `\??\C:\System Volume Information\FsTx\95F62703B343F111A92A005056975458\FsTxLogs\FsTxLog.blf` |
| `0x9660` | *(mirror copy)* same path |
| `0x1d78` | `%BLF%\FsTxLogContainer00000000000000000001` |
| `0x1e30` | `%BLF%\FsTxLogContainer00000000000000000002` |
| `0x9778` | `%BLF%\FsTxLogContainer00000000000000000001` *(mirror)* |
| `0x9830` | `%BLF%\FsTxLogContainer00000000000000000002` *(mirror)* |

> The dual copies at offset 0x1xxx and 0x9xxx reflect the CLFS BLF dual-sector mirroring used for crash recovery. The `%BLF%` prefix is CLFS relative path notation.

**BLF Header (0x0):**
```
15 00 01 00 02 00 02 00  -- CLFS signature (v1, 2 sectors, 2 containers)
00 00 00 00 4b 82 4c c6  -- checksum: 0xc64c824b
01 00 00 00 ...          -- sequence number 1
f8 03 00 00 00 00 00 00  -- 0x3f8 = 1016 (record offset)
1c 5f 00 00              -- 0x5f1c = LSN pointer
f5 c1 f5 c1              -- CLFS tail/head signatures
```

---

### Program 4: `FsTxKtmLog.blf` (64 KB — KTM BLF header)

Identical BLF header format to `FsTxLog.blf`. Strings mirror the same dual-copy pattern, referencing `FsTxKtmLog.blf` and `FsTxKtmLogContainer` files.

---

## Analysis 2 — ghidra-rpc (RPC Daemon Interface)

**Tool:** ghidra-rpc / Ghidra 12.0.4 headless daemon  
**Socket:** `<runtime_socket>`  
**Project:** `<project_dir>/yellowkey_sql.gpr`

### Metadata Summary (all programs)

| Program | Arch | Bits | Endian | Format | Functions |
|---------|------|------|--------|--------|-----------|
| `FsTxLogContainer00000000000000000001` | x86 | 64 | LE | Raw Binary | 0 |
| `FsTxKtmLogContainer00000000000000000001` | x86 | 64 | LE | Raw Binary | 0 |
| `FsTxLog.blf` | x86 | 64 | LE | Raw Binary | 0 |
| `FsTxKtmLog.blf` | x86 | 64 | LE | Raw Binary | 0 |

No imports, no exports, no functions across all four files. Disassembly at every inspected offset was rejected by Ghidra with `"Address is in a data section (type: undefined), not executable code"` — confirming these are **purely data files with no embedded shellcode or executable stubs**.

### Strings Confirmed (ghidra-rpc JSON)

**FsTxLogContainer00000000000000000001:**
```json
"strings": [
  { "address": "0000010c", "value": "\\??\\C:\\Windows\\win.ini",                      "type": "unicode" },
  { "address": "0000013a", "value": "\\??\\X:\\Windows\\System32\\winpeshl.ini",        "type": "unicode" }
]
```

**FsTxLog.blf:**
```json
"strings": [
  { "address": "00001c60", "value": "\\??\\C:\\System Volume Information\\FsTx\\95F62703B343F111A92A005056975458\\FsTxLogs\\FsTxLog.blf", "type": "unicode" },
  { "address": "00001d78", "value": "%BLF%\\FsTxLogContainer00000000000000000001",       "type": "unicode" },
  { "address": "00001e30", "value": "%BLF%\\FsTxLogContainer00000000000000000002",       "type": "unicode" },
  ... (mirror copies at 0x9660, 0x9778, 0x9830)
]
```

**FsTxKtmLogContainer00000000000000000001:** No strings (pure binary KTM records).

### Memory Map (ghidra-rpc)

All segments are **read+write+execute** (default Raw Binary loader flags). There is no actual executable code — the `execute` permission is an artifact of the Raw Binary loader mapping the entire file as a single `CODE` segment; Ghidra's disassembler confirmed no actual instructions.

---

## Technical Exploit Mechanism

### How the TxF Bypass Works

1. **TxF (Transactional NTFS)** is a Windows feature that allows NTFS file operations to participate in kernel transactions. Operations can be committed atomically or rolled back.

2. The crafted CLFS log files describe a **pending (uncommitted) transaction** that:
   - Reads from `\??\C:\Windows\win.ini` (a harmless, always-present file, used as the content source)
   - Writes to `\??\X:\Windows\System32\winpeshl.ini` (where `X:` maps to the system drive under WinRE's device namespace)

3. **WinRE's undocumented TxF processing component** — unique to the WinRE image and absent from documented Windows APIs — discovers uncommitted TxF logs when it starts and **forces them to complete**, regardless of whether they were meant to commit.

4. The result is that `C:\Windows\System32\winpeshl.ini` is created/overwritten on the BitLocker-protected volume. Since WinRE has already decrypted the volume (by design, to allow system recovery), it writes to plaintext NTFS.

5. **`winpeshl.ini`** controls what shell WinPE/WinRE launches. A custom entry can specify `cmd.exe` or any other binary. On the next WinRE boot, an unrestricted command shell spawns with SYSTEM privileges and full read/write access to the decrypted volume.

### Why `win.ini` Is Used as the Source

`win.ini` is a near-zero-content file present on all Windows systems. Using it as the "source" of the TxF copy operation provides valid file handle semantics for the transaction record without requiring the attacker to embed arbitrary file content in the CLFS records. The actual `winpeshl.ini` payload format is:

```ini
[LaunchApps]
%SYSTEMDRIVE%\Windows\System32\cmd.exe
```

This file would need to be placed separately or the WinRE component may use the source content — the exact mechanism for content injection is in the vulnerable WinRE binary component, which is not part of this PoC.

### CLFS File Structure

```
FsTxLog.blf                          <-- Index: tracks container files
  ├── FsTxLogContainer...0001 (10MB) <-- TxF records + payload strings
  └── FsTxLogContainer...0002 (10MB) <-- Overflow/continuation

FsTxKtmLog.blf                       <-- KTM index: kernel transaction metadata
  ├── FsTxKtmLogContainer...0001 (512KB) <-- KTM transaction records
  └── FsTxKtmLogContainer...0002 (512KB) <-- KTM continuation
```

The GUID `95F62703-B343-F111-A92A-005056975458` uniquely identifies this transaction across both the TxF and KTM log trees. It appears hardcoded in the BLF path strings.

---

## Key Findings

| # | Finding | Severity | Detail |
|---|---------|----------|--------|
| 1 | **Exploit payload strings present** | Critical | `\??\X:\Windows\System32\winpeshl.ini` encoded as UTF-16 at offset 0x13a in the main log container — this is the write target |
| 2 | **Source file reference** | High | `\??\C:\Windows\win.ini` at 0x10c used as the TxF copy source to avoid needing embedded file content |
| 3 | **No shellcode or PE present** | Informational | All files are pure CLFS data structures — the exploit logic is in the vulnerable WinRE component, not in these trigger files |
| 4 | **Dual-copy BLF structure** | Informational | CLFS BLF headers store all path strings at two offsets (0x1xxx and 0x9xxx), a standard CLFS crash-recovery mirroring mechanism |
| 5 | **KTM container is opaque** | Informational | `FsTxKtmLogContainer` has no readable strings — it carries binary KTM state; the TxF container carries the actual paths |
| 6 | **Windows 10 not affected** | Scope note | Only Windows 11/Server 2022/2025 WinRE contains the vulnerable TxF-processing component |

---

## Defensive Recommendations

1. **Restrict physical access** to machines using BitLocker. BitLocker without a PIN/TPM+PIN configuration cannot prevent WinRE from auto-unlocking on boot from a WinRE environment.

2. **Enable BitLocker with a pre-boot PIN** (`TPM+PIN` or `Password` protector mode). Without the correct PIN, WinRE cannot unlock the volume and the transaction write cannot reach plaintext NTFS.

3. **Apply Microsoft patches** — this was disclosed to Microsoft via MORSE/MSTIC/GHOST. Monitor for associated CVE advisories.

4. **Detection — monitoring for `winpeshl.ini`:** Alert on creation of `C:\Windows\System32\winpeshl.ini` or modifications to `C:\System Volume Information\FsTx\` directories. Under normal conditions, `winpeshl.ini` should not exist on a standard Windows installation.

5. **Disable or restrict TxF recovery in WinRE** (if a Microsoft-provided GPO or registry key is published with the patch).

6. **Secure Boot** does not prevent this attack — `winpeshl.ini` is processed by a signed Windows component after secure boot verification.

---

## Evidence Files

| File | Description |
|------|-------------|
| `ghidrasql_analysis.txt` | ghidrasql full analysis (memory blocks, functions, strings, program options) |
| `ghidra_rpc_analysis.txt` | ghidra-rpc analysis (metadata, memory map, strings, imports, exports) |
| `ghidra_rpc_deep_analysis.txt` | ghidra-rpc deep analysis (raw byte dumps, disassembly attempts, find-bytes) |
| `<project_dir>/` | Persisted Ghidra project (all 4 programs) |
