# Project Research Summary

**Project:** Agent Sandbox
**Domain:** Container-based AI coding agent sandbox with proxy egress control
**Researched:** 2026-03-24
**Confidence:** HIGH

## Executive Summary

Agent Sandbox is a local, self-hosted Docker-based sandbox for running AI coding agents (Claude Code, GitHub Copilot, etc.) safely on a developer's own machine. The project is mid-pivot: the existing per-container iptables approach (`init-firewall.py`) is being replaced by a shared Squid proxy architecture. Research confirms this is the correct direction. The iptables approach requires `NET_ADMIN` capability per container, resolves domain names to IPs at startup (which go stale on CDN-based hosts), and does not compose cleanly across multiple simultaneous sandboxes. The Squid proxy on a Docker internal network eliminates all three problems: no elevated capabilities needed in sandbox containers, hostname-based matching stays current, and a single ACL file governs every sandbox simultaneously.

The recommended architecture uses two Docker networks: `sandbox-internal` (with `internal: true`, no direct internet) and `sandbox-external` (normal bridge). Sandbox containers join only the internal network and route all traffic through `HTTP_PROXY`/`HTTPS_PROXY` env vars pointing at the Squid container, which straddles both networks. Squid enforces a `dstdomain` allowlist without SSL inspection — it reads the CONNECT tunnel destination hostname directly, which is sufficient for domain-level egress control without the CA cert distribution complexity of SSL-bump. mise manages language runtimes inside containers and orchestrates the sandbox lifecycle on the host.

The key risks are well-documented and avoidable. The most dangerous is a false sense of completeness: proxy enforcement looks correct but package managers (npm, cargo, go, git) may bypass it entirely via direct connections. This must be verified by watching Squid access logs during installs, not by spot-checking agent behavior. The migration from iptables to proxy must be a clean cutover — running both simultaneously causes Docker DNS NAT corruption. The proxy startup race (sandbox starts before Squid is ready) must be closed with a real health check and `service_healthy` condition, not a sleep.

## Key Findings

### Recommended Stack

The existing base image (Debian bookworm-slim, non-root `dev` user at UID/GID 500, gosu for entrypoint UID adjustment) is already the right choice. No change needed there. The pivot is replacing the iptables-based `init-firewall.py` with a Squid 5.7 proxy container built from Debian bookworm (consistent base image; alternatively `ubuntu/squid:5.2-22.04_beta` from Canonical). Docker Compose v2 manages the dual-network topology and service lifecycle. mise on the host replaces justfile for task orchestration, extending naturally from its existing use inside the Claude agent image.

**Core technologies:**
- Debian bookworm-slim: sandbox container base — glibc compatibility, good package availability, validated in codebase
- Squid 5.7 (bookworm apt): shared egress proxy — explicit forward proxy with `dstdomain` ACL, no SSL-bump needed
- Docker Compose v2: multi-container orchestration — dual-network topology, `depends_on` health checks
- mise (host + container): runtime management and task runner — already in use, extends to all runtimes and lifecycle tasks
- Node 22 LTS, Python 3.13, Go 1.24, Rust stable, Bun 1.2, uv 0.6.x: language runtimes inside sandbox via mise

### Expected Features

The research is clear about what belongs in v1 versus later. The core architectural pivot (Squid proxy) is the single most important deliverable; everything else is blocked or enabled by getting that right first.

**Must have (table stakes):**
- Container isolation per agent run — baseline safety unit
- Non-root user execution — already implemented
- Network egress control via Squid proxy — the core pivot
- Read-only rootfs with writable tmpfs — filesystem immutability
- Capability dropping (`--cap-drop=ALL`, `--security-opt=no-new-privileges`) — removes NET_ADMIN after migration
- Resource limits (CPU, memory, PIDs) and execution timeouts — runaway prevention
- Workspace bind mount and credential isolation — already partially implemented
- Ephemeral sandbox lifecycle — clean slate per agent run
- Full language runtime suite via mise — agents need these pre-installed
- Package cache volumes (npm, pip, cargo, go) — significant latency reduction across runs
- Stdout/stderr capture — minimum observability

**Should have (competitive):**
- Shared Squid proxy enabling simultaneous multi-sandbox routing — key differentiator over iptables approach
- mise task orchestration on host (`proxy:start`, `sandbox:run`) — cohesive operator experience
- Policy-as-file allowlist (externalized `allowlist.txt`) — update egress policy without image rebuild
- LSP tooling (rust-analyzer, pyright, tsserver) — agent code intelligence
- Filesystem diff logging — audit what agent changed
- Published pre-built image to GHCR — zero-build onboarding

**Defer (v2+):**
- CLI tool replacing mise tasks — premature abstraction; prove mise insufficient first
- Per-project Squid ACL profiles — wait for multi-project user demand
- Structured audit/event log — defer until compliance use case emerges

### Architecture Approach

The architecture centers on a dual-network Docker topology enforced entirely at the Docker layer, not inside containers. Sandbox containers join only `sandbox-internal` (internal: true), gaining no default route to the internet. The Squid container joins both networks and is the sole path from internal to external. This design removes `NET_ADMIN` from sandbox containers entirely, centralizes egress policy in one ACL file, and scales to N concurrent sandboxes with no per-sandbox configuration. Sandbox startup flow: host runs `mise run sandbox:start` → Compose brings up proxy (if not running), waits for health check → sandbox container starts, entrypoint aligns UID/GID, drops to dev user, routes all traffic via `HTTP_PROXY`.

**Major components:**
1. Squid proxy container (`images/proxy/`) — egress gateway, ACL enforcement, access logging; long-running, shared across all sandboxes
2. sandbox-internal Docker network — isolates sandbox containers from direct internet; `internal: true` enforced by Docker
3. sandbox-external Docker network — internet-accessible bridge; only Squid container joins this
4. Base sandbox image (`images/base/`) — Debian bookworm, dev user, entrypoint UID/GID alignment; `init-firewall.py` removed
5. Agent image layers (`images/agents/claude`, `images/agents/copilot`) — extend base with agent CLI, mise runtimes, per-agent policy
6. config/allowlist.txt — externalised domain allowlist; mounted into proxy; policy changes via `squid -k reconfigure` without image rebuild
7. mise.toml (host) — task orchestration for proxy and sandbox lifecycle

### Critical Pitfalls

1. **Package managers bypassing proxy silently** — `HTTP_PROXY` env alone is insufficient. npm, cargo, git, go all require additional per-tool config (`.npmrc`, `.cargo/config.toml`, `git config http.proxy`, `GOPROXY`). Set both case variants (`HTTP_PROXY` and `http_proxy`). Verify by watching Squid access logs during a full `npm install` and `cargo build`, not by checking agent success.

2. **Proxy startup race** — `depends_on` without `condition: service_healthy` only waits for container process start, not Squid ready-to-accept. Add a health check that makes a proxied request through Squid and use `service_healthy` condition. Without this, cold-start sandbox failures appear intermittently and are hard to diagnose.

3. **mise runtimes hidden by volume mount** — building runtimes into the image via normal `mise install` then mounting `mise-state:/home/dev/.mise` at runtime shadows the pre-installed tools. Use `mise install --system` in the Dockerfile (system path `/usr/local/share/mise/installs` is not shadowed by home directory volume mounts). Test with a freshly-removed named volume.

4. **iptables migration conflict** — running `init-firewall.py` alongside proxy-based egress corrupts Docker's embedded DNS NAT rules, breaking `squid` hostname resolution inside sandbox containers. Migration must be a clean cutover: remove `init-firewall.py` from entrypoints, drop `NET_ADMIN`, rebuild image. Verify with `getent hosts squid` inside sandbox as the first post-migration test.

5. **Proxy config writability** — if Squid config is mounted into sandbox containers (even read-only), a confused agent could attempt to modify it if the mount is accidentally `rw`. Never mount proxy config into sandbox containers at all. Mount credentials and workspace only.

## Implications for Roadmap

The research reveals a clear dependency sequence: proxy infrastructure must be solid before runtime installation, and runtime installation must be solid before agent-layer work. This is not arbitrary sequencing — each phase blocks the next.

### Phase 1: Proxy Foundation

**Rationale:** Everything depends on egress control being correct. This is the core architectural pivot and must be done first in isolation so it can be validated before anything else is added. Getting this wrong and discovering it later (during agent testing) is expensive to diagnose.
**Delivers:** Working Squid proxy container with dual-network Docker topology, domain allowlist ACL, health check, access logging, and explicit architectural decision to not use SSL-bump.
**Addresses:** Network egress control (table stakes), shared Squid proxy for multi-agent routing (differentiator), policy-as-file allowlist.
**Avoids:** Pitfall 2 (no SSL-bump, documented as ADR in squid.conf), Pitfall 3 (health check wired here, not later), Pitfall 7 (proxy config mounted read-only, sandbox containers never see it).
**Research flag:** Standard patterns — Squid explicit forward proxy with `dstdomain` ACL is well-documented. Skip research-phase for this phase.

### Phase 2: Migration — Remove iptables, Wire Sandbox to Proxy

**Rationale:** Base image must be refactored before agent layers are built on it. Removing `init-firewall.py` and `NET_ADMIN` is the migration step that commits to the new architecture. Do this as a discrete phase so the clean cutover is explicit and can be verified.
**Delivers:** Updated base image without `init-firewall.py`, sandbox containers joining `sandbox-internal` only, `HTTP_PROXY`/`HTTPS_PROXY` env vars set, `NO_PROXY` set correctly, `--cap-drop=ALL` and `--security-opt=no-new-privileges` active, `--read-only` + tmpfs.
**Uses:** Debian bookworm-slim base, Docker Compose dual-network config from Phase 1.
**Avoids:** Pitfall 6 (clean cutover; verify DNS resolution immediately), Pitfall 3 (`NO_PROXY` for localhost set here).
**Research flag:** Standard patterns — entrypoint UID/GID alignment, capability dropping, read-only rootfs all have established Docker patterns.

### Phase 3: Language Runtime Installation

**Rationale:** Agent images layer on top of the base. Runtimes must be stable before agent-specific images are built. This is also where the mise volume-shadowing pitfall lives — it must be resolved here, not discovered during agent testing.
**Delivers:** Full language runtime suite (Node 22, Python 3.13, Go 1.24, Rust stable, Bun, uv) installed via `mise install --system` in the Dockerfile. Package cache volumes (npm, pip, cargo, go) defined in Compose. Verified with fresh volume removal test.
**Uses:** mise for all runtimes, named Docker volumes for cache persistence.
**Avoids:** Pitfall 5 (system install path; fresh volume test gates completion of this phase).
**Research flag:** mise Docker cookbook (`mise install --system`) is documented. No research-phase needed, but fresh-volume test is mandatory gate.

### Phase 4: Per-Package-Manager Proxy Integration

**Rationale:** Proxy enforcement requires tool-specific configuration beyond env vars. This is isolated as its own phase because it is the highest-risk integration concern — tools silently bypassing the proxy is not detectable without active log verification. Must happen before agent-layer work or the security guarantee is unverified.
**Delivers:** npm proxy config in `.npmrc`, cargo proxy config in `.cargo/config.toml`, `git config http.proxy` in image Dockerfile, `GOPROXY` set correctly, both case variants of proxy env vars. Squid access log verified to show entries from each package manager during install.
**Avoids:** Pitfall 4 (per-package-manager verification via Squid access logs is the completion gate).
**Research flag:** Integration gotchas are documented in PITFALLS.md with specific config per tool. No research-phase needed — implementation is mechanical but requires log verification.

### Phase 5: Agent Image Layers and Hardening

**Rationale:** Claude and Copilot image layers build on a verified proxy+runtime base. Resource limits, seccomp, and execution timeout are added here as the final security baseline layer. Multi-agent concurrency testing belongs here because it depends on both proxy and runtimes being stable.
**Delivers:** Claude and Copilot agent images, resource limits (CPU, memory, PID), execution timeout, seccomp profile (default Docker, then tune), stdout/stderr capture. Multi-sandbox concurrency tested (3+ simultaneous agents).
**Addresses:** All P1 features from FEATURES.md completed here; security baseline closed.
**Avoids:** Pitfall 1 (threat model documented in SECURITY.md — CONNECT scope, not content), Pitfall 8 (DNS tunneling position documented as accepted risk or mitigated).
**Research flag:** Standard Docker hardening patterns. Seccomp custom profile may need research-phase if default profile proves too restrictive for agent workloads.

### Phase 6: Observability and Publishing

**Rationale:** Once the sandbox is functionally correct and security-hardened, add the observability and distribution features that increase adoption. These have no dependency on Phase 5 correctness beyond "it works."
**Delivers:** Filesystem diff logging, LSP tooling (rust-analyzer, pyright, tsserver), published GHCR image with stable tag strategy, GitHub Actions CI for build+publish.
**Addresses:** P2 features from FEATURES.md.
**Research flag:** LSP tooling installation via mise backends may need a quick research-phase to confirm rust-analyzer aqua/cargo backend compatibility with the system install path pattern.

### Phase Ordering Rationale

- Phases 1-2 are the architectural pivot. Both must complete before anything else because the proxy network is the foundation everything runs on.
- Phase 3 before Phase 4: runtimes must be installed before their proxy behavior can be verified.
- Phase 4 before Phase 5: proxy enforcement must be verified before agent images are considered correct.
- Phase 5 before Phase 6: no point publishing or adding observability to an unverified security baseline.
- The iptables removal is a discrete gate in Phase 2 — not spread across phases — because dual enforcement causes immediate breakage (Docker DNS corruption).

### Research Flags

Phases needing deeper research during planning:
- **Phase 5 (seccomp profile tuning):** Default Docker seccomp may block syscalls that Claude Code or Copilot agents require. Needs profiling against real agent workloads. Start with default; tune if agents fail unexpectedly.
- **Phase 6 (LSP tooling):** rust-analyzer and pyright installation via mise system path needs verification. Depends on aqua or cargo backends behaving correctly with `--system`.

Phases with standard patterns (skip research-phase):
- **Phase 1:** Squid explicit forward proxy with `dstdomain` is canonical, well-documented.
- **Phase 2:** Docker capability dropping, read-only rootfs, entrypoint patterns are standard.
- **Phase 3:** mise Docker cookbook explicitly covers the system install path pattern.
- **Phase 4:** Package manager proxy configs are documented in PITFALLS.md with specific directives.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | Core stack (Debian, Squid, Docker Compose, mise) verified against official sources and existing codebase. Squid config pattern cross-validated via community + official docs. |
| Features | HIGH | Multiple current sources (2025-2026) on agent sandbox products. Table stakes and differentiators consistent across sources. |
| Architecture | HIGH | Dual-network Docker topology is a documented, production-proven pattern. Data flow and component responsibilities derived from official Compose and Squid docs. |
| Pitfalls | HIGH | Critical pitfalls verified against official Docker docs, official Squid wiki, npm bug tracker, and real-world implementation reports. |

**Overall confidence:** HIGH

### Gaps to Address

- **DNS tunneling mitigation:** Whether to mitigate (block outbound UDP/53 from sandbox containers) or document as accepted risk. Decision should be made during Phase 5 hardening. Research confirms it is a real channel; whether it is in scope for this threat model is a product decision, not a technical unknown.
- **npm proxy env var behavior across versions:** npm's handling of `HTTP_PROXY` varies across versions (npm/cli#6930). The workaround (explicit `.npmrc` config) is clear; the specific npm version in use should be pinned and verified during Phase 4.
- **Squid cache tuning for multi-agent workloads:** Disk cache behavior under 3+ simultaneous agents doing heavy installs is flagged as a performance trap. Start with `cache deny all` (recommended in STACK.md for freshness) and add `cache_mem` tuning only if performance becomes an issue during Phase 5 concurrency testing.

## Sources

### Primary (HIGH confidence)
- Squid ACL documentation — https://wiki.squid-cache.org/SquidFaq/SquidAcl
- Squid HTTPS/CONNECT documentation — https://wiki.squid-cache.org/Features/HTTPS
- Docker seccomp profiles — https://docs.docker.com/engine/security/seccomp/
- Docker Compose networking — https://docs.docker.com/compose/how-tos/networking/
- Docker proxy env vars — https://docs.docker.com/engine/cli/proxy/
- Docker Compose startup ordering — https://docs.docker.com/compose/how-tos/startup-order/
- Docker network/firewall iptables — https://docs.docker.com/engine/network/firewall-iptables/
- ubuntu/squid Docker Hub — https://hub.docker.com/r/ubuntu/squid (Canonical official)
- Debian bookworm squid package — https://packages.debian.org/bookworm/squid
- mise documentation — https://mise.jdx.dev/
- mise Docker cookbook — https://mise.jdx.dev/mise-cookbook/docker.html
- Existing codebase (`images/base/Dockerfile`, `images/agents/claude/Dockerfile`, `docker-compose.yml`, `images/base/init-firewall.py`)

### Secondary (MEDIUM confidence)
- [jimangel.io: Restrict Container Internet Access with Squid Proxy](https://www.jimangel.io/posts/docker-block-internet-squid-proxy) — dual-network topology pattern
- [INNOQ: Dev Sandbox Network for AI Coding Agents (2026-03)](https://www.innoq.com/en/blog/2026/03/dev-sandbox-network/) — nftables + explicit proxy, config immutability, DNS gap
- [Squid security best practice config](https://github.com/password123456/setup-squid-proxy-with-security-best-practice) — ACL patterns, cross-validated with official docs
- [Modal: Top AI Code Sandbox Products in 2025](https://modal.com/blog/top-code-agent-sandbox-products) — feature matrix
- [Northflank: Best code execution sandbox for AI agents 2026](https://northflank.com/blog/best-code-execution-sandbox-for-ai-agents) — feature analysis
- [Pere Villega: I Built Yet Another Sandbox](https://perevillega.com/posts/2026-03-03-ai-sandbox-coding-agents/) — local self-hosted gaps vs cloud
- [Daniel Demmel: Coding Agents in Secured VS Code Dev Containers](https://www.danieldemmel.me/blog/coding-agents-in-secured-vscode-dev-containers) — devcontainer security

### Tertiary (LOW confidence)
- npm proxy env var bug — [npm/cli#6930](https://github.com/npm/cli/issues/6930) — specific npm version behavior; validate against pinned version during Phase 4

---
*Research completed: 2026-03-24*
*Ready for roadmap: yes*
