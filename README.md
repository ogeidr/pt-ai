# pt-ai

A minimalistic, ephemeral, agentic framework for penetration testing.

## Overview

`pt-ai` explores a lightweight approach to AI-assisted offensive security, built around agents whose state is scoped to an individual engagement and discarded when the engagement ends. Agents may be narrow and single-purpose or multi-capability and interconnected, composed to match the scope and requirements of the engagement at hand. The project favors minimal surface area, minimal dependencies, and composability over persistent, monolithic agent systems.

## Design Principles


- **Minimalistic.** Few moving parts. No orchestration layer, no persistent databases, no heavy framework.
- **Ephemeral.** State is bounded by the engagement. Nothing carries over once the engagement concludes.
- **Composable.** Agents can be simple and narrowly-scoped, or combined and interconnected into multi-capability workflows as the engagement requires.
- **Authorization-bound.** Every agent operates within explicit scope and authorization boundaries.
- **Auditable.** Every action is intended to be observable and reproducible.

## Deployment options

Four ways to run pt-ai — pick the one that fits your setup:

| Option | AI model | Tools | Best for |
|---|---|---|---|
| [Docker + Claude Code](docker/README.md) | Claude (Anthropic API / OAuth) | Remote Kali host via MCP | Existing Kali server, cloud API |
| [Docker + LM Studio](docker/README-lmstudio.md) | Local model via LM Studio | Remote Kali host via MCP | Air-gapped / no API key, Mac host |
| [Docker + Ollama](docker/README-ollama.md) | Local model via Ollama | Remote Kali host via MCP | Air-gapped / no API key, Linux host |
| [Vagrant Kali VM](vagrant/README.md) | Claude (OAuth) | Local — tools run inside the VM | Self-contained, no remote host needed |

### Docker options (Claude / LM Studio / Ollama)

All three Docker options share the same architecture: an ephemeral container handles AI reasoning, and a separate Linux host running `kali-server-mcp` provides the Kali toolset over an MCP bridge. The container is destroyed on exit; only the engagement evidence directory survives.

- **Claude Code** (`docker/ptai`) — uses Claude via Anthropic API key or browser OAuth.
- **LM Studio** (`docker/ptai-lmstudio`) — uses opencode with any OpenAI-compatible model served by LM Studio on the host. No API key needed.
- **Ollama** (`docker/ptai-ollama`) — same as LM Studio but with Ollama as the local model server.

### Vagrant Kali VM

A fully-provisioned Kali Linux VM (`vagrant/kali`) where Claude Code runs directly inside the VM alongside all the tools — no MCP bridge or remote host required. Includes ghidrasql for binary analysis. Snapshot/restore provides clean state between engagements.

Recommended for Apple Silicon Macs using VMware Fusion.

## Status

Early-stage research project. Interfaces, agent definitions, and execution model are subject to change.

## Authorized Use Only

This project is intended exclusively for authorized security testing. Users are responsible for obtaining written authorization before engaging any target system.

## License

MIT — see `LICENSE`.

## Credits

Forked from [`0xSteph/pentest-ai`](https://github.com/0xSteph/pentest-ai) by [0xSteph](https://github.com/0xSteph); several folders and files originate from that project. Upstream MIT license preserved in `ORIGINAL.LICENSE`.



