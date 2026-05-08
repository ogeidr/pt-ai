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

## Status

Early-stage research project. Interfaces, agent definitions, and execution model are subject to change.

## Authorized Use Only

This project is intended exclusively for authorized security testing. Users are responsible for obtaining written authorization before engaging any target system.

## License

MIT — see `LICENSE`.

## Credits

Forked from [`0xSteph/pt-ai`](https://github.com/0xSteph/pt-ai) by [0xSteph](https://github.com/0xSteph); several folders and files originate from that project. Upstream MIT license preserved in `ORIGINAL.LICENSE`.



