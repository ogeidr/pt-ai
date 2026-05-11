# pt-ai Ollama Docker

Ephemeral Ubuntu container running opencode and a vendored stdio MCP bridge.
opencode speaks OpenAI-compatible APIs natively, so Ollama on the host is
reached directly — no translation proxy needed. The Kali toolset and MCP API
server live on a separate Linux host — identical to the standard pt-ai setup.

## Architecture

```
┌────────────────── client host (e.g. macOS) ──────────────────────┐    ┌──── Linux host ────┐
│                                                                  │    │                    │
│  Ollama  ◄───────────────────────────────────────────────────┐  │    │  kali-server-mcp   │
│  localhost:11434  (OpenAI-compatible API)                     │  │    │  bound 127.0.0.1   │
│                                                               │  │    │  :5000             │
│  ssh -L 5000:127.0.0.1:5000 user@<linux-host>  ──────────────┼──┼────►                   │
│                                                               │  │    │  nmap, gobuster,   │
│  ┌──── pt-ai-ollama container (ubuntu:24.04) ─────────────┐  │  │    │  nikto, …          │
│  │                                                        │  │  │    └────────────────────┘
│  │  opencode ── OpenAI API ── HTTP ───────────────────────┼──┘  │
│  │               host.docker.internal:11434               │     │
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
├── Dockerfile.ollama       # ubuntu:24.04 + node 20 + opencode + mcp bridge
├── entrypoint-ollama.sh    # convert agents, generate opencode.json, probe services, exec opencode
├── ptai-ollama             # POSIX-sh host wrapper (build / run)
├── Dockerfile              # standard pt-ai image (Claude API)
├── entrypoint.sh
├── ptai
├── .dockerignore
└── README-ollama.md
```

## Prerequisites

- Docker (Engine on Linux, or Docker Desktop on macOS).
- Ollama installed on the host and running (`ollama serve` or the background service).
- The model pulled on the host before running: `ollama pull <model>`.
- A reachable Linux host running `kali-server-mcp` on `127.0.0.1:5000`.

## Build

```sh
docker/ptai-ollama build              # build the image
docker/ptai-ollama build --no-cache   # rebuild from scratch
```

Pin the MCP bridge to a specific commit or override the base tag:

```sh
MCP_BRIDGE_REF=<full-sha> docker/ptai-ollama build
UBUNTU_TAG=24.04          docker/ptai-ollama build
```

## Set up Ollama

On the host:

```sh
# Install (macOS)
brew install ollama

# Pull the model you want to use
ollama pull gemma4:31b       # lightweight, good for advisory agents
ollama pull qwen2.5-coder:32b # stronger for execution agents

# Ollama runs as a background service automatically after install.
# If it is not running: ollama serve
```

No API key is required. Ollama's OpenAI-compatible endpoint accepts any value.

## Set up the remote MCP server

Identical to the standard setup. On the Linux host:

```sh
sudo apt install mcp-kali-server
kali-server-mcp --ip 127.0.0.1 --port 5000 &
```

The API must bind **only `127.0.0.1`**. Never expose it on the LAN.

## Run an engagement

Three pieces in place before `ptai-ollama run`:

1. **Ollama running** on the host with the model pulled.
2. **Remote MCP server running** on the Linux host (bound to `127.0.0.1:5000`).
3. **SSH tunnel up** in its own terminal, leave it running:
   ```sh
   ssh -L 5000:127.0.0.1:5000 user@<linux-host> -N
   ```

Then:

```sh
export PT_AI_OLLAMA_MODEL=gemma4:31b
export PT_AI_MCP_SERVER=http://host.docker.internal:5000
docker/ptai-ollama run <engagement-id>
```

This:

- Creates `engagements/<engagement-id>/` on the host (the only persistent surface).
- Bind-mounts `agents/` and converts them to opencode commands at startup.
- Generates `opencode.json` inside the container: registers the model under a custom `ollama` provider, points at Ollama on the host, and wires in the MCP bridge.
- Probes both Ollama and the remote MCP for readiness and warns if unreachable.
- Tears the container down on exit (`--rm`); only `engagements/<id>/` survives.

### Options

```sh
docker/ptai-ollama run my-eng --shell          # bash instead of opencode
docker/ptai-ollama run my-eng --listen 4444    # publish 4444/tcp for callbacks

# Override Ollama URL if not on the default port
PT_AI_OLLAMA_URL=http://host.docker.internal:11434 docker/ptai-ollama run my-eng
```

### Invoking agents inside opencode

Agents are available as slash commands. Type `/` in opencode to see the full list:

```
/recon-advisor       /vuln-scanner        /web-hunter
/ad-attacker         /exploit-guide       /exploit-chainer
/attack-planner      /engagement-planner  /report-generator
...
```

## Model recommendations

For pt-ai's security reasoning tasks, larger models perform significantly better.

| Model | Size | Best for |
|---|---|---|
| `qwen2.5-coder:32b` | 20GB+ VRAM | Execution agents, tool use, attack chaining |
| `llama3.1:70b` | 40GB+ VRAM | Full methodology, complex reasoning |
| `gemma4:31b` | 8GB VRAM | Advisory agents, quick lookups |

## Networking

Same as the standard setup. The container reaches the host via
`host.docker.internal` (Docker Desktop) or `--add-host=...:host-gateway` on
native Linux Docker, which the wrapper sets unconditionally.

## Ephemerality

The container is destroyed on exit (`--rm`). Only `engagements/<engagement-id>/`
persists on the host. No credentials are kept — Ollama needs no authentication.

## File ownership

Inside the container the process runs as `operator` (uid 1000). Same behaviour
as the standard image — see `docker/README.md` for details.

## Troubleshooting

| Symptom | Likely cause / fix |
|---|---|
| `pt-ai-ollama: PT_AI_OLLAMA_MODEL is required.` | Export `PT_AI_OLLAMA_MODEL` before running. |
| `pt-ai-ollama: PT_AI_MCP_SERVER is required.` | Export `PT_AI_MCP_SERVER=http://host.docker.internal:5000`. |
| `warning — Ollama at … is not reachable` | Run `ollama serve` on the host, or check the background service is running. |
| `warning — remote MCP at … is not reachable` | SSH tunnel down or `kali-server-mcp` not running. |
| Model not found in opencode | Run `ollama pull <model>` on the host first, then relaunch. |
| No agents show up as `/` commands | Check `~/.config/opencode/commands/` inside the container (`--shell` mode). |
| LLM responses are poor quality | Use a larger model. Advisory agents work with 8B; execution agents need 32B+. |

## Authorized use only

Same constraint as the rest of the repo: this tooling is for authorized
penetration-testing engagements only. Every agent enforces scope/authorization
verification before producing target-specific guidance.
