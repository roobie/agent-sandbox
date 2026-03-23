# Architecture Research

**Domain:** Container-based agent sandbox with shared proxy egress
**Researched:** 2026-03-24
**Confidence:** HIGH

## Standard Architecture

### System Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                          HOST MACHINE                               │
│                                                                     │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │                    sandbox-internal (Docker network)          │   │
│  │                    internal: true  (no direct internet)       │   │
│  │                                                               │   │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐        │   │
│  │  │  sandbox-1   │  │  sandbox-2   │  │  sandbox-N   │        │   │
│  │  │  (claude)    │  │  (copilot)   │  │  (any agent) │        │   │
│  │  │              │  │              │  │              │        │   │
│  │  │ HTTP_PROXY=  │  │ HTTP_PROXY=  │  │ HTTP_PROXY=  │        │   │
│  │  │ squid:3128   │  │ squid:3128   │  │ squid:3128   │        │   │
│  │  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘        │   │
│  │         │                 │                  │                │   │
│  │         └─────────────────┴──────────────────┘                │   │
│  │                           │                                   │   │
│  │              ┌────────────▼────────────┐                      │   │
│  │              │      Squid Proxy        │                      │   │
│  │              │  (bridges both nets)    │                      │   │
│  │              │  port 3128              │                      │   │
│  │              │  ACL allowlist enforced │                      │   │
│  │              └────────────┬────────────┘                      │   │
│  └───────────────────────────┼───────────────────────────────────┘   │
│                              │                                       │
│  ┌───────────────────────────┼───────────────────────────────────┐   │
│  │       sandbox-external (Docker bridge, internet access)       │   │
│  │                          │                                    │   │
│  └───────────────────────────┼───────────────────────────────────┘   │
│                              │                                       │
│                        ┌─────▼──────┐                                │
│                        │  Internet  │                                │
│                        │  (allowed  │                                │
│                        │  domains   │                                │
│                        │  only)     │                                │
│                        └────────────┘                                │
└─────────────────────────────────────────────────────────────────────┘
```

**Network isolation is enforced at the Docker layer, not inside containers.**
The internal network has `internal: true` set, which means Docker itself
prevents direct outbound routing. All egress must pass through the Squid
container, which sits on both networks. This removes the requirement for
`NET_ADMIN` capability and per-container iptables rules.

### Component Responsibilities

| Component | Responsibility | Notes |
|-----------|----------------|-------|
| Squid proxy container | Shared egress gateway. Enforces ACL domain allowlist. Routes HTTP CONNECT for HTTPS. Logs all requests and denials. Persists across sandbox lifecycle. | Single instance. Shared by all sandboxes. |
| sandbox-internal network | Isolates sandbox containers from direct internet. Forces all egress through Squid. | `internal: true` in Docker Compose. No default route to internet. |
| sandbox-external network | Provides internet access for the Squid container only. | Standard bridge network. Only Squid joins this. |
| Sandbox container (base image) | Debian bookworm dev environment. Runs agent. Configured to route via proxy env vars. Read-only rootfs + tmpfs. Non-root user. | N instances, one per agent session. |
| Agent image layer (claude/copilot) | Extends base image with agent CLI, mise runtimes, credentials config, agent-specific policy overlay. | Per-agent variant of base. |
| Squid ACL config | Domain allowlist defining what egress is permitted. Maps to policy.json concept from existing iptables approach. | File mounted into Squid container or baked into Squid image. |
| Host orchestration (mise tasks) | Starts/stops proxy, launches/tears down sandboxes, passes workspace mounts and credential volumes. | mise.toml on host. |
| Volume mounts | Workspace (bind), credentials (named volume), caches (npm/pip/cargo named volumes). Outlive individual sandbox runs. | Defined in Docker Compose. |

## Recommended Project Structure

```
agent-sandbox/
├── images/
│   ├── base/
│   │   ├── Dockerfile          # Debian base, dev user, entrypoint
│   │   └── entrypoint.sh       # UID/GID alignment, drops to dev
│   │                           # (init-firewall.py removed or disabled)
│   ├── agents/
│   │   ├── claude/
│   │   │   ├── Dockerfile      # Extends base, installs mise + claude-code
│   │   │   └── policy.json     # Claude-specific allowed domains (→ squid ACL)
│   │   └── copilot/
│   │       ├── Dockerfile      # Extends base, installs copilot
│   │       └── policy.json     # Copilot-specific allowed domains
│   └── proxy/
│       ├── Dockerfile          # FROM ubuntu/squid or sameersbn/squid
│       └── squid.conf          # ACL allowlist config, deny-all default
├── config/
│   └── allowlist.txt           # Shared domain allowlist (mounted into proxy)
├── docker-compose.yml          # Services: proxy + sandbox(es) + networks
├── mise.toml                   # Host-side tasks: proxy:start, sandbox:run, etc.
└── .planning/
    └── ...
```

### Structure Rationale

- **images/proxy/:** Squid gets its own image directory, parallel to base/agents. Keeps proxy config versioned with the project.
- **config/allowlist.txt:** Externalized allowlist means policy changes do not require image rebuilds — just restart proxy with updated mount.
- **policy.json in agent dirs:** Carries forward the existing policy-as-code concept. Build tooling can merge agent policy into the shared allowlist at proxy start.

## Architectural Patterns

### Pattern 1: Dual-Network Docker Isolation

**What:** Squid container joins both an internal (no internet) network and an external (internet-accessible) bridge network. Sandbox containers join only the internal network. All egress must pass through Squid since containers on the internal network have no direct default route to the internet.

**When to use:** Anytime you need enforceable egress control without per-container iptables. This is the primary pattern for the shared proxy architecture.

**Trade-offs:**
- Pro: No NET_ADMIN capability needed in sandbox containers
- Pro: One ACL config governs all sandboxes simultaneously
- Pro: Docker enforces the isolation, not the container itself
- Con: All sandboxes share one proxy — a misbehaving sandbox could consume proxy resources
- Con: Proxy becomes a single point of failure (mitigated: proxy is long-running, simple to restart)

**Example (docker-compose.yml):**
```yaml
networks:
  sandbox-internal:
    internal: true   # No direct internet — Docker enforces this
  sandbox-external:
    driver: bridge

services:
  proxy:
    image: agent-sandbox-proxy:local
    networks:
      - sandbox-internal
      - sandbox-external  # Only this container reaches the internet

  sandbox:
    image: agent-sandbox-claude:local
    networks:
      - sandbox-internal  # Internal only — must use proxy
    environment:
      - HTTP_PROXY=http://proxy:3128
      - HTTPS_PROXY=http://proxy:3128
      - NO_PROXY=localhost,127.0.0.1
```

### Pattern 2: Explicit Forward Proxy (not transparent intercept)

**What:** Sandbox containers are configured with `HTTP_PROXY` and `HTTPS_PROXY` environment variables pointing at Squid on port 3128. For HTTPS, Squid handles the CONNECT tunnel — it sees the destination hostname for ACL matching, then creates a raw TCP tunnel to the destination. This means Squid does not need to decrypt TLS (no SSL-bump).

**When to use:** This project's use case — hostname-based domain allowlisting without TLS inspection. Simpler and more trustworthy than SSL-bump.

**Trade-offs:**
- Pro: No CA certificate management required in sandbox containers
- Pro: TLS traffic is not decrypted — Squid only sees the CONNECT hostname
- Pro: Standard env vars (`HTTP_PROXY`, `HTTPS_PROXY`) are respected by curl, wget, npm, pip, cargo, go without extra configuration
- Con: ACL matching is on the CONNECT hostname, not the full URL — sufficient for domain allowlisting
- Con: Requires tools to honor proxy env vars (all standard tools do; some custom tools may not)

**Squid ACL config pattern:**
```
acl allowed_domains dstdomain "/etc/squid/allowlist.txt"
acl CONNECT method CONNECT
acl SSL_ports port 443
acl Safe_ports port 80 443

http_access deny !Safe_ports
http_access deny CONNECT !SSL_ports
http_access allow allowed_domains
http_access deny all
```

### Pattern 3: Policy-as-File Allowlist

**What:** The existing `policy.json` concept evolves into a plain-text domain allowlist file consumed directly by Squid's `dstdomain` ACL directive. One file per agent type (or a merged shared file), mounted into the proxy container. Changes take effect on proxy reload (`squid -k reconfigure`) without rebuilding images.

**When to use:** When the domain policy needs to be updatable independently of the container image. Supports the existing pattern of per-agent policies (claude/policy.json, copilot/policy.json) while centralizing enforcement in the proxy.

**Trade-offs:**
- Pro: No iptables DNS resolution required (current approach resolves domains to IPs at boot, which can go stale)
- Pro: Squid matches on hostname — policy is readable and auditable
- Con: Multiple agent policies must be merged at proxy startup (simple concatenation works)
- Con: Squid reload is needed after allowlist changes (non-disruptive with `squid -k reconfigure`)

## Data Flow

### Egress Request Flow (HTTPS)

```
Agent process in sandbox
    | HTTP CONNECT proxy:3128 target.example.com:443
    |
    v
Squid proxy container (sandbox-internal network)
    | 1. Check src IP against localnet ACL (only sandbox-internal range)
    | 2. Check CONNECT destination against allowed_domains ACL
    |    - ALLOWED: create TCP tunnel to target.example.com:443
    |    - DENIED:  return 403, log TCP_DENIED
    |
    v (if allowed)
sandbox-external Docker network
    |
    v
Internet → target.example.com:443
    |
    v (TCP tunnel response)
Back through Squid → sandbox container → agent process
```

### Egress Request Flow (HTTP)

```
Agent process in sandbox
    | GET http://target.example.com/ via proxy
    |
    v
Squid proxy container
    | 1. Check dstdomain against allowed_domains ACL
    |    - ALLOWED: forward request to target
    |    - DENIED:  return 403
    |
    v (if allowed)
target.example.com:80
    |
    v (response)
Back through Squid → sandbox container
```

### Sandbox Startup Flow

```
Host: mise run sandbox:start
    |
    v
docker compose up proxy          (if not running)
    | Squid reads squid.conf + allowlist.txt
    | Binds port 3128 on sandbox-internal
    |
    v
docker compose run sandbox       (ephemeral or persistent)
    | Container joins sandbox-internal
    | entrypoint.sh: adjust UID/GID → drop to dev user
    | (no firewall init — proxy handles egress control)
    |
    v
Agent runs inside sandbox
    | All outbound traffic via HTTP_PROXY env vars
    | Proxy enforces allowlist
    | Proxy logs all requests
```

### Key Data Flows

1. **Policy update:** Edit `config/allowlist.txt` on host → `docker compose exec proxy squid -k reconfigure` → new ACL active immediately, no container restart.
2. **Credential injection:** Named volumes (claude-state, etc.) mounted into sandbox at startup. Agent reads credentials from volume. Proxy never sees credentials.
3. **Workspace access:** Host project directory bind-mounted into `/workspace`. Changes visible on both host and sandbox immediately.
4. **Cache persistence:** npm/pip/cargo cache volumes survive sandbox teardown. Subsequent runs reuse cached packages, avoiding repeated proxy traffic.

## Scaling Considerations

This is a local development tool. Scale concerns are about concurrent sandboxes on one machine, not distributed deployment.

| Concurrent sandboxes | Architecture Adjustments |
|----------------------|--------------------------|
| 1-3 | Single Squid instance, default config, no resource limits needed |
| 4-10 | Add `maximum_object_size` and `cache_mem` tuning to Squid. Consider memory and PID limits on each sandbox container. |
| 10+ | Squid connection count limits may need tuning. Likely hitting host memory before proxy becomes bottleneck. Resource limits per sandbox become essential. |

### Scaling Priorities

1. **First bottleneck:** Host memory — each sandbox with full mise runtimes uses significant RAM. Set memory limits per container.
2. **Second bottleneck:** Squid connection handling — unlikely to be hit at local dev scale but `workers` directive can be increased if needed.

## Anti-Patterns

### Anti-Pattern 1: Per-Container Firewall (existing approach)

**What people do:** Run `iptables` inside each sandbox container, resolve domain names to IPs at startup, add those IPs to an ipset, set default DROP policy.

**Why it's wrong:**
- Requires `NET_ADMIN` (and `NET_RAW`) capabilities per container — elevated privilege
- DNS-resolved IPs go stale (CDN IPs rotate); policy must be re-applied to stay current
- N containers means N independent firewall states to manage
- Initialization adds latency to every sandbox startup (DNS resolution, iptables setup)
- Harder to audit — policy enforcement is inside containers the agent can theoretically tamper with

**Do this instead:** Shared Squid proxy on an isolated Docker network. No elevated capabilities in sandbox containers. One ACL config file. Hostname-based matching stays current without re-resolution.

### Anti-Pattern 2: Transparent Proxy with SSL-Bump

**What people do:** Set up Squid as a transparent proxy with SSL interception (ssl-bump), install a custom CA cert in sandbox containers to MITM all TLS traffic.

**Why it's wrong:**
- Requires a custom CA cert baked into or injected into every sandbox image
- Adds Squid compilation dependency (ssl-bump requires `--with-openssl` build flag)
- Introduces an in-path TLS termination — more attack surface, more config complexity
- HPKP/certificate transparency checks may fail for some destinations
- Overkill for this use case — domain-level allowlisting (not URL-level) is sufficient

**Do this instead:** Explicit forward proxy mode. Squid sees the CONNECT hostname for ACL matching without decrypting TLS. Much simpler; no CA management required.

### Anti-Pattern 3: No_proxy Gaps

**What people do:** Set `HTTP_PROXY` and `HTTPS_PROXY` but forget `NO_PROXY` for localhost and Docker-internal addresses.

**Why it's wrong:** Traffic to `localhost`, `127.0.0.1`, and the Docker internal network (e.g., `172.17.0.0/16`) gets routed through the proxy unnecessarily, causing failures for local services (MCP servers, database connections) that the agent needs to reach.

**Do this instead:** Always set `NO_PROXY=localhost,127.0.0.1,::1` alongside the proxy env vars. Optionally include the sandbox-internal subnet if sandbox-to-sandbox communication is needed.

### Anti-Pattern 4: Proxy as Sidecar

**What people do:** Deploy one Squid container per sandbox as a sidecar in the same Compose service group.

**Why it's wrong:** N sandboxes → N Squid processes → N ACL configs to keep in sync. Defeats the centralization benefit. More memory, more attack surface.

**Do this instead:** One long-running proxy container shared by all sandboxes. Start it once; sandboxes start and stop independently.

## Integration Points

### External Services

| Service | Integration Pattern | Notes |
|---------|---------------------|-------|
| Docker Engine | docker compose for lifecycle management | Proxy and sandboxes defined in same compose file; proxy starts before sandboxes via `depends_on` |
| mise (host-side) | Tasks in `mise.toml` call docker compose commands | `proxy:start`, `sandbox:run`, `sandbox:stop` tasks wrap compose commands |
| Agent CLIs (claude, copilot) | Installed in agent image layers via mise; credentials via named volumes | Each agent image is a separate Dockerfile layer on the base |
| Package registries (npm, pip, cargo, go) | All traffic goes through Squid; registries must be in allowlist | Cache volumes reduce repeat traffic |

### Internal Boundaries

| Boundary | Communication | Notes |
|----------|---------------|-------|
| sandbox → proxy | HTTP CONNECT / HTTP via `HTTP_PROXY` env var on port 3128 | Standard proxy protocol; all standard tools honor env vars |
| proxy → internet | Direct TCP on allowed ports (80, 443) | Only Squid container has external network access |
| host → sandbox | docker compose exec or docker run interactive | entrypoint handles UID/GID adjustment |
| host → proxy | docker compose exec for squid reload or log inspection | Proxy management tasks |
| sandbox → workspace | Bind mount at `/workspace` | Read-write; changes immediately visible to host |
| sandbox → credentials | Named volume mount at `/home/dev/.claude` (or equivalent) | Credentials persist across sandbox restarts |

## Suggested Build Order

The architecture has clear dependency layers:

1. **Proxy image** (`images/proxy/`) — Self-contained; no dependency on sandbox base. Build first so it can be validated independently.
2. **Base sandbox image** (`images/base/`) — Remove `init-firewall.py` invocation from entrypoint, remove `NET_ADMIN` from compose. Add proxy env vars to image defaults or entrypoint.
3. **Agent image layers** (`images/agents/claude`, `images/agents/copilot`) — Depend on base. Build after base is stable.
4. **Docker Compose wiring** — Update `docker-compose.yml` to define dual networks, add proxy service, add `depends_on` for sandboxes.
5. **Allowlist config** (`config/allowlist.txt`) — Merge existing `policy.json` domain lists from agent dirs. Validate against Squid `dstdomain` format.
6. **mise tasks** — Host-side orchestration comes last; wraps everything built above.

## Sources

- [jimangel.io: Restrict Container Internet Access with Squid Proxy](https://www.jimangel.io/posts/docker-block-internet-squid-proxy) — dual-network Docker topology, env var routing pattern (MEDIUM confidence, community blog verified against Squid docs)
- [INNOQ: Dev Sandbox Network for AI Coding Agents (2026-03)](https://www.innoq.com/en/blog/2026/03/dev-sandbox-network/?mode=eco/) — nftables + explicit forward proxy for agent sandbox use case (MEDIUM confidence)
- [Squid ACL documentation](https://wiki.squid-cache.org/SquidFaq/SquidAcl) — `dstdomain` ACL type, `http_access deny all` deny-default pattern (HIGH confidence, official docs)
- [Squid HTTPS/CONNECT documentation](https://wiki.squid-cache.org/Features/HTTPS) — explicit forward proxy vs ssl-bump distinction (HIGH confidence, official docs)
- [GitHub: signal-9/docker-squid-whitelist](https://github.com/signal-9/docker-squid-whitelist) — minimal whitelist-only Squid container reference (MEDIUM confidence)
- [GitHub: salrashid123/squid_proxy](https://github.com/salrashid123/squid_proxy) — multi-mode Squid proxy patterns including SSL intercept (MEDIUM confidence)
- Existing codebase: `images/base/init-firewall.py`, `docker-compose.yml`, agent Dockerfiles — authoritative source on current iptables approach being replaced (HIGH confidence)

---
*Architecture research for: container-based agent sandbox with shared Squid proxy egress*
*Researched: 2026-03-24*
