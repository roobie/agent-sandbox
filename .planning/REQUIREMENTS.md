# Requirements: Agent Sandbox

**Defined:** 2026-03-24
**Core Value:** Agents can fetch anything they need from the web but cannot exfiltrate data to unauthorized destinations — enforced at the network layer, not by trusting the agent.

## v1 Requirements

Requirements for initial release. Each maps to roadmap phases.

### Proxy & Egress Control

- [x] **PROXY-01**: Squid proxy runs as a standalone long-running container, separate from sandbox containers
- [x] **PROXY-02**: Squid enforces domain-based egress allowlist via dstdomain ACLs loaded from a config file
- [x] **PROXY-03**: Squid uses SNI peek/splice to verify HTTPS destination hostnames without TLS decryption (no CA cert needed)
- [x] **PROXY-04**: Multiple sandbox containers route through the single Squid proxy simultaneously via shared Docker network
- [x] **PROXY-05**: Sandbox containers join an internal Docker network (no direct internet); only the proxy bridges to external
- [x] **PROXY-06**: Sandbox containers use HTTP_PROXY/HTTPS_PROXY env vars pointing at the Squid proxy
- [x] **PROXY-07**: Proxy container has a health check; sandbox containers wait for proxy to be healthy before starting

### Container Hardening

- [x] **HARD-01**: Sandbox containers run with read-only rootfs and writable tmpfs for /tmp
- [x] **HARD-02**: Sandbox containers run with --cap-drop=ALL and --security-opt=no-new-privileges
- [x] **HARD-03**: Sandbox containers use Docker's default seccomp profile (custom tuning deferred)
- [x] **HARD-04**: Resource limits (CPU, memory, PID) are configurable per sandbox run

### Development Environment

- [ ] **DEVENV-01**: Base image is Debian bookworm slim with common dev tools (git, curl, ripgrep, jq, neovim, tmux, fzf, build-essential, cmake)
- [ ] **DEVENV-02**: Language runtimes installed via mise: Node (latest LTS), Python (3.12+), Go (latest), Rust 1.94.x, uv 0.10.x, Bun 1.3.x, rust-analyzer (latest)
- [ ] **DEVENV-03**: Runtimes installed via `mise install --system` so they survive volume mount shadowing of home directory
- [ ] **DEVENV-04**: Package cache volumes (npm, pip, cargo, go modules) persist across sandbox runs
- [ ] **DEVENV-05**: LSP tooling pre-installed: rust-analyzer, pyright, typescript-language-server
- [ ] **DEVENV-06**: Non-root user execution (dev user) with UID/GID adjustment to match host workspace ownership
- [ ] **DEVENV-07**: Per-package-manager proxy configuration: .npmrc, cargo config.toml, git config, GOPROXY env var

### Orchestration

- [ ] **ORCH-01**: mise tasks on host for proxy lifecycle: `mise run proxy:start`, `mise run proxy:stop`, `mise run proxy:status`
- [ ] **ORCH-02**: mise tasks on host for sandbox lifecycle: `mise run sandbox:build`, `mise run sandbox:run`, `mise run sandbox:stop`
- [ ] **ORCH-03**: mise tasks support running multiple named sandbox instances simultaneously
- [ ] **ORCH-04**: Workspace bind-mounted from host directory into container at /workspace

### Observability

- [ ] **OBS-01**: Agent stdout/stderr captured via Docker logs
- [ ] **OBS-02**: Filesystem diff logging: docker diff for container changes + git diff for workspace changes, captured at sandbox stop
- [ ] **OBS-03**: Squid access logs available for auditing which domains agents accessed

### Distribution

- [ ] **DIST-01**: Container images published to GHCR via CI/CD pipeline
- [ ] **DIST-02**: Images also buildable from source via mise task (`mise run image:build`)
- [ ] **DIST-03**: Existing Docker artifacts evaluated and either reused or replaced (not left orphaned)

### Migration

- [x] **MIG-01**: Existing init-firewall.py and iptables approach completely removed (not left dormant)
- [x] **MIG-02**: NET_ADMIN and NET_RAW capabilities removed from sandbox containers

## v2 Requirements

Deferred to future release. Tracked but not in current roadmap.

### Advanced Hardening

- **HARD-05**: Custom seccomp profile tuned to actual agent syscall usage
- **HARD-06**: Execution timeouts configurable per sandbox run

### Advanced Orchestration

- **ORCH-05**: CLI tool replacing mise tasks if complexity warrants
- **ORCH-06**: Per-project Squid ACL profiles for different egress needs
- **ORCH-07**: Devcontainer support maintained alongside mise task mode

### Advanced Observability

- **OBS-04**: Structured audit log (JSON events) for compliance/review workflows
- **OBS-05**: Real-time filesystem change monitoring via inotifywait

## Out of Scope

| Feature | Reason |
|---------|--------|
| VM-based isolation (gVisor/Kata/Firecracker) | Containers + seccomp + cap-drop sufficient for local dev threat model; VMs add 3-10x startup overhead |
| Kubernetes orchestration | This is a local development tool, not a cluster workload |
| GUI / web dashboard | CLI and mise tasks are the right interface for developer audience |
| Agent framework integration (LangChain, Modal) | Infrastructure-layer, not framework-layer; avoid coupling |
| MITM TLS inspection (ssl-bump) | Breaks certificate pinning in npm/pip/cargo/SDKs; SNI peek/splice sufficient |
| Full network disable (--network=none) | Renders agent workflows unusable (can't fetch packages/docs/APIs) |
| Per-container sidecar proxy | N proxies = N configs; shared proxy is architecturally cleaner |
| Long-lived persistent workspaces | State accumulation causes reproducibility problems; ephemeral containers + cache volumes only |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| PROXY-01 | Phase 1 | Complete |
| PROXY-02 | Phase 1 | Complete |
| PROXY-03 | Phase 1 | Complete |
| PROXY-04 | Phase 1 | Complete |
| PROXY-05 | Phase 1 | Complete |
| PROXY-06 | Phase 1 | Complete |
| PROXY-07 | Phase 1 | Complete |
| MIG-01 | Phase 1 | Complete |
| MIG-02 | Phase 1 | Complete |
| HARD-01 | Phase 2 | Complete |
| HARD-02 | Phase 2 | Complete |
| HARD-03 | Phase 2 | Complete |
| HARD-04 | Phase 2 | Complete |
| DEVENV-01 | Phase 3 | Pending |
| DEVENV-02 | Phase 3 | Pending |
| DEVENV-03 | Phase 3 | Pending |
| DEVENV-04 | Phase 3 | Pending |
| DEVENV-05 | Phase 3 | Pending |
| DEVENV-06 | Phase 3 | Pending |
| DEVENV-07 | Phase 3 | Pending |
| ORCH-01 | Phase 3 | Pending |
| ORCH-02 | Phase 3 | Pending |
| ORCH-03 | Phase 3 | Pending |
| ORCH-04 | Phase 3 | Pending |
| OBS-01 | Phase 4 | Pending |
| OBS-02 | Phase 4 | Pending |
| OBS-03 | Phase 4 | Pending |
| DIST-01 | Phase 4 | Pending |
| DIST-02 | Phase 4 | Pending |
| DIST-03 | Phase 4 | Pending |

**Coverage:**
- v1 requirements: 30 total
- Mapped to phases: 30
- Unmapped: 0 ✓

---
*Requirements defined: 2026-03-24*
*Last updated: 2026-03-24 after roadmap creation*
