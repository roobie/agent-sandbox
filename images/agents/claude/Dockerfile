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

# Install Claude Code to user-space mise.
# claude-code is intentionally in the user data dir — it's a user-level tool.
ARG CLAUDE_CODE_VERSION=latest
RUN mise use -g claude-code@$CLAUDE_CODE_VERSION

# Configure Serena MCP server for claude-code.
# Must run before switching to system MISE_DATA_DIR so claude-code is found.
RUN mise exec -- \
    claude mcp add serena -- uvx --from git+https://github.com/oraios/serena serena start-mcp-server --context claude-code --project "$(pwd)"

# Install language runtimes to system path so they survive mise-state volume mount.
# Strategy: point MISE_DATA_DIR at /usr/local/share/mise — outside all named volume mounts.
# MISE_GLOBAL_CONFIG_FILE ensures the activation config lands in the system data dir.
# PATH update exposes the system shims to all subsequent build steps and container processes.
#
# At runtime, containers inherit these env vars so mise resolves system-wide installs.
# The dev user's mise-state volume (/home/dev/.mise) is for user-level overrides only.
#
# RUSTUP_HOME and CARGO_HOME are set to system-readable paths so rustc/cargo are accessible
# by non-root users. /root/.cargo is drwx------ (not accessible to non-root), so we use /usr/local/share.
ENV MISE_DATA_DIR=/usr/local/share/mise
ENV MISE_GLOBAL_CONFIG_FILE=/usr/local/share/mise/config.toml
ENV PATH="/usr/local/share/mise/shims:${PATH}"
ENV RUSTUP_HOME=/usr/local/share/rustup
ENV CARGO_HOME=/usr/local/share/cargo

USER root
ARG UV_VERSION
RUN mise install node@lts && \
    mise install python@3.13 && \
    mise install go@latest && \
    mise install rust@stable && \
    mise install bun@1.3 && \
    mise install rust-analyzer@latest && \
    mise install uv@$UV_VERSION && \
    chmod -R a+rx /usr/local/share/rustup /usr/local/share/cargo

# Activate all system tools — writes activation entries to MISE_GLOBAL_CONFIG_FILE
# and generates shims in /usr/local/share/mise/shims/
RUN mise use -g node@lts python@3.13 go@latest rust@stable \
    bun@1.3 rust-analyzer@latest uv@$UV_VERSION

# Install LSP tools via npm backend (npm shim now available via system node activation)
RUN mise install npm:pyright@latest && \
    mise install npm:typescript-language-server@latest && \
    mise use -g npm:pyright@latest npm:typescript-language-server@latest

# Per-package-manager proxy configuration baked into image layer.
# Configured paths are chosen to avoid named volume shadowing at runtime.

USER dev

# npm proxy — /home/dev/.npmrc is NOT under any volume mount.
# Also configure npm cache to use the named volume mount path (/home/dev/.npm).
# The volume is initially root-owned; npm needs write access.
# On first run the entrypoint's chown may fail (no CAP_CHOWN), so we keep /tmp as fallback.
RUN printf 'proxy=http://proxy:3128\nhttps-proxy=http://proxy:3128\ncache=/home/dev/.npm\n' \
    > /home/dev/.npmrc

# git proxy — writes to /home/dev/.gitconfig (not volume-mounted)
RUN git config --global http.proxy http://proxy:3128

USER root

# cargo proxy — /etc/cargo/config.toml avoids cargo-state:/home/dev/.cargo volume shadowing
# cargo reads /etc/cargo/config.toml as a system-level config
RUN mkdir -p /etc/cargo && \
    printf '[http]\nproxy = "http://proxy:3128"\n' \
    > /etc/cargo/config.toml

# Add Claude to PATH and set up aliases
RUN echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc && \
  echo "alias claude='mise exec -- claude'" >> ~/.zshrc && \
  echo "alias yolo-claude='cd /workspace && claude --dangerously-skip-permissions'" >> ~/.zshrc && \
  echo "alias yc='yolo-claude'" >> ~/.zshrc

EXPOSE 24282

# Entrypoint runs as root to adjust uid/gid, then drops to dev user
USER root
