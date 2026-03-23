# Phase 1: Proxy Infrastructure - Context

**Gathered:** 2026-03-24
**Status:** Ready for planning

<domain>
## Phase Boundary

Establish a shared Squid proxy container as the sole egress path for all sandbox containers. Enforce a domain-based allowlist via Squid ACLs with SNI peek/splice for HTTPS verification. Completely remove the existing iptables/ipset firewall approach and NET_ADMIN/NET_RAW capability requirements. This is the architectural pivot everything else depends on.

</domain>

<decisions>
## Implementation Decisions

### Allowlist config format
- Plain text file with one domain per line, consumed by Squid `dstdomain` ACL via `acl allowed_domains dstdomain "/etc/squid/allowlist.txt"`
- Evolves from existing policy.json concept but uses Squid-native format (no JSON parsing needed)
- Allowlist file mountable from host at runtime for easy editing without rebuilding the proxy image
- Default allowlist baked into proxy image; host mount overrides it

### Docker network topology
- Compose `internal: true` network for sandbox containers — no direct internet access
- Proxy container joins both the internal network and the default bridge (internet access)
- Sandbox containers set `HTTP_PROXY=http://squid:3128` and `HTTPS_PROXY=http://squid:3128`
- `NO_PROXY=localhost,127.0.0.1` to avoid routing local traffic through proxy

### Proxy container setup
- Build from Debian bookworm slim + `apt install squid` — consistent with base image approach
- Image tagged as `agent-sandbox-proxy:local` following existing naming convention
- Separate Dockerfile at `images/proxy/Dockerfile`
- Squid config (`squid.conf`) and default allowlist baked into image at `/etc/squid/`

### Health check
- Docker health check: `squid -k check` to validate config + `curl -sf -x http://localhost:3128 http://example.com` as HTTP probe
- Sandbox containers use `depends_on: proxy: condition: service_healthy` to wait for proxy
- Health check interval: 5s, timeout: 3s, retries: 3

### Squid logging
- Access logs to stdout via `access_log stdio:/dev/stdout` — visible via `docker logs`
- Cache logs to stderr via `cache_log stdio:/dev/stderr`
- No separate log volume needed; Docker captures everything

### SNI peek/splice
- `ssl_bump peek all` + `ssl_bump splice all` — reads TLS ClientHello to verify hostname without decrypting
- Prevents hostname spoofing in CONNECT tunnel (agent says `github.com` but connects to `evil.com`)
- No CA certificate needed; no certificate pinning breakage
- Requires `--with-openssl` Squid build (Debian package includes this)

### Migration strategy
- Clean single cutover: remove `init-firewall.py` from entrypoint.sh and all image layers in the same change
- Drop `cap_add: [NET_ADMIN, NET_RAW]` from docker-compose.yml simultaneously
- Remove `iptables`, `ipset`, `iproute2`, `dnsutils`, `aggregate` packages from base Dockerfile (no longer needed for firewall)
- Keep `dnsutils` if needed for debugging; remove the rest
- Verification: `getent hosts squid` inside sandbox confirms proxy DNS resolution works via Docker internal DNS

### Claude's Discretion
- Exact squid.conf structure and ACL ordering beyond the allowlist pattern
- Cache configuration (start with caching disabled, tune later if needed)
- Whether to keep `iproute2`/`dnsutils` in base image for debugging convenience
- Error page customization for blocked domains

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Research findings
- `.planning/research/STACK.md` — Squid 5.7 version confirmation, squid.conf patterns, proxy env var propagation details
- `.planning/research/ARCHITECTURE.md` — Dual-network Docker topology, component boundaries, data flow
- `.planning/research/PITFALLS.md` — Proxy startup race, DNS corruption from iptables, CONNECT port restriction ACL

### Existing code to modify/remove
- `images/base/Dockerfile` — Current base image (remove iptables packages, firewall script)
- `images/base/entrypoint.sh` — Current entrypoint (remove firewall init block)
- `images/base/init-firewall.py` — To be completely removed
- `images/base/policy.json` — To be replaced by Squid allowlist
- `images/agents/claude/policy.json` — Domains to migrate to Squid allowlist
- `images/agents/copilot/policy.json` — Domains to migrate to Squid allowlist
- `docker-compose.yml` — Remove cap_add, add proxy service and internal network
- `images/build.py` — Add proxy image build step

### External references
- `docs/research.md` — Prior research on sandbox patterns and Docker hardening
- `docs/mise.reference.md` — mise tooling (not directly relevant to Phase 1 but referenced in project)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `images/build.py`: Build orchestrator can be extended with `build_proxy()` function following existing `build_base()`/`build_claude()` pattern
- `images/agents/claude/policy.json` and `images/agents/copilot/policy.json`: Domain lists to migrate into Squid allowlist format
- `docker-compose.yml`: Volume mounting patterns (workspace, credentials, cache) remain valid; network and cap_add sections need replacement

### Established Patterns
- Image naming: `agent-sandbox-{component}:local` — proxy image follows as `agent-sandbox-proxy:local`
- Build script pattern: `build_{component}()` functions in `images/build.py`
- Policy files at `/etc/agent-sandbox/` — Squid config can follow similar path convention (`/etc/squid/`)
- Entrypoint pattern: `entrypoint.sh` checks state before acting (idempotent)

### Integration Points
- `docker-compose.yml`: Add `proxy` service, add `sandbox-net` internal network, wire `depends_on`
- `images/build.py`: Add `build_proxy()` after `build_base()`, before agent images
- `images/base/Dockerfile`: Remove iptables/ipset/firewall packages and COPY directives
- `images/base/entrypoint.sh`: Remove firewall init block, add proxy env var setup
- Agent Dockerfiles (`images/agents/*/Dockerfile`): May need `ENV HTTP_PROXY` / `ENV HTTPS_PROXY` for build-time package fetching

</code_context>

<specifics>
## Specific Ideas

- User wants Squid as a long-running singleton — not restarted per sandbox session
- Allowlist should be easy to edit without rebuilding (host mount override)
- Multiple sandboxes must appear in the same Squid access log (verifiable multi-agent routing)
- The migration must be a clean cutover — never run both iptables and proxy simultaneously

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 01-proxy-infrastructure*
*Context gathered: 2026-03-24*
