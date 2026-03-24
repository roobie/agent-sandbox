# Claude Code agent image
# Extends base with Claude Code CLI and aliases

ARG BASE_IMAGE=agent-sandbox-base:local
FROM ${BASE_IMAGE}

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

# Create claude config directory
RUN mkdir -p /home/dev/.claude && chown -R dev:dev /home/dev/.claude
USER dev

# Install Claude Code
ARG CLAUDE_CODE_VERSION=latest
RUN mise use -g claude-code@$CLAUDE_CODE_VERSION

ARG UV_VERSION
RUN mise use -g uv@$UV_VERSION

# Install language runtimes to system path so they survive mise-state volume mount.
# System installs go to /usr/local/share/mise/installs/ (not ~/.local/share/mise/installs/)
# which is outside any named volume mount — available on fresh volumes immediately.
USER root
RUN mise install --system node@lts && \
    mise install --system python@3.13 && \
    mise install --system go@latest && \
    mise install --system rust@stable && \
    mise install --system bun@1.3 && \
    mise install --system rust-analyzer@latest

# LSP tools via npm backend — must run after node@lts is installed
RUN mise install --system npm:pyright@latest && \
    mise install --system npm:typescript-language-server@latest

# Activate all system tools globally so they are on PATH for all users
RUN mise use --system node@lts python@3.13 go@latest rust@stable \
    bun@1.3 rust-analyzer@latest \
    npm:pyright@latest npm:typescript-language-server@latest

# Add Claude to PATH and set up aliases
RUN echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc && \
  echo "alias claude='mise exec -- claude'" >> ~/.zshrc && \
  echo "alias yolo-claude='cd /workspace && claude --dangerously-skip-permissions'" >> ~/.zshrc && \
  echo "alias yc='yolo-claude'" >> ~/.zshrc

RUN mise exec -- \
    claude mcp add serena -- uvx --from git+https://github.com/oraios/serena serena start-mcp-server --context claude-code --project "$(pwd)"

EXPOSE 24282

# Entrypoint runs as root to adjust uid/gid, then drops to dev user
USER root
