# pt-ai

A minimalistic, ephemeral, agentic framework for penetration testing.

## Design Principles

- **Minimalistic.** Few moving parts. No orchestration layer, no persistent databases, no heavy framework.
- **Ephemeral.** State is bounded by the engagement. Nothing carries over once the engagement concludes.
- **Composable.** Agents can be simple and narrowly-scoped, or combined and interconnected into multi-capability workflows as the engagement requires.
- **Authorization-bound.** Every agent operates within explicit scope and authorization boundaries.
- **Auditable.** Every action is intended to be observable and reproducible.

## Deployment

pt-ai runs in a fully-provisioned [Kali Linux VM](vagrant/README.md) managed by Vagrant. Claude Code (and opencode) run directly inside the VM alongside all the tools — no MCP bridge or remote host required. Snapshot/restore provides clean state between engagements.

```sh
cd vagrant && ./kali up
```

See [vagrant/README.md](vagrant/README.md) for setup and daily workflow.

## Status

Early-stage research project. Interfaces, agent definitions, and execution model are subject to change.

## Authorized Use Only

This project is intended exclusively for authorized security testing. Users are responsible for obtaining written authorization before engaging any target system.

## License

MIT — see `LICENSE`.

## Credits

Forked from [`0xSteph/pentest-ai`](https://github.com/0xSteph/pentest-ai) by [0xSteph](https://github.com/0xSteph); several folders and files originated from that project. Upstream MIT license preserved in `ORIGINAL.LICENSE`.



