# syntax=docker/dockerfile:1.6
#
# pt-ai: ephemeral Ubuntu container running Claude Code + the MCP stdio bridge.
#
# The Kali toolset and the MCP API server live on a separate Linux host.
# This container only handles Claude reasoning and the bridge that translates
# MCP stdio calls into HTTP requests against that remote API.
#
# Build-args:
#   UBUNTU_TAG       base image tag (default 24.04)
#   MCP_BRIDGE_REPO  upstream repo for the bridge (default Wh0am123/MCP-Kali-Server)
#   MCP_BRIDGE_REF   git ref to checkout (default main; pass a specific SHA
#                    via the wrapper's MCP_BRIDGE_REF env var for reproducibility)
#
ARG UBUNTU_TAG=24.04
FROM ubuntu:${UBUNTU_TAG}

ARG VERSION=dev
ARG MCP_BRIDGE_REPO=https://github.com/Wh0am123/MCP-Kali-Server.git
ARG MCP_BRIDGE_REF=main

LABEL org.opencontainers.image.title="pt-ai" \
      org.opencontainers.image.description="Ephemeral Ubuntu container with Claude Code and the kali MCP bridge" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.version="${VERSION}"

ENV DEBIAN_FRONTEND=noninteractive \
    HOME=/home/operator \
    PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin

# Base utilities + Node 20 (NodeSource — Ubuntu 24.04's apt nodejs is 18) +
# Python with venv support (Ubuntu 24.04 enforces PEP 668 system-Python pip).
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
        ca-certificates curl git jq \
        python3 python3-pip python3-venv \
 && curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
 && apt-get install -y --no-install-recommends nodejs \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/*

# Claude Code CLI.
RUN npm install -g @anthropic-ai/claude-code

# Vendor the MCP stdio bridge from upstream Wh0am123/MCP-Kali-Server. The bug
# we hit in the apt-packaged kali-server-mcp lives in the API server (which we
# do not run here); the bridge is small and stable. Pin a specific commit via
# --build-arg MCP_BRIDGE_REF=<sha> for reproducibility; the resolved SHA is
# recorded at /opt/mcp-bridge/.commit inside the image.
RUN git clone "${MCP_BRIDGE_REPO}" /opt/mcp-bridge \
 && cd /opt/mcp-bridge \
 && git checkout "${MCP_BRIDGE_REF}" \
 && git rev-parse HEAD > /opt/mcp-bridge/.commit \
 && python3 -m venv /opt/mcp-bridge/.venv \
 && /opt/mcp-bridge/.venv/bin/pip install --no-cache-dir -r requirements.txt \
 && rm -rf /opt/mcp-bridge/.git

# Non-root operator user (uid 1000).
# ubuntu:24.04 ships a default 'ubuntu' user at uid 1000; remove it so we can
# claim uid 1000 for our 'operator' user and have host bind-mounts line up.
RUN userdel -r ubuntu 2>/dev/null || true \
 && useradd -m -s /bin/bash -u 1000 -g operator operator \
 && mkdir -p /home/operator/.claude /work \
 && chown -R operator:operator /home/operator /work

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod 755 /usr/local/bin/entrypoint.sh

USER operator
WORKDIR /work

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["claude"]
