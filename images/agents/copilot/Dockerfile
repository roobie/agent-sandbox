# Claude Code agent image
# Extends base with Copilot CLI and aliases

ARG BASE_IMAGE=agent-sandbox-base:local
FROM ${BASE_IMAGE}

# Install mise and Copilot tools as root
USER root

# Install mise via official APT repo
RUN install -dm 755 /etc/apt/keyrings && \
  curl -fsSL https://mise.jdx.dev/gpg-key.pub \
    | tee /etc/apt/keyrings/mise-archive-keyring.asc > /dev/null && \
  echo "deb [signed-by=/etc/apt/keyrings/mise-archive-keyring.asc] https://mise.jdx.dev/deb stable main" \
    > /etc/apt/sources.list.d/mise.list && \
  apt-get update && \
  apt-get install -y --no-install-recommends mise && \
  apt-get clean && rm -rf /var/lib/apt/lists/*

# Create _ config directory
# RUN mkdir -p /home/dev/.claude && chown -R dev:dev /home/dev/.claude
USER dev

# Install Claude Code
ARG CLAUDE_CODE_VERSION=latest
RUN mise use -g claude-code@$CLAUDE_CODE_VERSION

ARG UV_VERSION
RUN mise use -g uv@$UV_VERSION

# Activate mise in shell — puts all mise-managed tools on PATH automatically
RUN echo 'eval "$(mise activate zsh)"' >> /home/dev/.zshrc && \
  echo 'export PATH="$HOME/.local/bin:$PATH"' >> /home/dev/.zshrc && \
  echo "alias yolo-claude='cd /workspace && claude --dangerously-skip-permissions'" >> /home/dev/.zshrc && \
  echo "alias yc='yolo-claude'" >> /home/dev/.zshrc

EXPOSE 24282

# Entrypoint runs as root to adjust uid/gid, then drops to dev user
USER root
