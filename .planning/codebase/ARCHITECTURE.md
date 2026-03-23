# Architecture

**Analysis Date:** 2026-03-23

## Pattern Overview

**Overall:** Layered sandbox architecture with pluggable security policies

Agent Sandbox implements a **security-first, composable design** for running AI coding agents (Claude Code, Copilot, etc.) in network-restricted containers. The architecture separates concerns into three distinct layers:

1. **Base image layer** - Common runtime, firewall infrastructure
2. **Agent-specific layer** - Agent CLI tools and policies
3. **Runtime mode layer** - Container orchestration (Compose or Devcontainer)

**Key Characteristics:**
- **Defense-in-depth**: Network restriction enforced via iptables/ipset at container startup, cannot be bypassed from within
- **Policy-as-code**: Network policies stored as JSON files, reviewable and version-controlled
- **Reproducibility**: Images pinned by digest, deterministic builds via Python script
- **Agent-agnostic**: Core infrastructure supports any agent type through inheritance and policy overrides

## Layers

**Firewall & Foundation Layer:**
- Purpose: Initialize and enforce network access control via iptables/ipset rules
- Location: `images/base/init-firewall.py`
- Contains: Python firewall initialization script with IP/CIDR management, DNS resolution
- Depends on: System iptables, ipset, curl, DNS
- Used by: All container entry points (both Compose and Devcontainer modes)

**Base Image Layer:**
- Purpose: Provide Debian-based runtime with development tools and firewall initialization
- Location: `images/base/Dockerfile`, `images/base/entrypoint.sh`, `images/base/policy.json`
- Contains: System dependencies (git, curl, tmux, zsh, neovim), firewall tools (iptables, ipset), development utilities (ripgrep, jq, gdb, valgrind)
- Depends on: debian:bookworm, zsh-in-docker plugin system, git-delta releases
- Used by: Agent-specific images (extends via FROM)

**Agent-Specific Image Layer:**
- Purpose: Add agent CLI tools, alias shortcuts, and agent-specific network policies
- Locations:
  - Claude agent: `images/agents/claude/Dockerfile`, `images/agents/claude/policy.json`
  - Copilot agent: `images/agents/copilot/Dockerfile`, `images/agents/copilot/policy.json`
- Contains: Agent CLI installation (via mise), shell aliases, per-agent policies with required domains
- Depends on: Base image, mise package manager
- Used by: Runtime modes (Compose or Devcontainer)

**Runtime Mode Layer:**
- Purpose: Orchestrate container execution with appropriate volumes and configuration
- Locations:
  - Compose: `docker-compose.yml` (project root and templates)
  - Devcontainer: `.devcontainer/devcontainer.json`, `.devcontainer/Dockerfile`, `.devcontainer/policy.json`
- Contains: Volume mounts (workspace, credentials, history), environment variables, capability grants (NET_ADMIN, NET_RAW)
- Depends on: Agent-specific image
- Used by: User (docker compose exec or VS Code)

**Devcontainer Wrapper (VS Code):**
- Purpose: Bridge VS Code IDE to sandboxed container, trigger firewall initialization in postStartCommand
- Location: `.devcontainer/`
- Contains: VS Code-specific settings, entrypoint (postStartCommand), devcontainer.json configuration
- Depends on: VS Code Dev Containers extension, Claude agent base image
- Used by: VS Code IDE only

## Data Flow

**Container Startup (Compose Mode):**

1. Docker Compose launches container from `agent-sandbox-claude:local` image
2. Entrypoint script (`entrypoint.sh`) runs as root
3. Firewall check: Is `allowed-domains` ipset already created?
   - NO → Run `init-firewall.py` with policy file at `/etc/agent-sandbox/policy.json`
   - YES → Skip firewall init (idempotent)
4. `init-firewall.py` executes in sequence:
   - Load and validate policy JSON
   - Flush existing iptables rules (preserving Docker DNS rules)
   - Create ipset `allowed-domains`
   - For each service (e.g., "github"): fetch IP ranges from GitHub API, add to ipset
   - For each domain: resolve via DNS, add IPs to ipset
   - Detect host network via `ip route`, add host network to ipset
   - Apply iptables default-DROP policies (INPUT/FORWARD/OUTPUT)
   - Add allow rules: DNS (53), SSH (22), localhost (lo), established connections, ipset matches
   - Verify firewall: block example.com, allow at least one configured endpoint
5. Adjust container user UID/GID to match host workspace
6. Drop privileges, start shell as `dev` user

**Container Startup (Devcontainer Mode):**

1. VS Code Dev Containers creates container from `.devcontainer/Dockerfile`
2. VS Code bypasses entrypoint script
3. Container initializes with standard base image entrypoint (for UID/GID adjustment only, firewall skipped)
4. Once shell is ready, VS Code runs `postStartCommand`: `sudo /usr/local/bin/init-firewall.py`
5. Firewall initialization proceeds as above
6. Agent is ready for use

**Network Request Flow:**

1. Process inside container attempts outbound connection (e.g., curl to api.github.com)
2. iptables OUTPUT chain matches:
   - Established connection? → ACCEPT (state tracking)
   - DNS port 53? → ACCEPT (required for DNS)
   - SSH port 22? → ACCEPT
   - Localhost? → ACCEPT
   - IP in allowed-domains ipset? → ACCEPT
   - Else → REJECT (icmp-admin-prohibited)
3. If allowed, connection proceeds; if rejected, user sees immediate connection failure

**State Management:**

- **Policy state**: Stored in image layer as `/etc/agent-sandbox/policy.json` (baked into image) or mounted at runtime from `~/.config/agent-sandbox/policy.json` (host machine)
- **Credentials state**: Stored in Docker volume, persists across container restarts (`claude-state` volume)
- **Shell history**: Stored in Docker volume (`command-history` volume)
- **Tool state**: mise (version manager) state in volumes for reproducible development environment

## Key Abstractions

**Policy Schema:**
- Purpose: Declare allowed outbound network targets in JSON format
- Examples: `images/base/policy.json`, `images/agents/claude/policy.json`, `.devcontainer/policy.json`
- Pattern: Two-field object with `services` array (e.g., "github") and `domains` array (e.g., "api.anthropic.com")
  - Services: Dynamic IP range fetching from well-known APIs (GitHub IP ranges)
  - Domains: Static FQDN list, resolved to IPs at firewall startup
- Schema validation: `init-firewall.py` validates structure before use

**Image Build Hierarchy:**
- Purpose: Share common base while allowing agent-specific customizations
- Pattern: Python build script orchestrates multi-stage Docker builds
  - `build.py` calls `docker build` with appropriate build args
  - Base image built first, then agent images extend it via ARG BASE_IMAGE
  - Policy inheritance: Each layer overrides `/etc/agent-sandbox/policy.json`

**Firewall Initialization Pipeline:**
- Purpose: Modular, idempotent network enforcement
- Pattern: `init-firewall.py` functions execute in strict order:
  1. `load_policy()` - Validate JSON structure
  2. `save_docker_dns_rules()` - Preserve Docker-internal DNS rules
  3. `flush_rules()` - Clean slate
  4. `restore_docker_dns()` - Re-add Docker DNS
  5. `setup_foundation_rules()` - Allow DNS, SSH, localhost
  6. `create_ipset()` - Create hash:net ipset
  7. `process_services()` - GitHub IPs
  8. `process_domains()` - Domain IPs
  9. `setup_host_network()` - Auto-detect and allow host network
  10. `apply_firewall_rules()` - Set default DROP, add ipset rules
  11. `verify_firewall()` - Smoke tests
- Idempotency: Entrypoint checks for existing ipset before re-running

**Volume Mounting Strategy:**
- Purpose: Isolate agent state while maintaining workspace access
- Pattern: Named volumes for credentials and history, bind mount for workspace
  - Workspace: Bind-mounted from host, read-write access for agent
  - Credentials: Named volume (survives container rebuild)
  - History: Named volume per-container (preserves shell history)
  - Host config: Optional bind-mount from `~/.claude/` (read-only)

## Entry Points

**Compose Mode Entry Point:**
- Location: `docker-compose.yml` (services.agent-sandbox)
- Triggers: `docker compose up -d && docker compose exec agent zsh`
- Responsibilities:
  - Start agent-sandbox-claude:local container
  - Mount workspace (cwd → /workspace)
  - Attach volumes for credentials, history, cache
  - Grant NET_ADMIN and NET_RAW capabilities
  - Run entrypoint.sh which initializes firewall, then starts zsh shell

**Devcontainer Entry Point:**
- Location: `.devcontainer/devcontainer.json` (postStartCommand)
- Triggers: VS Code "Reopen in Container" command
- Responsibilities:
  - Build Dockerfile from `.devcontainer/`
  - Mount workspace via VS Code internal mechanism
  - Mount volumes for credentials and history
  - Run postStartCommand: firewall initialization
  - Provide integrated terminal

**Claude Code Execution Entry Point:**
- Location: Shell aliases in agent image (`images/agents/claude/Dockerfile`)
- Triggers: User runs `claude` or `yolo-claude` from shell
- Responsibilities:
  - Invoke Claude Code CLI (installed via mise)
  - Set environment (CLAUDE_CONFIG_DIR=/home/dev/.claude)
  - Respect firewall restrictions for outbound API calls

**Firewall Verification Entry Point:**
- Location: `init-firewall.py` main() function, verify_firewall()
- Triggers: Every container startup (after initial firewall setup)
- Responsibilities:
  - Verify example.com is blocked
  - Verify at least one allowed endpoint is reachable
  - Exit non-zero if verification fails (blocks container startup)

## Error Handling

**Strategy:** Fail-fast with clear error messages. Firewall initialization must succeed before container is usable.

**Patterns:**

- **Policy validation errors** (invalid JSON, missing required fields):
  ```python
  # init-firewall.py
  if not isinstance(policy, dict):
    raise FirewallError("Policy must be a JSON object")
  ```
  Result: Script exits 1, container startup fails, user sees error in logs

- **DNS resolution errors** (domain not resolvable):
  ```python
  try:
    results = socket.getaddrinfo(domain, None, socket.AF_INET)
  except socket.gaierror as e:
    raise FirewallError(f"Failed to resolve {domain}: {e}")
  ```
  Result: Firewall init fails, container won't start (prevents misconfigured policy)

- **Firewall verification failures** (blocked domain reachable or allowed domain blocked):
  ```python
  if result.returncode == 0:  # Should have failed
    raise FirewallError(f"Firewall verification failed - was able to reach {VERIFY_BLOCKED_URL}")
  ```
  Result: Container startup aborted, error clearly states what went wrong

- **Idempotent reinitialize** (firewall already initialized):
  ```bash
  # entrypoint.sh
  if ! ipset list allowed-domains >/dev/null 2>&1; then
    /usr/local/bin/init-firewall.py  # Run
  else
    echo "Firewall already initialized."  # Skip
  fi
  ```
  Result: Safe to call entrypoint multiple times (dev-shell command reuses it)

- **Duplicate IP handling** (ipset add fails if already present):
  ```python
  try:
    run_cmd(["ipset", "add", IPSET_NAME, ip_or_cidr])
  except FirewallError as e:
    if "already" in msg and "added" in msg:
      return  # Silently ignore duplicates
    raise  # Re-raise other errors
  ```
  Result: Resilient to re-running, doesn't fail on harmless duplicates

## Cross-Cutting Concerns

**Logging:**
- Approach: Direct `print()` statements to stdout, captured by Docker logs
- Patterns:
  - `print(f"Using policy file: {path}")` - Initialization step
  - `print(f"  Adding {ip} for {domain}")` - Progress per domain
  - `print("Firewall verification passed...")` - Success confirmations
- Accessibility: User sees all log output via `docker logs` or VS Code output panel

**Validation:**
- CIDR validation: `validate_cidr()` ensures IPv4 network format via `ip_network()` parsing
- IPv4 validation: `validate_ipv4()` via `ip_address()` with version check
- Policy schema: JSON structure enforced before processing
- Firewall verification: Connectivity tests verify rules are actually applied

**Authentication:**
- Approach: Not handled by Agent Sandbox core; delegated to Claude Code
- Claude Code: Uses OAuth flow, credentials stored in volume at `~/.claude/`
- Host config: Optional host CLAUDE.md and settings.json mounted read-only, not modified by container
- Firewall policy: No authentication required; policy file is local configuration

**Network Isolation:**
- Default-DROP iptables policies: All traffic denied unless explicitly allowed
- Allow list enforcement via ipset: Fast lookup of permitted IPs/CIDRs
- DNS as exception: Port 53 always allowed (required for domain resolution)
- Host network auto-detection: `/24` network of default gateway automatically allowed (enables Docker to host communication)

---

*Architecture analysis: 2026-03-23*
