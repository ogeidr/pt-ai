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

## Relationship to the Original Project

This repository was originally forked from [`0xSteph/pentest-ai`](https://github.com/0xSteph/pentest-ai), created by [0xSteph](https://github.com/0xSteph). The original project provides a comprehensive suite of 28 Claude Code subagents covering the full penetration testing lifecycle, and full credit for that body of work belongs to the original author.

`pt-ai` diverges in philosophy. Rather than a persistent, pre-defined agent suite, it pursues a minimalistic, per-engagement model in which agents are assembled, connected, and retired according to the shape of each engagement.

## Status

Early-stage research project. Interfaces, agent definitions, and execution model are subject to change.

## Authorized Use Only

This project is intended exclusively for authorized security testing. Users are responsible for obtaining written authorization before engaging any target system.

## License

MIT — see `LICENSE`.
