#!/usr/bin/env bash
# pentest-ai installer
# Usage: ./install.sh [--global | --project | --uninstall | --update]

set -euo pipefail

VERSION="3.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENTS_SRC="${SCRIPT_DIR}/agents"
GLOBAL_DIR="${HOME}/.claude/agents"
PROJECT_DIR=".claude/agents"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

banner() {
    echo -e "${CYAN}"
    echo "  ____  _____ _   _ _____ _____ ____ _____        _    ___ "
    echo " |  _ \| ____| \ | |_   _| ____/ ___|_   _|     / \  |_ _|"
    echo " | |_) |  _| |  \| | | | |  _| \___ \ | |_____ / _ \  | | "
    echo " |  __/| |___| |\  | | | | |___ ___) || |_____/ ___ \ | | "
    echo " |_|   |_____|_| \_| |_| |_____|____/ |_|    /_/   \_\___|"
    echo ""
    echo -e "  ${BOLD}v${VERSION}${NC}${CYAN} - AI-Powered Penetration Testing Agents${NC}"
    echo ""
}

count_agents() {
    local dir="$1"
    find "$dir" -maxdepth 1 -name "*.md" ! -name "_*" -type f 2>/dev/null | wc -l
}

check_prereqs() {
    if ! command -v claude &>/dev/null; then
        echo -e "${YELLOW}Warning: Claude Code CLI not found in PATH.${NC}"
        echo "  Install it with: npm install -g @anthropic-ai/claude-code"
        echo ""
    fi

    if [ ! -d "$AGENTS_SRC" ]; then
        echo -e "${RED}Error: agents/ directory not found at ${AGENTS_SRC}${NC}"
        echo "  Run this script from the pentest-ai repository root."
        exit 1
    fi
}

install_global() {
    echo -e "${BOLD}Installing agents globally...${NC}"
    mkdir -p "$GLOBAL_DIR"

    local installed=0
    local updated=0
    local skipped=0

    for agent in "${AGENTS_SRC}"/*.md; do
        local name
        name=$(basename "$agent")
        local dest="${GLOBAL_DIR}/${name}"

        if [ -f "$dest" ]; then
            if ! diff -q "$agent" "$dest" &>/dev/null; then
                cp "$agent" "$dest"
                ((updated++))
                echo -e "  ${YELLOW}updated${NC}  ${name}"
            else
                ((skipped++))
            fi
        else
            cp "$agent" "$dest"
            ((installed++))
            echo -e "  ${GREEN}installed${NC} ${name}"
        fi
    done

    local total
    total=$(count_agents "$AGENTS_SRC")
    echo ""
    echo -e "${GREEN}Done.${NC} ${total} agents available globally."
    [ $installed -gt 0 ] && echo -e "  ${GREEN}${installed} new${NC}"
    [ $updated -gt 0 ] && echo -e "  ${YELLOW}${updated} updated${NC}"
    [ $skipped -gt 0 ] && echo -e "  ${skipped} unchanged"
    echo ""
    echo -e "  Location: ${CYAN}${GLOBAL_DIR}${NC}"
    echo "  Agents are available in all Claude Code sessions."
}

install_project() {
    echo -e "${BOLD}Installing agents for this project...${NC}"
    mkdir -p "$PROJECT_DIR"

    local installed=0
    for agent in "${AGENTS_SRC}"/*.md; do
        local name
        name=$(basename "$agent")
        cp "$agent" "${PROJECT_DIR}/${name}"
        ((installed++))
        echo -e "  ${GREEN}installed${NC} ${name}"
    done

    echo ""
    echo -e "${GREEN}Done.${NC} ${installed} agents installed to ${CYAN}${PROJECT_DIR}${NC}"
    echo "  Agents are available only in this directory."
}

uninstall() {
    echo -e "${BOLD}Uninstalling pentest-ai agents...${NC}"
    echo ""

    local removed=0

    # Check global
    if [ -d "$GLOBAL_DIR" ]; then
        for agent in "${AGENTS_SRC}"/*.md; do
            local name
            name=$(basename "$agent")
            if [ -f "${GLOBAL_DIR}/${name}" ]; then
                rm "${GLOBAL_DIR}/${name}"
                ((removed++))
                echo -e "  ${RED}removed${NC}  ${GLOBAL_DIR}/${name}"
            fi
        done
    fi

    # Check project-level
    if [ -d "$PROJECT_DIR" ]; then
        for agent in "${AGENTS_SRC}"/*.md; do
            local name
            name=$(basename "$agent")
            if [ -f "${PROJECT_DIR}/${name}" ]; then
                rm "${PROJECT_DIR}/${name}"
                ((removed++))
                echo -e "  ${RED}removed${NC}  ${PROJECT_DIR}/${name}"
            fi
        done
    fi

    if [ $removed -eq 0 ]; then
        echo "  No pentest-ai agents found to remove."
    else
        echo ""
        echo -e "${GREEN}Done.${NC} Removed ${removed} agent files."
    fi
}

show_status() {
    echo -e "${BOLD}Installation Status${NC}"
    echo ""

    local global_count
    global_count=$(count_agents "$GLOBAL_DIR")
    if [ "$global_count" -gt 0 ]; then
        echo -e "  Global: ${GREEN}${global_count} agents${NC} in ${GLOBAL_DIR}"
    else
        echo -e "  Global: ${YELLOW}not installed${NC}"
    fi

    if [ -d "$PROJECT_DIR" ]; then
        local project_count
        project_count=$(count_agents "$PROJECT_DIR")
        if [ "$project_count" -gt 0 ]; then
            echo -e "  Project: ${GREEN}${project_count} agents${NC} in ${PROJECT_DIR}"
        fi
    fi

    local source_count
    source_count=$(count_agents "$AGENTS_SRC")
    echo -e "  Source:  ${CYAN}${source_count} agents${NC} available in repo"
    echo ""
}

usage() {
    echo -e "${BOLD}Usage:${NC} ./install.sh [option]"
    echo ""
    echo "Options:"
    echo "  --global      Install agents globally (~/.claude/agents/)"
    echo "  --project     Install agents for current project (.claude/agents/)"
    echo "  --uninstall   Remove all pentest-ai agents"
    echo "  --update      Update existing global install (same as --global)"
    echo "  --status      Show installation status"
    echo "  --help        Show this help message"
    echo ""
    echo "No option: interactive mode (prompts you to choose)"
    echo ""
    echo "One-liner install from GitHub:"
    echo "  git clone https://github.com/0xSteph/pentest-ai.git && cd pentest-ai && ./install.sh --global"
}

interactive() {
    echo "Where do you want to install the agents?"
    echo ""
    echo "  1) Global     - available in all Claude Code sessions"
    echo "  2) Project    - available only in the current directory"
    echo "  3) Uninstall  - remove pentest-ai agents"
    echo "  4) Status     - show current installation"
    echo ""
    read -rp "Choice [1-4]: " choice

    case "$choice" in
        1) install_global ;;
        2) install_project ;;
        3) uninstall ;;
        4) show_status ;;
        *) echo "Invalid choice."; exit 1 ;;
    esac
}

# Main
banner
check_prereqs

case "${1:-}" in
    --global|--update) install_global ;;
    --project)         install_project ;;
    --uninstall)       uninstall ;;
    --status)          show_status ;;
    --help|-h)         usage ;;
    "")                interactive ;;
    *)                 echo -e "${RED}Unknown option: $1${NC}"; usage; exit 1 ;;
esac
