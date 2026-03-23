# External Integrations

**Analysis Date:** 2026-03-23

## APIs & External Services

**GitHub:**
- GitHub API - Code repository access, authentication
  - SDK/Client: `gh` CLI (GitHub CLI)
  - Auth: SSH keys (mounted from host)
  - Firewall Policy: In all agent policies via "github" service
  - IP Ranges: Fetched dynamically from `https://api.github.com/meta`

**Anthropic (Claude Code):**
- Claude Code IDE - AI coding assistant
  - SDK/Client: `claude` CLI (installed via Mise)
  - Auth: Credentials stored in Docker volume at `/home/dev/.claude`
  - Allowed Endpoints:
    - `api.anthropic.com` - Claude API calls
    - `sentry.io` - Error tracking/telemetry
    - `statsig.anthropic.com` - Feature flags
    - `statsig.com` - Analytics

**Package Registries:**
- PyPI - Python package repository
  - Used for: `uv` package manager dependencies
  - Domain: `pypi.org`
  - Auth: Optional authentication via host's `~/.pypirc` (not provided by default)

**Mise Version Registry:**
- `mise-versions.jdx.dev` - Tool version manifest
  - Used for: Fetching latest versions of tools managed by Mise

**Microsoft (VS Code - Devcontainer only):**
- VS Code remote development
  - Domains: `marketplace.visualstudio.com`, `vscode.blob.core.windows.net`, `update.code.visualstudio.com`, `mobile.events.data.microsoft.com`
  - Only allowed in devcontainer policy (`.devcontainer/policy.json`)

## Data Storage

**Databases:**
- None - Agent-Sandbox is a development sandbox without persistent database

**File Storage:**
- Local filesystem only
  - Workspace: `/workspace` (bind mount from host)
  - Claude state: `/home/dev/.claude` (Docker volume, persists across rebuilds)
  - Shell history: `/commandhistory` (Docker volume)
  - Mise state: `/home/dev/.mise` (Docker volume)
  - Cargo state: `/home/dev/.cargo` (Docker volume)
  - Local bin: `/home/dev/.local/bin` (Docker volume)

**Caching:**
- Mise Cache: `/home/dev/.mise/cache` (Docker volume)

## Authentication & Identity

**Auth Provider:**
- Custom/Host-based
  - SSH keys: Mounted from host (typically `~/.ssh`)
  - GitHub token: Via SSH keys or `gh` CLI authentication
  - Claude Code: Credentials stored in Docker volume
  - VS Code: Session stored in Docker volume

**Implementation:**
- Credentials and SSH keys are **not** stored within the container image
- Loaded from host filesystem at runtime via volume mounts
- `CLAUDE_CONFIG_DIR` environment variable points to persistent state directory

## Monitoring & Observability

**Error Tracking:**
- Sentry.io - Error reporting (via Claude Code)
  - Domain: `sentry.io`

**Logs:**
- Local to container/stdout
- Shell history persisted to `/commandhistory/.bash_history` (Docker volume)
- No centralized logging configured

**Firewall Verification:**
- `init-firewall.py` verifies connectivity:
  - Confirms `https://example.com` is blocked (policy enforcement)
  - Confirms at least one allowed endpoint is reachable (GitHub API or first domain in policy)

## CI/CD & Deployment

**Hosting:**
- Docker container runtime
- Deployable to any Docker-compatible environment

**Container Registry:**
- GHCR (GitHub Container Registry) - Published images
  - Base images: `ghcr.io/mattolson/agent-sandbox-base`
  - Agent images: `ghcr.io/mattolson/agent-sandbox-claude`
  - Dev/local images: `agent-sandbox-*:local` (built locally via `images/build.py`)

**CI Pipeline:**
- GitHub Actions (referenced in `.github/` directory)
- Not detailed in this analysis

## Environment Configuration

**Required env vars:**
- `TZ` - Timezone (default: America/Los_Angeles)
- `CLAUDE_CONFIG_DIR` - Claude state directory (default: `/home/dev/.claude`)

**Optional env vars (for build):**
- `PYTHON_VERSION` - Python version for installation
- `UV_VERSION` - UV tool version
- `GIT_DELTA_VERSION` - git-delta version
- `ZSH_IN_DOCKER_VERSION` - zsh-in-docker script version
- `CLAUDE_CODE_VERSION` - Claude Code CLI version

**Secrets location:**
- No secrets committed to repository
- Host machine credentials (SSH keys, etc.) mounted at runtime
- Claude authentication: Stored in Docker volume (persists across container restarts)

## Network Policy & Firewall

**Firewall Implementation:**
- `init-firewall.py` - Python script that runs at container startup
- Uses iptables + ipset for network enforcement
- Default: **block all outbound traffic**
- Allow: Only domains/services specified in policy.json

**Policy Format:**
```json
{
  "services": ["github"],
  "domains": [
    "api.anthropic.com",
    "sentry.io"
  ]
}
```

**Policy Layering:**
- **Base policy**: `images/base/policy.json` - GitHub only
- **Claude policy**: `images/agents/claude/policy.json` - GitHub + Claude Code endpoints
- **Copilot policy**: `images/agents/copilot/policy.json` - GitHub + PyPI (for dependencies)
- **Devcontainer policy**: `.devcontainer/policy.json` - GitHub + Claude + VS Code
- **Host override**: `${HOME}/.config/agent-sandbox/policy.json` (optional, mounted as read-only)

**Firewall Rules:**
- DNS (UDP port 53) - Always allowed for resolution
- SSH (TCP port 22) - Always allowed for git operations
- Localhost - Always allowed for inter-process communication
- Host network (`.0/24`) - Auto-detected from container's default route
- Configured domains - Resolved via DNS, IPs added to ipset
- GitHub service - IP ranges fetched from `api.github.com/meta` and added to ipset
- Default: DROP all other outbound traffic

## Webhooks & Callbacks

**Incoming:**
- None configured

**Outgoing:**
- None configured

---

*Integration audit: 2026-03-23*
