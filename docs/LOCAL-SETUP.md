# Running pt-ai Without Cloud Providers

pt-ai agents are plain markdown files. The security methodology, MITRE ATT&CK mappings, and tool guidance inside them work with any LLM that supports system prompts. If Anthropic, OpenAI, or any cloud provider changes their terms, restricts security content, or shuts down, your agents still work.

This guide covers running pt-ai fully offline with local models.

## Why Run Locally?

- **No keyword filtering.** Local models don't flag terms like "exploit" or "vulnerability." You get unfiltered methodology guidance for authorized testing.
- **No data leaves your machine.** Client data, scan results, and engagement details stay local. No API calls, no telemetry, no training data concerns.
- **No vendor lock-in.** If any provider pulls the plug or changes their acceptable use policy, your tooling keeps working.
- **No subscription costs.** After the hardware investment, ongoing costs are electricity only.

## How the VM is wired

`./pt-ai provision` writes `~/.config/opencode/opencode.json` inside the VM with the
native Anthropic provider as the default (`anthropic/claude-sonnet-4-6`). **To use a
local model, run `./pt-ai local-model detect` then `./pt-ai local-model use <id>`** —
it finds the reachable endpoint, writes a durable provider config (survives
re-provision and `destroy`/`up`), and switches the active model for you (Option 1
below). The `./pt-ai opencode` wrapper also forwards `PT_AI_OPENCODE_MODEL`, so you
can flip models per session:

```sh
PT_AI_OPENCODE_MODEL=local/qwen/qwen3.6-35b-a3b ./pt-ai opencode
```

**Host address from the VM** depends on your Vagrant provider:

- **VMware** (the default) **/ Parallels**: use the host-only address reachable
  from the guest (e.g. `172.16.145.1` or `192.168.161.1` on VMware Fusion — check
  `ip route` in the VM for the gateway). `10.0.2.2` will **not** work here.
- **VirtualBox** (`VAGRANT_PROVIDER=virtualbox`): the host is `10.0.2.2` over the
  NAT interface.

## Option 1: LM Studio (Recommended)

[LM Studio](https://lmstudio.ai/) provides a GUI for downloading and running local
models with an OpenAI-compatible API. opencode inside the VM speaks OpenAI
natively — no translation proxy needed. Strong tool-callers for the agent workflow
include **`qwen/qwen3.6-35b-a3b`** and **`openai/gpt-oss-20b`**.

**Assumptions:** LM Studio is installed on the host, a model is loaded, and the local
server is started with **"Serve on Local Network" enabled** (otherwise it binds to
localhost only and the VM can't reach it).

### Easiest: `./pt-ai local-model` (recommended)

The wrapper finds the reachable endpoint and writes a **durable** config that
survives `./pt-ai provision` and `destroy`/`up` (stored in
`config/opencode/local-model.json`, see `local-model.json.example`):

```sh
cd vagrant
./pt-ai local-model detect                       # probes the VM → host for LM Studio/Ollama, lists model ids
./pt-ai local-model use qwen/qwen3.6-35b-a3b      # copy an exact id from detect; writes durable config + applies live
./pt-ai opencode                                  # launches on the local model (no fallback warning)
```

`detect` tries the VMware/Parallels host-only gateways and the VirtualBox NAT host
automatically on ports `1234` (LM Studio) and `11434` (Ollama); pass `--port N` or
`--url http://HOST:PORT/v1` to override. `use` verifies the id is actually served
(catching prefix/casing typos) before writing anything.

### Manual fallback

If you prefer to edit the config by hand, write `~/.config/opencode/opencode.json`
inside the VM (`./pt-ai ssh`) — but note this is **not** durable; `./pt-ai provision`
regenerates the file, so prefer `local-model use` above:

```json
{
  "$schema": "https://opencode.ai/config.json",
  "provider": {
    "lmstudio": {
      "npm": "@ai-sdk/openai-compatible",
      "options": { "baseURL": "http://172.16.145.1:1234/v1" },
      "models": { "gpt-oss-20b": { "name": "gpt-oss-20b" } }
    }
  },
  "model": "lmstudio/gpt-oss-20b"
}
```

Replace the `baseURL` host with your provider's host address (see above) and the
model id with whatever LM Studio shows. Then run `./pt-ai opencode`.

## Option 2: Ollama

Ollama runs on your host and exposes an OpenAI-compatible API. opencode connects
directly to it — no translation proxy needed.

**Assumptions:** Ollama is installed on the host and the desired model is pulled.

```sh
# 1. Install Ollama and pull a model (on the host)
brew install ollama             # macOS
ollama pull qwen2.5-coder:32b   # or whichever model fits your VRAM

# 2. Expose Ollama to the VM (bind to all interfaces, not just localhost)
OLLAMA_HOST=0.0.0.0 ollama serve
```

Then point opencode at it the same way as LM Studio — `./pt-ai local-model detect`
probes port `11434` too, so:

```sh
cd vagrant
./pt-ai local-model detect
./pt-ai local-model use qwen2.5-coder:32b
./pt-ai opencode
```

Or configure it by hand (not durable; `./pt-ai provision` regenerates the file) —
write `~/.config/opencode/opencode.json` inside the VM (`./pt-ai ssh`):

```json
{
  "$schema": "https://opencode.ai/config.json",
  "provider": {
    "ollama": {
      "npm": "@ai-sdk/openai-compatible",
      "options": { "baseURL": "http://172.16.145.1:11434/v1" },
      "models": { "qwen2.5-coder:32b": { "name": "qwen2.5-coder:32b" } }
    }
  },
  "model": "ollama/qwen2.5-coder:32b"
}
```

Replace the `baseURL` host with your provider's host address (see above), then
`./pt-ai opencode`. Smaller Ollama models vary in tool-calling reliability — if the
agents misbehave, prefer the LM Studio + `gpt-oss-20b` path above.

### Multi-GPU Setup

If you have multiple GPUs:

```bash
# Ollama automatically uses multiple GPUs when available
# Set the number of GPU layers to offload
OLLAMA_NUM_GPU=2 ollama serve

# For specific GPU selection
CUDA_VISIBLE_DEVICES=0,1 ollama serve
```

## Option 3: Raw System Prompts (Any LLM)

If you don't use OpenCode or Claude Code at all, you can still use the agent methodology directly. Each agent file contains a complete system prompt after the YAML frontmatter.

```bash
# Extract the system prompt from any agent
awk 'BEGIN{found=0} /^---$/{found++; next} found>=2{print}' agents/recon-advisor.md
```

Paste this as the system prompt in any LLM interface: ChatGPT, local web UI, Hugging Face, API calls, etc. You lose automatic routing and tool execution, but the methodology guidance works the same.

### API Usage Example

```python
# Works with any OpenAI-compatible API (Ollama, vLLM, LM Studio, etc.)
import openai

client = openai.OpenAI(
    base_url="http://localhost:11434/v1",
    api_key="not-needed"
)

# Load agent system prompt
with open("agents/recon-advisor.md") as f:
    lines = f.readlines()
    # Skip YAML frontmatter
    system_prompt = []
    frontmatter_count = 0
    for line in lines:
        if line.strip() == "---":
            frontmatter_count += 1
            continue
        if frontmatter_count >= 2:
            system_prompt.append(line)

response = client.chat.completions.create(
    model="llama3.1:70b",
    messages=[
        {"role": "system", "content": "".join(system_prompt)},
        {"role": "user", "content": "Analyze this Nmap output: ..."}
    ]
)
print(response.choices[0].message.content)
```

## Hardware Requirements

### Minimum (8B Models)
- GPU: NVIDIA RTX 3060 12GB or RTX 4060 8GB
- RAM: 16GB
- Storage: 20GB for model files
- Quality: Basic methodology guidance, simple analysis

### Recommended (32B-70B Models)
- GPU: NVIDIA RTX 4090 24GB or 2x RTX 3090
- RAM: 32GB
- Storage: 100GB for model files
- Quality: Full methodology, reliable command syntax, good analysis

### Optimal (70B+ Models, Full Quality)
- GPU: 2x NVIDIA A100 80GB or 2x RTX 4090
- RAM: 64GB
- Storage: 200GB for model files
- Quality: Comparable to cloud API, full attack chain reasoning

### Apple Silicon
- M1 Pro/Max: 8B models comfortably, 32B with quantization
- M2 Ultra: 70B models with unified memory (192GB config)
- M3 Max: 32B models at good speed, 70B with quantization

## Choosing Between Cloud and Local

| Factor | Cloud (Claude Code) | Local (LM Studio/Ollama + opencode) |
|--------|-------------------|--------------------------|
| Model quality | Best available (frontier Claude) | Good with 70B+, moderate with smaller |
| Privacy | Data goes to Anthropic/OpenAI | Nothing leaves your machine |
| Content policy | Some security terms may be filtered | No filtering |
| Cost | $20-100/month subscription | Hardware cost only |
| Setup | 5 minutes | 30-60 minutes |
| Auto-routing | Built-in subagent routing | Manual command invocation |
| Tier 2 execution | Full support | Full support (same bash/tool access) |
| Reliability | Depends on API uptime | Runs offline |

## Keeping Agents Provider-Agnostic

The agent files are designed to be portable:

1. **Core content is plain markdown.** The methodology, techniques, and tool references are text. No provider-specific API calls or SDK dependencies.
2. **YAML frontmatter is the only platform-specific part.** opencode reads `skills/` natively via the Claude-compat path, and `./pt-ai provision` translates `agents/` into opencode subagents — the markdown body is shared verbatim across both.
3. **Tool names map directly.** Claude Code's `Bash`, `Read`, `Write`, `Edit`, `Grep`, `Glob` map 1:1 to OpenCode's `bash`, `view`, `write`, `edit`, `grep`, `glob`.
4. **No proprietary features used.** The agents don't use Claude-specific features like artifacts, projects, or memory. They're pure system prompts.

If you're building on top of pt-ai and want to stay portable, keep your additions in the same format: methodology in markdown, tool references by generic name, no provider-specific API calls.
