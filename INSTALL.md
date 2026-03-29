# Installation Guide

## New to Claude? Start Here

If you haven't used Claude Code before, here's what you need and how to set it up.

### What is Claude Code?

Claude Code is a command-line tool from Anthropic that lets you work with Claude directly in your terminal. You type natural language, and Claude reads files, writes code, runs commands, and answers questions in context. pentest-ai adds 17 security-focused agents on top of this.

### Step 1: Get a Claude Account

1. Go to [claude.ai](https://claude.ai) and create an account
2. Subscribe to **Claude Pro** ($20/month) or **Claude Max** ($100/month). Claude Code requires a paid subscription. The free tier does not include CLI access.

### Step 2: Install Claude Code

Claude Code runs on Linux, macOS, and Windows (via WSL). You need Node.js 18+ installed first.

```bash
# Install Node.js if you don't have it (check with: node --version)
# macOS
brew install node

# Ubuntu/Debian
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt-get install -y nodejs

# Windows: Install WSL first (wsl --install), then use the Ubuntu instructions above
```

Then install Claude Code:

```bash
npm install -g @anthropic-ai/claude-code
```

### Step 3: Authenticate

```bash
# Run claude for the first time. It will open a browser window to log in.
claude
```

Follow the prompts to connect your Claude account. Once authenticated, you'll see the Claude Code prompt in your terminal. Type `exit` to close it for now.

### Step 4: Install pentest-ai

Follow the installation methods below to add the security agents.

### Step 5: Verify It Works

```bash
# Start Claude Code
claude

# Try a simple prompt
> What agents do you have available?
```

Claude should list the pentest-ai agents. Try a real task:

```
> Plan a basic external penetration test for a small web application
```

If Claude routes to the engagement-planner agent, you're all set.

### Troubleshooting Setup

| Problem | Fix |
|---------|-----|
| `npm: command not found` | Install Node.js first (see Step 2) |
| `claude: command not found` | Run `npm install -g @anthropic-ai/claude-code` again, or check that your npm global bin is in your PATH |
| "Authentication required" | Run `claude` and complete the browser login flow |
| "Subscription required" | You need Claude Pro or Max. The free tier does not include Claude Code |

For more details, see the [official Claude Code docs](https://docs.anthropic.com/en/docs/claude-code).

---

## Prerequisites

Before installing pentest-ai, ensure you have the following:

- **Claude Code CLI** installed and working (`claude` command available in your terminal)
- **Active Claude subscription** (Pro or Max tier recommended for best results)

## Installation Methods

### Method 1: Global Install

A global install makes the agents available in all your projects and directories.

```bash
# Clone or download the repository
# Then copy all agent files to your global Claude agents directory

cp agents/*.md ~/.claude/agents/
```

This places the agent definition files where Claude Code looks for them by default. The agents will be available in every Claude Code session regardless of your working directory.

### Method 2: Project-Level Install

A project-level install makes the agents available only when you are working within a specific project directory. This is useful if you want to keep security tooling isolated to specific engagement workspaces.

```bash
# Navigate to your project directory
cd /path/to/your/project

# Create the agents directory
mkdir -p .claude/agents/

# Copy agent files
cp /path/to/pentest-ai/agents/*.md .claude/agents/
```

### Method 3: One-Liner from GitHub

Clone the repository and install globally in a single command:

```bash
git clone https://github.com/0xSteph/pentest-ai.git && cp pentest-ai/agents/*.md ~/.claude/agents/
```


## Verification

After installation, verify that the agents are loaded correctly.

### Step 1: Start Claude Code

```bash
claude
```

### Step 2: Check Available Agents

Ask Claude:

```
What agents do you have available?
```

Claude should list the six pentest-ai agents among any other agents you have installed.

### Step 3: Test Each Agent

Run a sample prompt for each agent to verify they are routing correctly:

**Engagement Planner:**
```
Plan a basic external network penetration test for a small web application.
```

**Recon Advisor:**
```
What would you look for in an Nmap scan of a typical corporate /24 subnet?
```

**Exploit Guide:**
```
Explain the methodology for AS-REP Roasting and how to detect it.
```

**Detection Engineer:**
```
Create a Sigma rule for detecting suspicious PowerShell execution.
```

**STIG Analyst:**
```
What is STIG V-220768 and what does compliance require?
```

**Report Generator:**
```
What sections should a professional penetration test report include?
```

## Troubleshooting

### Agents Not Loading

- **Wrong directory:** Ensure the `.md` files are in `~/.claude/agents/` (global) or `.claude/agents/` (project-level). The directory name must be exactly `agents` inside the `.claude` directory.
- **Wrong file extension:** Agent definition files must have the `.md` extension.
- **File permissions:** Ensure the agent files are readable by your user account.

### Claude Not Routing to the Correct Agent

- **Check the description field:** Claude uses the `description` field in each agent's YAML frontmatter to determine when to route. If routing is inconsistent, review and adjust the description to more clearly match the types of prompts you are using.
- **Be specific in your prompts:** Vague prompts may not trigger the correct agent. Include keywords that match the agent's domain (e.g., "detection rule," "pentest report," "STIG compliance").
- **Invoke explicitly:** You can always invoke an agent by name if automatic routing is not selecting the right one.

### Model Not Available

- **Subscription tier:** Some agents may specify a model (such as `claude-sonnet-4-20250514` or `opus`) in their frontmatter. Ensure your subscription tier supports the specified model.
- **Model field:** If a model is not available to you, edit the agent's `.md` file and change the `model` field in the frontmatter to a model your subscription supports.

### Agent Output Quality

- **Provide context:** The agents perform best when given specific, detailed prompts with relevant context such as tool output, scope details, or engagement parameters.
- **Iterate:** If the first response is not detailed enough, follow up with more specific questions or provide additional information.
