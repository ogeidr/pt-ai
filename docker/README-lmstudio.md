# pt-ai LM Studio Docker

Ephemeral Ubuntu container running opencode and a vendored stdio MCP bridge.
opencode speaks OpenAI-compatible APIs natively, so LM Studio on the host is
reached directly — no translation proxy needed. The Kali toolset and MCP API
server live on a separate Linux host — identical to the standard pt-ai setup.

## Architecture

```
┌────────────────── client host (e.g. macOS) ──────────────────────┐    ┌──── Linux host ────┐
│                                                                  │    │                    │
│  LM Studio  ◄────────────────────────────────────────────────┐  │    │  kali-server-mcp   │
│  localhost:1234  (OpenAI-compatible API)                      │  │    │  bound 127.0.0.1   │
│                                                               │  │    │  :5000             │
│  ssh -L 5000:127.0.0.1:5000 user@<linux-host>  ──────────────┼──┼────►                   │
│                                                               │  │    │  nmap, gobuster,   │
│  ┌──── pt-ai-lmstudio container (ubuntu:24.04) ───────────┐  │  │    │  nikto, …          │
│  │                                                        │  │  │    └────────────────────┘
│  │  opencode ── OpenAI API ── HTTP ───────────────────────┼──┘  │
│  │               host.docker.internal:1234                │     │
│  │                                                        │     │
│  │  opencode ── stdio ──► client.py                       │     │
│  │                              │ (bridge)                │     │
│  │                              ▼                         │     │
│  │          HTTP → host.docker.internal:5000 ─────────────┼─────┘
│  └────────────────────────────────────────────────────────┘     │
└──────────────────────────────────────────────────────────────────┘
```

## Layout

```
docker/
├── Dockerfile.lmstudio     # ubuntu:24.04 + node 20 + opencode + mcp bridge
├── entrypoint-lmstudio.sh  # convert agents, generate opencode.json, probe services, exec opencode
├── ptai-lmstudio           # POSIX-sh host wrapper (build / run)
├── Dockerfile              # standard pt-ai image (Claude API)
├── entrypoint.sh
├── ptai
├── .dockerignore
└── README-lmstudio.md
```

## Prerequisites

- Docker (Engine on Linux, or Docker Desktop on macOS).
- LM Studio installed on the host, local server started, and a model loaded.
- A reachable Linux host running `kali-server-mcp` on `127.0.0.1:5000`.

## Build

```sh
docker/ptai-lmstudio build              # build the image
docker/ptai-lmstudio build --no-cache   # rebuild from scratch
```

Pin the MCP bridge to a specific commit or override the base tag:

```sh
MCP_BRIDGE_REF=<full-sha> docker/ptai-lmstudio build
UBUNTU_TAG=24.04          docker/ptai-lmstudio build
```

## Set up LM Studio

In LM Studio on the host:

1. Load the model you want to use.
2. Go to **Local Server** and click **Start Server** (default port `1234`).
3. Note the model identifier shown in the server tab — you will pass it as
   `PT_AI_LM_STUDIO_MODEL`.

No API key is required. LM Studio's local server accepts any value.

## Set up the remote MCP server

Identical to the standard setup. On the Linux host:

```sh
sudo apt install mcp-kali-server
kali-server-mcp --ip 127.0.0.1 --port 5000 &
```

The API must bind **only `127.0.0.1`**. Never expose it on the LAN.

## Run an engagement

Three pieces in place before `ptai-lmstudio run`:

1. **LM Studio server running** on the host with a model loaded.
2. **Remote MCP server running** on the Linux host (bound to `127.0.0.1:5000`).
3. **SSH tunnel up** in its own terminal, leave it running:
   ```sh
   ssh -L 5000:127.0.0.1:5000 user@<linux-host> -N
   ```

Then:

```sh
export PT_AI_LM_STUDIO_MODEL=<model-identifier>
export PT_AI_MCP_SERVER=http://host.docker.internal:5000
docker/ptai-lmstudio run <engagement-id>
```

This:

- Creates `engagements/<engagement-id>/` on the host (the only persistent surface).
- Bind-mounts `agents/` and converts them to opencode commands at startup.
- Generates `opencode.json` inside the container: registers the model under a custom `lmstudio` provider (required for opencode to discover it), points the provider at LM Studio, and wires in the MCP bridge.
- Probes both LM Studio and the remote MCP for readiness and warns if unreachable.
- Tears the container down on exit (`--rm`); only `engagements/<id>/` survives.

### Options

```sh
docker/ptai-lmstudio run my-eng --shell          # bash instead of opencode
docker/ptai-lmstudio run my-eng --listen 4444    # publish 4444/tcp for callbacks

# Override LM Studio URL if not on the default port
PT_AI_LM_STUDIO_URL=http://host.docker.internal:1234 docker/ptai-lmstudio run my-eng
```

### Invoking agents inside opencode

Agents are available as slash commands. Type `/` in opencode to see the full list:

```
/recon-advisor       /vuln-scanner        /web-hunter
/ad-attacker         /exploit-guide       /exploit-chainer
/attack-planner      /engagement-planner  /report-generator
...
```

## Networking

Same as the standard setup. The container reaches the host via
`host.docker.internal` (Docker Desktop) or `--add-host=...:host-gateway` on
native Linux Docker, which the wrapper sets unconditionally.

## Ephemerality

The container is destroyed on exit (`--rm`). Only `engagements/<engagement-id>/`
persists on the host. No credentials are kept — LM Studio needs no authentication.

## File ownership

Inside the container the process runs as `operator` (uid 1000). Same behaviour
as the standard image — see `docker/README.md` for details.

## Troubleshooting

| Symptom | Likely cause / fix |
|---|---|
| `pt-ai-lmstudio: PT_AI_LM_STUDIO_MODEL is required.` | Export `PT_AI_LM_STUDIO_MODEL` before running. |
| `pt-ai-lmstudio: PT_AI_MCP_SERVER is required.` | Export `PT_AI_MCP_SERVER=http://host.docker.internal:5000`. |
| `warning — LM Studio at … is not reachable` | LM Studio server not started, or model not loaded. |
| `warning — remote MCP at … is not reachable` | SSH tunnel down or `kali-server-mcp` not running. |
| No agents show up as `/` commands | Check `~/.config/opencode/commands/` inside the container (`--shell` mode). |
| Model not found / wrong model used | opencode requires models to be explicitly registered. The entrypoint does this automatically via `PT_AI_LM_STUDIO_MODEL`. Confirm the value matches the model identifier shown in LM Studio's server tab. |
| LLM responses are poor quality | Local models are less capable than Claude for tool use. Use a 70B+ model. |

## Authorized use only

Same constraint as the rest of the repo: this tooling is for authorized
penetration-testing engagements only. Every agent enforces scope/authorization
verification before producing target-specific guidance.
