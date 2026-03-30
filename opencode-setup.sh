#!/usr/bin/env bash
# Convert pentest-ai agents to OpenCode/Crush custom commands
# Usage: ./opencode-setup.sh [--global | --project]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENTS_SRC="${SCRIPT_DIR}/agents"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

GLOBAL_CMD_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/opencode/commands"
PROJECT_CMD_DIR=".opencode/commands"

banner() {
    echo -e "${CYAN}"
    echo "  pentest-ai -> OpenCode/Crush adapter"
    echo -e "  ${BOLD}Provider-agnostic mode${NC}"
    echo ""
}

# Strip YAML frontmatter and convert agent to a command prompt
convert_agent() {
    local agent_file="$1"
    local dest_dir="$2"
    local name

    name=$(basename "$agent_file" .md)

    # Skip the scope guard (not a standalone agent)
    if [[ "$name" == _* ]]; then
        return
    fi

    # Extract everything after the closing --- of YAML frontmatter
    local content
    content=$(awk 'BEGIN{found=0} /^---$/{found++; next} found>=2{print}' "$agent_file")

    # Write as OpenCode custom command
    cat > "${dest_dir}/${name}.md" << CMDEOF
${content}
CMDEOF

    echo -e "  ${GREEN}converted${NC} ${name}"
}

install_global() {
    echo -e "${BOLD}Installing as global OpenCode commands...${NC}"
    mkdir -p "$GLOBAL_CMD_DIR"

    local count=0
    for agent in "${AGENTS_SRC}"/*.md; do
        convert_agent "$agent" "$GLOBAL_CMD_DIR"
        ((count++))
    done

    echo ""
    echo -e "${GREEN}Done.${NC} ${count} commands installed to ${CYAN}${GLOBAL_CMD_DIR}${NC}"
    echo ""
    echo "Usage in OpenCode/Crush:"
    echo "  /recon-advisor    - invoke the recon advisor"
    echo "  /vuln-scanner     - invoke the vuln scanner"
    echo "  /ad-attacker      - invoke the AD attacker"
    echo "  (etc.)"
}

install_project() {
    echo -e "${BOLD}Installing as project-level OpenCode commands...${NC}"
    mkdir -p "$PROJECT_CMD_DIR"

    local count=0
    for agent in "${AGENTS_SRC}"/*.md; do
        convert_agent "$agent" "$PROJECT_CMD_DIR"
        ((count++))
    done

    echo ""
    echo -e "${GREEN}Done.${NC} ${count} commands installed to ${CYAN}${PROJECT_CMD_DIR}${NC}"
}

create_context_file() {
    local dest="$1"
    cat > "$dest" << 'CTXEOF'
# pentest-ai Context

You are operating as a penetration testing assistant with 23 specialized knowledge areas.
When the user invokes a command (e.g., /recon-advisor, /vuln-scanner), follow the instructions
in that command file exactly. When no specific command is invoked, use your judgment to apply
the most relevant security methodology.

## Key Principles

1. Every technique must include both offensive methodology and defensive detection perspective
2. Map all techniques to MITRE ATT&CK IDs
3. For Tier 2 (execution) commands: validate scope before running any tool
4. Save all tool output to timestamped evidence files
5. Tag command noise levels: QUIET, MODERATE, or LOUD
6. Prioritize methodology first, tool execution second

## Available Commands

Offensive: /recon-advisor, /vuln-scanner, /web-hunter, /ad-attacker, /exploit-guide,
           /privesc-advisor, /cloud-security, /api-security, /osint-collector,
           /engagement-planner, /mobile-pentester, /wireless-pentester, /social-engineer,
           /credential-tester, /attack-planner, /bug-bounty

Defense:   /detection-engineer, /threat-modeler, /forensics-analyst, /malware-analyst,
           /stig-analyst

Reporting: /report-generator, /ctf-solver
CTXEOF
    echo -e "  ${GREEN}created${NC} ${dest}"
}

generate_ollama_config() {
    local config_file="$1"
    cat > "$config_file" << 'CFGEOF'
{
  "agents": {
    "coder": {
      "model": "local.llama3.1:70b",
      "maxTokens": 8000
    },
    "task": {
      "model": "local.llama3.1:70b",
      "maxTokens": 4000
    }
  },
  "contextPaths": [
    "opencode.md"
  ],
  "shell": {
    "path": "/bin/bash",
    "args": ["-l"]
  }
}
CFGEOF
    echo -e "  ${GREEN}created${NC} ${config_file}"
    echo ""
    echo -e "${YELLOW}Note:${NC} Edit the model name in ${config_file} to match your Ollama model."
    echo "  Common options:"
    echo "    local.llama3.1:70b      - Best quality for security work (40GB+ VRAM)"
    echo "    local.llama3.1:8b       - Lighter, runs on 8GB+ VRAM"
    echo "    local.qwen2.5:72b       - Strong alternative (40GB+ VRAM)"
    echo "    local.deepseek-r1:32b   - Good reasoning (20GB+ VRAM)"
    echo "    local.mistral-large      - Solid all-around (24GB+ VRAM)"
}

usage() {
    echo -e "${BOLD}Usage:${NC} ./opencode-setup.sh [option]"
    echo ""
    echo "Options:"
    echo "  --global      Install commands globally for OpenCode/Crush"
    echo "  --project     Install commands for current project"
    echo "  --context     Generate opencode.md context file in current directory"
    echo "  --config      Generate .opencode.json with Ollama local model config"
    echo "  --full        Do everything: global commands + context + config"
    echo "  --help        Show this help"
    echo ""
    echo "Prerequisites:"
    echo "  1. Install OpenCode: go install github.com/opencode-ai/opencode@latest"
    echo "     Or Crush:  go install github.com/charmbracelet/crush@latest"
    echo "  2. For local models: install Ollama (https://ollama.ai)"
    echo "     Then: ollama pull llama3.1:70b"
    echo "  3. Set LOCAL_ENDPOINT=http://localhost:11434/v1"
}

interactive() {
    echo "What do you want to set up?"
    echo ""
    echo "  1) Global commands    - available in all OpenCode sessions"
    echo "  2) Project commands   - available in current directory only"
    echo "  3) Full local setup   - commands + context file + Ollama config"
    echo ""
    read -rp "Choice [1-3]: " choice

    case "$choice" in
        1) install_global ;;
        2) install_project ;;
        3)
            install_global
            echo ""
            echo -e "${BOLD}Creating context and config files...${NC}"
            create_context_file "opencode.md"
            generate_ollama_config ".opencode.json"
            ;;
        *) echo "Invalid choice."; exit 1 ;;
    esac
}

# Main
banner

case "${1:-}" in
    --global)   install_global ;;
    --project)  install_project ;;
    --context)  create_context_file "opencode.md" ;;
    --config)   generate_ollama_config ".opencode.json" ;;
    --full)
        install_global
        echo ""
        echo -e "${BOLD}Creating context and config files...${NC}"
        create_context_file "opencode.md"
        generate_ollama_config ".opencode.json"
        ;;
    --help|-h)  usage ;;
    "")         interactive ;;
    *)          echo -e "${RED}Unknown option: $1${NC}"; usage; exit 1 ;;
esac
