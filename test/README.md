# pt-ai plugin — test suite

Automated + semi-automated tests for the **plugin** install path (install Option
B). Split into two tiers by what each test actually needs. **Neither tier runs on
your host OS**, and nothing installs into your host `~/.claude`.

> This is the plugin-side counterpart to the VM-side harness in
> [`../vagrant/test/`](../vagrant/test/) (`provision-test.sh`, `tool-audit.sh`).

## Tier 1 — mechanical (VM-free, automated in CI)

Pure shell + `jq`. No Claude Code, no auth, no VM. This is the everyday regression
signal and runs in GitHub Actions (`.github/workflows/plugin-suite.yml`) on every
push/PR that touches the plugin sources.

```sh
bash test/plugin-suite.sh      # runs all three; writes test/results/summary.txt
```

| Check | Script | Asserts |
|---|---|---|
| parity | `plugin-parity.sh` | committed `plugin/` == a fresh `tools/build-plugin.sh` (also exercises the build, and is the definitive **GNU-sed portability** check in CI) |
| hooks | `plugin-hooks.sh` | `pt-ai-guard.sh` denies/allows correctly (credential exfil, catastrophic `rm`, OPSEC ceiling, Read-tool file_path) |
| validate | `plugin-validate.sh` | manifests are valid JSON; agent/skill frontmatter; hooks executable; guard byte-identical to source; component counts derived from source |

`plugin-suite.sh` preflights for `jq`/`python3` (without a JSON parser the guard
fails closed and the hook allow-cases would fail for the wrong reason) and exits
non-zero if any check fails, so it is CI-gateable. `test/results/` is gitignored.

## Tier 2 — functional (in the Vagrant VM, on demand)

Installing and *driving* the plugin needs an authenticated Claude Code and the
toolchain — only the VM has both. `plugin-functional.sh` **refuses to run off
Linux** and installs into a throwaway `CLAUDE_CONFIG_DIR` seeded with only the
OAuth credential (`~/.claude/.credentials.json`), so it is authed yet isolated
from the VM's own provisioned skills.

Run it **inside the guest**, from a checkout of this repo (`git clone` or
`vagrant upload` — no Vagrantfile change needed):

```sh
# in the VM:
bash test/plugin-functional.sh
```

It scripts: local-marketplace add → install → assert the plugin + components are
registered (`claude plugin list --json` and the `enabledPlugins` settings key) →
a headless `claude -p` smoke that the guard blocks a credential read. The full
interactive engagement flow (`/scope-declare → /engagement → /engage-recon`,
`./engagements/` creation, live OPSEC deny) is a **manual checklist** printed at
the end — it needs a TTY and is not faked.

> The `claude plugin …` / `claude -p` flags are sourced from the Claude Code docs;
> verify against the installed version on first run (`claude plugin --help`).

## What runs where

| | Host (macOS) | GitHub CI | Vagrant VM |
|---|---|---|---|
| Tier 1 (mechanical) | — (off-limits) | ✅ every push/PR | ✅ possible |
| Tier 2 (functional) | ✋ refuses | — (no authed Claude) | ✅ on demand |
