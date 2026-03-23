# Technology Stack

**Analysis Date:** 2026-03-23

## Languages

**Primary:**
- Python 3.13.11 - Firewall initialization and build automation
- Bash - Entrypoint script and shell configuration
- Shell - Docker configuration and setup scripts

**Secondary:**
- YAML - Docker Compose and Dockerfile configuration
- JSON - Policy files for network allowlisting

## Runtime

**Environment:**
- Docker (Debian bookworm base image)
- Non-root user execution (dev user, uid/gid 500)

**Package Manager:**
- Mise (`mise.jdx.dev`) - Version management for Python, UV, Claude Code
- APT - Linux package management within container
- pip - Python package management (via UV)

## Frameworks

**Container Orchestration:**
- Docker Compose - Local development and testing
- Dockerfile - Multi-stage image builds (base, claude agent, copilot agent, devcontainer)

**Agent Runtime:**
- Claude Code - AI coding assistant (installed via Mise)
- UV - Python project and script runner (installed via Mise)

**Development Tools:**
- Zsh - Container shell with powerline10k theme
- git-delta (`0.18.2`) - Improved git diff viewer
- Neovim - Text editor
- fzf - Fuzzy finder

## Key Dependencies

**Critical:**
- `python3` - Language runtime
- `iptables` + `ipset` - Network firewall (core security feature)
- `iproute2` - Network routing tools
- `dnsutils` - DNS resolution tools
- `curl` - HTTP client (firewall verification)

**Infrastructure:**
- `git` - Version control
- `gh` - GitHub CLI
- `jq` - JSON processor
- `tmux` - Terminal multiplexer
- `ripgrep` - Fast text search
- `ca-certificates` - SSL/TLS trust anchors

**Development:**
- `build-essential` - C/C++ compiler toolchain
- `cmake` - Build system
- `pkg-config` - Compile flags for libraries
- `gdb` - Debugger
- `valgrind` - Memory analyzer
- `shellcheck` - Shell script linter

## Configuration

**Environment:**
- Configured via Docker Compose environment variables:
  - `TZ` - Timezone (default: America/Los_Angeles)
  - `CLAUDE_CONFIG_DIR` - Claude Code state directory
  - `DEVCONTAINER` - Flag indicating devcontainer mode
  - `MISE_*` - Mise configuration directories

**Build:**
- `images/build.py` - Python build script for Docker images
- Build args configurable via environment:
  - `PYTHON_VERSION` (default: 3.13.11)
  - `UV_VERSION` (default: 0.9.26)
  - `GIT_DELTA_VERSION` (default: 0.18.2)
  - `ZSH_IN_DOCKER_VERSION` (default: 1.2.0)
  - `CLAUDE_CODE_VERSION` (default: latest)

**Network Policy:**
- `/etc/agent-sandbox/policy.json` - Network allowlist (baked into image)
- Can be overridden via volume mount: `${HOME}/.config/agent-sandbox/policy.json`

## Platform Requirements

**Development:**
- Docker Engine with docker-compose
- 4+ CPU cores recommended
- 8GB+ RAM recommended
- 60GB+ disk space
- Linux, macOS (via Colima), or Windows (via Docker Desktop)

**Production/Runtime:**
- Debian bookworm compatible Linux kernel
- NET_ADMIN and NET_RAW capabilities for firewall
- Network access to configured allowed domains only

## Image Layers

**Base Image:**
- `agent-sandbox-base:local`
- Debian bookworm base with common development tools
- Firewall script and entrypoint
- Location: `images/base/Dockerfile`

**Agent Images:**
- `agent-sandbox-claude:local` - Claude Code agent with Mise runtime
  - Location: `images/agents/claude/Dockerfile`
- `agent-sandbox-copilot:local` - GitHub Copilot agent (experimental)
  - Location: `images/agents/copilot/Dockerfile`

**Devcontainer Image:**
- Extends `agent-sandbox-claude` with VS Code endpoints
- Location: `.devcontainer/Dockerfile`

---

*Stack analysis: 2026-03-23*
