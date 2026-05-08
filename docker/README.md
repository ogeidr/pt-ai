# pt-ai Docker

Ephemeral Ubuntu container running Claude Code and a vendored stdio MCP bridge.
The Kali toolset and the MCP API server live on a separate Linux host (your
existing Kali VM, a small cloud box, etc.); the container only handles Claude
reasoning and the bridge that translates MCP stdio calls into HTTP requests
against the remote API. Each engagement runs in a throwaway container; only
the per-engagement evidence directory survives.

## Architecture

```
┌──────────── client host (e.g. macOS) ────────────┐    ┌──── Linux host ────┐
│                                                  │    │                    │
│  ssh -L 5000:127.0.0.1:5000 user@<linux-host>  ──┼────►  kali-server-mcp   │
│                                                  │    │  bound 127.0.0.1   │
│  ┌──── pt-ai container (ubuntu:24.04) ──────┐    │    │  :5000             │
│  │  Claude Code  ── stdio ──►  client.py    │    │    │                    │
│  │                              │ (bridge)  │    │    │  nmap, gobuster,   │
│  │                              ▼           │    │    │  nikto, …          │
│  │   HTTP → host.docker.internal:5000 ──────┼────┘    │                    │
│  └────────────────────────────────────────────┘         │                    │
└──────────────────────────────────────────────────┘    └────────────────────┘
```

The bridge (`client.py`) is vendored from upstream
[`Wh0am123/MCP-Kali-Server`](https://github.com/Wh0am123/MCP-Kali-Server) at a
commit pinned via the `MCP_BRIDGE_REF` build-arg. The resolved SHA is recorded
at `/opt/mcp-bridge/.commit` inside the image.

## Layout

```
docker/
├── Dockerfile            # ubuntu:24.04 + node 20 + claude code + vendored bridge
├── entrypoint.sh         # auth check, register MCP, probe remote, exec claude
├── ptai                  # POSIX-sh host wrapper (build / auth / run)
├── .dockerignore
└── README.md
```

## Prerequisites

- Docker (Engine on Linux, or Docker Desktop on macOS).
- An Anthropic API key, or a Claude Pro/Max subscription for browser OAuth.
- A reachable Linux host running `kali-server-mcp` on `127.0.0.1:5000`.
  Typically a Kali VM with the `mcp-kali-server` apt package installed.

## Build

```sh
docker/ptai build              # refresh base + bridge HEAD
docker/ptai build --no-cache   # rebuild everything from scratch
```

`build` always passes `--pull`, so the base layer is refreshed every time.

Pin the bridge to a specific upstream commit for reproducibility, or override
the Ubuntu base tag:

```sh
MCP_BRIDGE_REF=<full-sha> docker/ptai build
UBUNTU_TAG=24.04          docker/ptai build
```

Inspect the bridge SHA baked into a built image:

```sh
docker run --rm --entrypoint cat pt-ai:latest /opt/mcp-bridge/.commit
```

## Authenticate

Two options. Mutually exclusive — pick one per session.

### Option A — API key (no browser)

Export the key on the host before `ptai run`:

```sh
export ANTHROPIC_API_KEY=sk-ant-...
docker/ptai run my-engagement
```

Bills against the API key, not your Pro/Max subscription.

### Option B — Browser OAuth (Pro/Max)

One-time login persists a credential file on the host:

```sh
docker/ptai auth
```

Inside the container, run `claude /login`, open the printed URL on this host,
paste the code back. Credential is written to `~/.claude-pt-ai/.credentials.json`
(override with `PT_AI_AUTH_DIR`). All subsequent `ptai run` calls bind-mount it
writable so token refresh works.

If both `ANTHROPIC_API_KEY` and the credential file are present, the API key
wins.

## Set up the remote MCP server

On the Linux host that will run the actual scans:

```sh
# Install once, then keep it running (e.g. systemd, tmux, or just a backgrounded
# process while you work).
sudo apt install mcp-kali-server
kali-server-mcp --ip 127.0.0.1 --port 5000 &
```

The API must bind **only `127.0.0.1`**. Never expose it on the LAN — the API
runs arbitrary commands and would give any reachable host RCE on the Linux
host.

If the apt package's server has the `CommandExecutor` regression that rejects
list inputs (symptom: `500 Server Error`, message `CommandExecutor expects a
string, but got list`), apply the in-place fix and pin the package so apt
upgrades don't re-introduce the bug:

```sh
sudo python3 /tmp/patch_mcp.py    # one-shot patch script you keep around
sudo apt-mark hold mcp-kali-server
```

## Run an engagement

Three pieces in place before `ptai run`:

1. **Remote API server running** on the Linux host (bound to `127.0.0.1:5000`).
2. **SSH tunnel up** in its own terminal, leave it running:
   ```sh
   ssh -L 5000:127.0.0.1:5000 user@<linux-host> -N
   ```
3. **`PT_AI_MCP_SERVER` set** to the URL the container should hit:
   ```sh
   export PT_AI_MCP_SERVER=http://host.docker.internal:5000
   ```

Then:

```sh
docker/ptai run <engagement-id>
```

This:

- Creates `engagements/<engagement-id>/` on the host (the only persistent surface).
- Bind-mounts the repo's `agents/` read-only into `~/.claude/agents/` so all
  agents in `agents/` are available to Claude Code.
- Registers the MCP bridge in `~/.claude.json` pointing at `$PT_AI_MCP_SERVER`.
- Probes the remote URL for readiness; warns if unreachable within ~5 s.
- Tears the container down on exit (`--rm`); only `engagements/<id>/` survives.

### Options

```sh
docker/ptai run my-eng --shell                       # bash instead of claude
docker/ptai run my-eng --listen 4444                 # publish 4444/tcp for callbacks
docker/ptai run my-eng -- --model sonnet             # extra args after -- go to claude
```

`--listen` publishes the same port on host and container (`-p 4444:4444`).
For multiple ports, run `docker run` directly using the same flags as the
wrapper.

## Networking

Default bridge networking. The container reaches the Linux host via
`host.docker.internal` (Docker Desktop) or via `--add-host=...:host-gateway`
on native Linux Docker (≥20.10), which the wrapper sets unconditionally.

The container has **no network capabilities** beyond what default bridge
networking provides — no `NET_RAW`, no `NET_ADMIN`. Raw-socket scans happen on
the Linux host where the API server runs, not inside this container.

## Ephemerality

The container is destroyed on exit (`--rm`); the image is immutable. Two
things persist on the host: **engagement evidence** under
`engagements/<engagement-id>/` (the artifact of the engagement), and
**Claude Code's own state** under `~/.claude-pt-ai/` and
`~/.claude-pt-ai-home.json` (OAuth token + session history, so logins
survive between containers). To start clean, `rm -rf ~/.claude-pt-ai/
~/.claude-pt-ai-home.json` and re-run `ptai auth`.

## File ownership

Inside the container the process runs as `operator` (uid 1000). Files in
`engagements/<id>/` will be owned by uid 1000 on the host. On macOS Docker
Desktop, this is transparently mapped to your user. On Linux, if your host
uid is not 1000, run `chown -R "$(id -u):$(id -g)" engagements/<id>/` after
the session.

## Troubleshooting

| Symptom                                                          | Likely cause / fix                                                                                                                            |
|------------------------------------------------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------|
| `pt-ai: no authentication available.`                            | Set `ANTHROPIC_API_KEY` or run `ptai auth`.                                                                                                   |
| `pt-ai: PT_AI_MCP_SERVER is required.`                           | Export `PT_AI_MCP_SERVER=http://host.docker.internal:5000` before `ptai run`.                                                                |
| `pt-ai: warning — remote MCP at … is not reachable.`             | SSH tunnel down, or remote `kali-server-mcp` not running, or wrong URL. The startup probe fired; tool calls will fail until fixed.            |
| MCP tool calls return `500` with `CommandExecutor expects a string, but got list` | Apply the executor patch on the Linux host (see above) and `apt-mark hold mcp-kali-server`.                                                 |
| File ownership wrong on Linux                                    | `chown -R "$(id -u):$(id -g)" engagements/<id>/` after the session.                                                                           |

## Authorized use only

Same constraint as the rest of the repo: this tooling is for authorized
penetration-testing engagements only. Every agent enforces scope/authorization
verification before producing target-specific guidance.
