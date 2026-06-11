// pt-ai-guard.js — opencode tool.execute.before plugin (runtime safety gate).
//
// Mirrors the Claude Code PreToolUse guard so the opencode front-end gets the
// SAME runtime gate — closing the "Claude-front-end only" gap for PENDING
// #1/#2/#5/#14 WITHOUT a host egress allowlist:
//   Stage 1 — operator LLM-credential exfil
//   Stage 2 — catastrophic recursive delete of a protected path (bash only)
//   Stage 3 — OPSEC ceiling: refuse commands noisier than the ceiling (bash only)
//
// It does NOT reimplement those rules: it feeds the proposed bash command to the
// SAME pt-ai-guard.sh script (installed alongside, by 05-opencode.sh) as the
// minimal Claude-event JSON the script expects, and THROWS — which opencode
// treats as a block — when the script returns a `deny` decision. One source of
// truth for the rules; no drifting JS copy.
//
// Fails CLOSED: any failure to run the guard, or an unreadable result, throws.
// Gates BOTH `bash` (the command) and `read` (the file path) through the same
// script — opencode's declarative `permission.read` globs are an unreliable
// hard-deny (it expands `~` in the pattern but not in the model-supplied path,
// so a literal `~/.anthropic_key` read falls through to "ask"), so the plugin is
// the dependable read block; the globs in opencode.json stay as a backstop.

import { spawnSync } from "node:child_process"

const GUARD = `${process.env.HOME}/.config/opencode/pt-ai-guard.sh`

export const PtAiGuard = async () => ({
  "tool.execute.before": async (input, output) => {
    // bash → the command string; read → the file path. The guard's Stage-1
    // credential matcher works on either; Stage-2 (recursive delete) only ever
    // matches a command, never a bare read path.
    let probe
    if (input?.tool === "bash") probe = output?.args?.command
    else if (input?.tool === "read") probe = output?.args?.filePath
    else return
    if (!probe) return

    let res
    try {
      res = spawnSync(GUARD, [input.tool], {
        input: JSON.stringify({ tool_input: { command: probe } }),
        encoding: "utf8",
      })
    } catch (e) {
      throw new Error(`pt-ai guard failed to run (${e}); blocking as a precaution.`)
    }
    if (res.error || typeof res.stdout !== "string") {
      throw new Error("pt-ai guard did not run; blocking as a precaution.")
    }
    if (res.stdout.includes('"permissionDecision":"deny"')) {
      let reason = "Blocked by pt-ai guard."
      try {
        reason = JSON.parse(res.stdout).hookSpecificOutput.permissionDecisionReason
      } catch { /* fall back to the generic reason */ }
      throw new Error(reason)
    }
  },
})
