# Agent Sandbox

## What This Is

A locked-down container image and orchestration toolkit for running AI coding agents (Claude Code, Copilot, etc.) safely on local machines. Provides a fully-featured Debian-based development environment with controlled network egress via a shared Squid proxy, hardened filesystem access via bind mounts, and process-level security restrictions. Multiple sandbox instances can run simultaneously, all routing through a single central proxy container.

## Core Value

Agents can fetch anything they need from the web (packages, docs, APIs) but cannot exfiltrate data to unauthorized destinations — enforced at the network layer, not by trusting the agent.

## Requirements

### Validated

<!-- Shipped and confirmed valuable. Inferred from existing codebase. -->

- ✓ Debian bookworm base image with common dev tools (git, curl, ripgrep, jq, neovim, tmux, fzf, build-essential, cmake) — existing
- ✓ Non-root user execution (dev user, uid/gid 500) — existing
- ✓ Network egress control via shared Squid proxy with domain allowlist ACL — Phase 1
- ✓ SNI peek/splice for HTTPS hostname verification without TLS decryption — Phase 1
- ✓ Multiple sandbox instances routing through single Squid proxy — Phase 1
- ✓ Dual-network Docker topology (internal + external) — Phase 1
- ✓ Agent-specific image layers (Claude, Copilot) extending base — existing
- ✓ Volume mounting strategy (workspace bind mount, credential volumes, cache volumes) — existing
- ✓ Docker Compose orchestration mode — existing
- ✓ Devcontainer support for VS Code — existing
- ✓ Build automation via Python script (images/build.py) — existing
- ✓ Shell environment (zsh + powerlevel10k, git-delta, fzf integration) — existing
- ✓ UID/GID adjustment to match host workspace ownership — existing
- ✓ Read-only rootfs with writable tmpfs for /tmp and /run — Phase 2
- ✓ cap_drop=ALL (SETUID/SETGID retained for gosu) + no-new-privileges — Phase 2
- ✓ Default seccomp profile active — Phase 2
- ✓ Configurable resource limits (CPU, memory, PID) via env vars — Phase 2
- ✓ Full language runtime suite via mise: Node, Python, Go, Rust 1.94.x, uv, Bun 1.3.x — Phase 3
- ✓ LSP tooling: rust-analyzer, pyright, typescript-language-server — Phase 3
- ✓ mise tasks for sandbox lifecycle (proxy:start/stop, sandbox:build/run/stop) — Phase 3
- ✓ Package cache volumes (npm, pip, go) persisting across runs — Phase 3
- ✓ Per-package-manager proxy config (.npmrc, cargo, git, GOPROXY) — Phase 3
- ✓ Multi-sandbox support via named instances — Phase 3

### Active

<!-- Current scope. Building toward these. -->
- [ ] Published container image (Docker Hub / GHCR) in addition to local build
- [ ] Execution timeouts for sandbox runs
- [ ] Observability: stdout/stderr capture, filesystem diff logging

### Out of Scope

<!-- Explicit boundaries. -->

- Full VM-based isolation — containers are sufficient for this threat model, VMs add too much overhead
- Network ingress lockdown in v1 — agents need to fetch web resources freely (outbound HTTP/HTTPS allowed through proxy)
- Kubernetes orchestration — this is a local development tool, not a cluster workload
- GUI/web dashboard — CLI and mise tasks are the interface
- Agent framework integration (LangChain sandboxes, Modal) — this is infrastructure-level, not framework-level

## Context

The existing codebase has a working iptables/ipset-based firewall approach that controls egress per-container. The new direction moves egress control to a shared Squid proxy container, which is architecturally cleaner for multi-agent scenarios — one proxy serves all sandboxes, one place to manage ACLs.

The existing Docker artifacts (base image, agent images, build script, compose file, firewall script) should be evaluated for reuse. The base Dockerfile and volume strategy are solid foundations. The iptables firewall approach will be replaced by proxy-based egress, but the policy-as-JSON concept can evolve into Squid ACL configuration.

Research reference: `docs/research.md` — comprehensive survey of sandbox patterns, container hardening, and proxy approaches.
Tooling reference: `docs/mise.reference.md` — mise is used for both runtime version management inside the container and task orchestration on the host.

## Constraints

- **Base image**: Debian bookworm slim — balance of size and package availability
- **Proxy**: Squid in a separate long-running container, shared across sandboxes via Docker network
- **Orchestration**: mise tasks initially, potential CLI tool later if complexity warrants
- **Distribution**: Both pre-built image (registry) and buildable from source
- **Capabilities**: Containers need NET_ADMIN only if iptables fallback is needed; proxy-based approach may eliminate this requirement
- **Host compatibility**: Linux native, macOS via Colima/Docker Desktop, Windows via Docker Desktop

## Key Decisions

<!-- Decisions that constrain future work. -->

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Squid proxy over iptables for egress | Centralized control for multi-agent, easier ACL management, no per-container NET_ADMIN needed | — Pending |
| Shared proxy (not sidecar) | One proxy for N sandboxes, simpler than N sidecars, single ACL config | — Pending |
| Debian slim over Alpine | Better package compatibility, agents expect glibc environment | — Pending |
| mise for runtimes + orchestration | Already in use for agent tooling, extends naturally to host-side tasks | — Pending |
| Evaluate existing Docker artifacts | Keep what works (base image structure, volume strategy), replace what changes (firewall → proxy) | — Pending |

---
*Last updated: 2026-03-24 after Phase 3 completion*
