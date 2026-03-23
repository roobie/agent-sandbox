# Phase 1: Proxy Infrastructure - Research

**Researched:** 2026-03-24
**Domain:** Squid forward proxy in Docker, dual-network egress control, iptables migration
**Confidence:** HIGH

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **Allowlist format:** Plain text, one domain per line, consumed by Squid `dstdomain` ACL via `acl allowed_domains dstdomain "/etc/squid/allowlist.txt"`. Evolves from policy.json but uses Squid-native format. Host-mountable to allow edits without rebuilding.
- **Docker network topology:** Compose `internal: true` network for sandbox containers. Proxy joins both internal and default bridge. Sandbox containers set `HTTP_PROXY=http://squid:3128`, `HTTPS_PROXY=http://squid:3128`, `NO_PROXY=localhost,127.0.0.1`.
- **Proxy container setup:** Debian bookworm slim + `apt install squid`. Tagged `agent-sandbox-proxy:local`. Separate Dockerfile at `images/proxy/Dockerfile`. squid.conf and default allowlist baked into image at `/etc/squid/`.
- **Health check:** `squid -k check` + `curl -sf -x http://localhost:3128 http://example.com`. Sandbox containers use `depends_on: proxy: condition: service_healthy`. Interval 5s, timeout 3s, retries 3.
- **Squid logging:** `access_log stdio:/dev/stdout`, `cache_log stdio:/dev/stderr`. No separate log volume.
- **SNI peek/splice:** `ssl_bump peek all` + `ssl_bump splice all`. No CA cert needed. Requires `--with-openssl` Squid build (Debian package includes this).
- **Migration strategy:** Clean single cutover. Remove `init-firewall.py` from entrypoint.sh, remove from image layers, drop `cap_add: [NET_ADMIN, NET_RAW]`, remove `iptables`, `ipset`, `aggregate` packages from base Dockerfile. All in the same change.

### Claude's Discretion

- Exact squid.conf structure and ACL ordering beyond the allowlist pattern
- Cache configuration (start with caching disabled, tune later if needed)
- Whether to keep `iproute2`/`dnsutils` in base image for debugging convenience
- Error page customization for blocked domains

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| PROXY-01 | Squid proxy runs as a standalone long-running container, separate from sandbox containers | images/proxy/Dockerfile + Compose service with `restart: unless-stopped` |
| PROXY-02 | Squid enforces domain-based egress allowlist via dstdomain ACLs loaded from a config file | `acl allowed_domains dstdomain "/etc/squid/allowlist.txt"` + host mount override pattern |
| PROXY-03 | Squid uses SNI peek/splice to verify HTTPS destination hostnames without TLS decryption | `ssl_bump peek all` + `ssl_bump splice all` in squid.conf; Debian squid package is built with `--with-openssl` |
| PROXY-04 | Multiple sandbox containers route through the single Squid proxy simultaneously via shared Docker network | `sandbox-internal` bridge network; all sandboxes join it; only proxy also joins `sandbox-external` |
| PROXY-05 | Sandbox containers join an internal Docker network (no direct internet); only the proxy bridges to external | `internal: true` on `sandbox-internal` network in docker-compose.yml |
| PROXY-06 | Sandbox containers use HTTP_PROXY/HTTPS_PROXY env vars pointing at the Squid proxy | Environment block in agent-sandbox service; `HTTP_PROXY=http://proxy:3128`, `HTTPS_PROXY=http://proxy:3128`, `NO_PROXY=localhost,127.0.0.1` |
| PROXY-07 | Proxy container has a health check; sandbox containers wait for proxy to be healthy before starting | Compose healthcheck block + `depends_on: proxy: condition: service_healthy` |
| MIG-01 | Existing init-firewall.py and iptables approach completely removed (not left dormant) | Remove from entrypoint.sh, remove from Dockerfile COPY directives, delete file |
| MIG-02 | NET_ADMIN and NET_RAW capabilities removed from sandbox containers | Remove `cap_add: [NET_ADMIN, NET_RAW]` from docker-compose.yml |
</phase_requirements>

---

## Summary

Phase 1 establishes the shared Squid proxy container as the sole egress path for all sandbox containers and completely removes the existing per-container iptables/ipset firewall. The existing code in `images/base/` is well-understood: `init-firewall.py` (240+ lines) resolves domain names to IPs at container startup and configures iptables rules with NET_ADMIN capability — this entire mechanism goes away.

The replacement is architecturally simpler: a new `images/proxy/` directory with a Dockerfile (Debian bookworm + squid) and a baked-in squid.conf. Two Docker networks replace the iptables rules — `sandbox-internal` (internal: true, no direct internet) and `sandbox-external` (bridge). The proxy container bridges both; sandbox containers join only the internal one. Docker's own network layer enforces the isolation, not the containers themselves.

The SNI peek/splice decision is notable: this is more than a plain CONNECT tunnel. Squid reads the TLS ClientHello SNI field to verify the tunnel destination before splicing, which prevents hostname spoofing attacks (agent says `github.com` in the CONNECT but the TCP connection is to `evil.com`). This requires the OpenSSL-enabled Squid build, which the Debian bookworm package provides. No CA certificate is distributed and no TLS traffic is decrypted.

**Primary recommendation:** Build proxy image first, verify SNI peek/splice works independently, then update base image (remove firewall code), then wire docker-compose.yml. Never run both iptables and proxy simultaneously — clean cutover enforced by removing NET_ADMIN at the same time as removing the firewall code.

---

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| squid | 5.7-2+deb12u5 (Debian bookworm apt) | Forward proxy with ACL enforcement | Production-proven, apt-installed, `--with-openssl` build included, `dstdomain` ACL supports SNI peek/splice, no separate compilation needed |
| debian:bookworm-slim | 12 (bookworm-slim) | Proxy container base image | Consistent with sandbox base image; one distro to maintain; glibc environment; slim reduces image size |
| Docker Compose v2 | Compose spec (no `version:` field) | Multi-container orchestration with network isolation | `internal: true` network support, `service_healthy` depends_on, built into Docker CLI |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| curl | system | Proxy health check probe | Inside proxy container for health check (`curl -sf -x http://localhost:3128 http://example.com`) |
| gosu | 1.16 (bookworm) | Entrypoint UID/GID drop in base image | Already used; survives Phase 1 unchanged |
| python3 | system | images/build.py (no change needed) | Already used for build orchestration |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Debian bookworm + apt install squid | ubuntu/squid:5.2-22.04_beta | Ubuntu image is Canonical-maintained, but builds on Ubuntu 22.04 not Debian; mixing distros adds maintenance surface. Bookworm gives squid 5.7 (newer) vs squid 5.2. |
| SNI peek/splice | Plain CONNECT tunnel (no ssl_bump) | CONNECT alone allows hostname spoofing — agent sends `CONNECT github.com:443` but connects to a different IP. SNI peek verifies the ClientHello hostname matches. Decided: use peek/splice. |
| Baked allowlist in image | Host-mount only allowlist | Baked allowlist requires rebuild for every domain change. Decision: bake default + support host mount override. |

**Installation (proxy container):**
```bash
apt-get install -y --no-install-recommends squid curl
```

---

## Architecture Patterns

### Recommended Project Structure

```
images/
├── base/
│   ├── Dockerfile          # Remove: iptables, ipset, aggregate, init-firewall.py COPY
│   │                       # Remove: policy.json COPY
│   └── entrypoint.sh       # Remove: firewall init block (lines 11-25)
│   # DELETE: init-firewall.py
│   # DELETE: policy.json
├── agents/
│   ├── claude/
│   │   └── policy.json     # Domains migrated to allowlist.txt; file can be removed
│   └── copilot/
│       └── policy.json     # Domains migrated to allowlist.txt; file can be removed
└── proxy/
    ├── Dockerfile          # NEW: FROM debian:bookworm-slim, apt install squid curl
    └── squid.conf          # NEW: SNI peek/splice + allowlist ACL

config/
└── allowlist.txt           # NEW (or images/proxy/allowlist.txt baked in image)

docker-compose.yml          # Modified: add proxy service + networks, remove cap_add
images/build.py             # Modified: add build_proxy() function
```

### Pattern 1: SNI Peek/Splice squid.conf

**What:** Squid reads the TLS ClientHello to extract the SNI hostname, matches it against the allowlist ACL, then splices (transparent TCP tunnel) if allowed. This is distinct from ssl-bump (no MITM, no CA cert, no decryption).

**When to use:** Any HTTPS CONNECT where destination hostname verification is required without TLS decryption.

**Example:**
```squid
# Source: Squid ssl_bump documentation + CONTEXT.md decisions
http_port 3128

# --- SNI peek/splice (requires --with-openssl build) ---
# No https_port needed for explicit forward proxy; ssl_bump operates on CONNECT tunnels
ssl_bump peek all
ssl_bump splice all

# --- ACL definitions ---
acl Safe_ports port 80
acl Safe_ports port 443
acl CONNECT method CONNECT
acl SSL_ports port 443
acl allowed_domains dstdomain "/etc/squid/allowlist.txt"

# --- ACL enforcement ---
# Deny requests to unsafe ports
http_access deny !Safe_ports

# Deny CONNECT to non-SSL ports
http_access deny CONNECT !SSL_ports

# Allow connections to whitelisted domains
http_access allow allowed_domains

# Deny everything else (deny-default)
http_access deny all

# --- Logging (stdout/stderr for docker logs) ---
access_log stdio:/dev/stdout
cache_log stdio:/dev/stderr

# --- Caching disabled (freshness > performance for sandbox use) ---
cache deny all
```

### Pattern 2: Dual-Network Docker Compose Topology

**What:** Two Docker networks. Sandbox containers join only the internal network (no direct internet). Proxy container joins both. Docker enforces isolation at the network layer.

**When to use:** Any Compose setup where egress control must be enforced without per-container capabilities.

**Example:**
```yaml
# Source: CONTEXT.md decisions + docker-compose.yml modification plan
networks:
  sandbox-internal:
    internal: true    # Docker blocks all external routing from this network
  sandbox-external:
    driver: bridge

services:
  proxy:
    image: agent-sandbox-proxy:local
    container_name: agent-sandbox-proxy
    networks:
      - sandbox-internal
      - sandbox-external
    restart: unless-stopped
    healthcheck:
      test: ["CMD-SHELL", "squid -k check && curl -sf -x http://localhost:3128 http://example.com"]
      interval: 5s
      timeout: 3s
      retries: 3
      start_period: 10s
    volumes:
      # Host mount overrides baked-in allowlist when present
      - ./config/allowlist.txt:/etc/squid/allowlist.txt:ro

  agent-sandbox:
    image: agent-sandbox-claude:local
    container_name: agent-sandbox
    networks:
      - sandbox-internal
    depends_on:
      proxy:
        condition: service_healthy
    environment:
      - HTTP_PROXY=http://proxy:3128
      - HTTPS_PROXY=http://proxy:3128
      - http_proxy=http://proxy:3128
      - https_proxy=http://proxy:3128
      - NO_PROXY=localhost,127.0.0.1
    # cap_add REMOVED — no NET_ADMIN, no NET_RAW
```

### Pattern 3: Proxy Dockerfile

**What:** Minimal Debian bookworm-slim image with squid and curl. squid.conf and default allowlist baked in. Image runs squid in foreground (not daemon mode) for proper PID 1 and docker logs support.

**Example:**
```dockerfile
# Source: CONTEXT.md decisions
FROM debian:bookworm-slim

RUN apt-get update && \
    apt-get install -y --no-install-recommends squid curl && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

COPY squid.conf /etc/squid/squid.conf
COPY allowlist.txt /etc/squid/allowlist.txt

RUN chmod 644 /etc/squid/squid.conf /etc/squid/allowlist.txt

EXPOSE 3128

# Run squid in foreground; logs go to stdout/stderr via squid.conf directives
CMD ["squid", "-N", "-f", "/etc/squid/squid.conf"]
```

**Note:** `squid -N` runs in foreground (no daemon). Combined with `access_log stdio:/dev/stdout` in squid.conf, all access logs appear in `docker logs agent-sandbox-proxy`.

### Pattern 4: Allowlist Domain Migration

**What:** Domains from `images/agents/claude/policy.json`, `images/agents/copilot/policy.json`, and `images/base/policy.json` are merged into a single `allowlist.txt`. Leading dot enables subdomain matching.

**Existing domains to migrate:**

From `images/base/policy.json` (services: github):
- `.github.com` (covers github.com + all subdomains including api.github.com, raw.githubusercontent.com, etc.)

From `images/agents/claude/policy.json`:
- `.api.anthropic.com`
- `.sentry.io`
- `.statsig.anthropic.com`
- `.statsig.com`
- `.pypi.org`
- `.mise-versions.jdx.dev`

From `images/agents/copilot/policy.json` (services: github + domains):
- `.pypi.org` (duplicate — deduplicate in allowlist)
- `.mise-versions.jdx.dev` (duplicate)

**Combined allowlist.txt:**
```
# GitHub (replaces services: ["github"] — covers all GitHub IP ranges via hostname)
.github.com
.githubusercontent.com

# Anthropic / Claude Code
.api.anthropic.com
.statsig.anthropic.com
.statsig.com

# Error tracking
.sentry.io

# Package registries
.pypi.org
.files.pythonhosted.org

# mise version resolution
.mise-versions.jdx.dev
```

**Key insight:** Squid `dstdomain` with leading dot matches the domain and all subdomains. `github.com` in policy.json used the GitHub /meta API to resolve IP ranges at boot — Squid matches `.github.com` directly without DNS resolution at startup, and stays current as GitHub rotates CDN IPs.

### Anti-Patterns to Avoid

- **Running both firewall approaches simultaneously:** If `init-firewall.py` runs AND the proxy is active, Docker's embedded DNS NAT rules (`127.0.0.11`) can be corrupted, breaking inter-container DNS. The `getent hosts proxy` call inside the sandbox will fail. Symptom: `curl http://proxy:3128` gives "Could not resolve host: proxy".
- **`depends_on` without `condition: service_healthy`:** Compose `depends_on` without a condition only waits for process start, not for Squid to be listening. Sandbox will hit "connection refused" on first requests during cold start.
- **Setting only uppercase proxy env vars:** Several tools check lowercase (`http_proxy`, `https_proxy`). Set both case variants.
- **Forgetting `NO_PROXY`:** Without `NO_PROXY=localhost,127.0.0.1`, Docker healthcheck traffic and loopback connections route through the proxy, causing confusion.
- **Forgetting `squid -N` in CMD:** Without foreground flag, Squid daemonizes and the container exits immediately after start.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Domain-based egress filtering | Custom iptables + DNS resolution at startup (existing init-firewall.py) | Squid `dstdomain` ACL | iptables works on IPs, not hostnames; CDN IPs rotate; DNS-at-startup goes stale; requires NET_ADMIN |
| HTTPS destination verification | SSL-bump MITM | Squid `ssl_bump peek all` + `ssl_bump splice all` | peek/splice reads SNI without decrypting; no CA cert needed; no certificate pinning breakage |
| Proxy readiness signal | `sleep 5` in entrypoint | Docker Compose `healthcheck` + `service_healthy` | sleep is fragile; healthcheck is declarative and integrates with Compose dependency graph |
| Allowlist hot-reload | Restart proxy container | `docker compose exec proxy squid -k reconfigure` | Non-disruptive; in-flight connections complete; no container teardown |
| Multi-container log aggregation | Separate log volume + log shipper | `access_log stdio:/dev/stdout` | Docker captures stdout; `docker logs agent-sandbox-proxy` shows all sandbox requests |

**Key insight:** The existing `init-firewall.py` is 435 lines solving a problem that Squid solves natively with 20 lines of config. The entire complexity exists because iptables operates on IP addresses — Squid's `dstdomain` ACL eliminates this.

---

## Common Pitfalls

### Pitfall 1: SNI Peek/Splice Requires OpenSSL Build

**What goes wrong:** `ssl_bump` directives cause Squid startup error: "SslBump requires --with-openssl" if the installed Squid binary was not compiled with OpenSSL support.

**Why it happens:** Some Squid packages are built without OpenSSL to reduce footprint. Debian bookworm has two packages: `squid` (with OpenSSL, 5.7-2+deb12u5) and `squid-openssl` (historically a separate variant — in bookworm the main `squid` package includes it).

**How to avoid:** Use Debian bookworm's `squid` package. Verify in Dockerfile: `RUN squid -v | grep with-openssl` as a build-time assertion (optional but useful).

**Warning signs:** Proxy container exits immediately on first start with squid error in logs. Run `squid -v` to check build options.

### Pitfall 2: Proxy Startup Race

**What goes wrong:** Sandbox container starts while Squid is still initializing. First package install or agent startup request hits "connection refused" on port 3128.

**Why it happens:** Docker Compose starts services in dependency order but default `depends_on` only waits for process launch, not readiness.

**How to avoid:** Health check with `condition: service_healthy`. The health check command `squid -k check && curl -sf -x http://localhost:3128 http://example.com` validates both config validity AND that the port is accepting connections.

**Warning signs:** Works on second `docker compose up` (proxy already warm), fails on first cold start.

### Pitfall 3: DNS Resolution Broken After Migration

**What goes wrong:** After removing iptables code, sandbox container cannot resolve `proxy` hostname. `getent hosts proxy` returns nothing. `curl http://proxy:3128` fails.

**Why it happens:** Two possible causes: (1) the migration is incomplete — `init-firewall.py` still runs and corrupts Docker's DNS NAT rules; (2) the sandbox container is not on the `sandbox-internal` network where the `proxy` container's DNS name resolves.

**How to avoid:** Remove ALL of these simultaneously: the `cap_add` in docker-compose.yml, the firewall init block in entrypoint.sh, and the `init-firewall.py` COPY in base Dockerfile. The `proxy` DNS name resolves only within the `sandbox-internal` network — verify both services are on that network.

**First verification step after migration:** `docker compose exec agent-sandbox getent hosts proxy`

### Pitfall 4: Health Check Target Must Be Reachable

**What goes wrong:** The health check `curl -sf -x http://localhost:3128 http://example.com` fails because `example.com` is not in the allowlist.

**Why it happens:** The deny-all default in squid.conf blocks `example.com`. Squid returns HTTP 403, which curl treats as success (non-zero exit). The health check passes but for wrong reasons.

**How to avoid:** The CONTEXT.md decision uses `http://example.com` (HTTP, not HTTPS). For plain HTTP proxying, Squid will either allow or deny based on ACL. Two options:
1. Add `example.com` to allowlist (noisy in access logs).
2. Use `squid -k check` alone as the health check — this validates config and process health without a network probe.
3. Use `squid -k check` AND a curl to a known-allowed domain that returns fast (e.g., `http://mise-versions.jdx.dev`).

**Recommended approach:** Use the `squid -k check` command as the primary health signal. It validates that the Squid process is running and config is loaded. Add curl as secondary probe to a domain in the allowlist.

### Pitfall 5: allowlist.txt dstdomain Format

**What goes wrong:** Domain entries without a leading dot only match the exact domain, not subdomains. `github.com` in allowlist.txt matches `github.com` but NOT `api.github.com` or `raw.githubusercontent.com`.

**Why it happens:** Squid `dstdomain` ACL: exact domain matches without dot, subdomain wildcard with leading dot. The existing `policy.json` used GitHub's /meta API for explicit IP ranges; the new format must compensate by using subdomain wildcard syntax.

**How to avoid:** Use leading dot for all entries: `.github.com` (matches github.com and all subdomains). Test with `curl -x http://proxy:3128 https://raw.githubusercontent.com/...` to verify subdomain coverage.

### Pitfall 6: Squid Proxy Not Binding on Internal Network

**What goes wrong:** Squid listens on `http_port 3128` which binds to `0.0.0.0`. If the proxy container is also on the external network, the proxy port is exposed externally (to the host and potentially beyond).

**Why it happens:** Default `http_port 3128` binds all interfaces.

**How to avoid:** In docker-compose.yml, do NOT publish port 3128 to the host (`ports: ["3128:3128"]`). The port is only accessible within Docker networks. Sandbox containers reach `proxy:3128` via the `sandbox-internal` network. The proxy should not have any `ports:` binding unless debugging requires it.

---

## Code Examples

### Complete squid.conf with SNI Peek/Splice

```squid
# Source: CONTEXT.md decisions + Squid official docs
# https://wiki.squid-cache.org/Features/SslBump

http_port 3128

# SNI peek/splice: read TLS ClientHello to verify hostname,
# then splice (transparent tunnel) without decrypting payload.
# No CA cert needed. No certificate pinning breakage.
ssl_bump peek all
ssl_bump splice all

# ACL definitions
acl Safe_ports port 80
acl Safe_ports port 443
acl CONNECT method CONNECT
acl SSL_ports port 443
acl allowed_domains dstdomain "/etc/squid/allowlist.txt"

# ACL enforcement (order matters — evaluated top to bottom)
http_access deny !Safe_ports
http_access deny CONNECT !SSL_ports
http_access allow allowed_domains
http_access deny all

# Logging to stdout/stderr for docker logs
access_log stdio:/dev/stdout
cache_log stdio:/dev/stderr

# Disable caching (sandbox use: freshness > performance)
cache deny all
```

### Build Orchestrator Extension

```python
# Source: existing images/build.py pattern
def build_proxy() -> None:
    build_args: dict[str, str] = {}  # No build args needed initially
    run_docker_build("agent-sandbox-proxy:local", SCRIPT_DIR / "proxy", build_args)

# In main():
elif target == "proxy":
    build_proxy()
elif target == "all":
    build_proxy()   # Build proxy first — no dependency on base
    build_base()
    build_claude()
```

### Entrypoint Cleanup (lines to remove from entrypoint.sh)

Lines 11-25 of the current `images/base/entrypoint.sh` — the entire firewall init block:
```bash
# REMOVE THESE LINES:
# Initialize firewall if not already done
# Check if allowed-domains ipset exists (created by init-firewall.py)
if ! ipset list allowed-domains >/dev/null 2>&1; then
    echo "Initializing firewall..."
    if ! /usr/local/bin/init-firewall.py; then
        ...
        exit 1
  fi
else
  echo "Firewall already initialized."
fi
```

After removal, entrypoint.sh starts directly with `cd /workspace`.

### Base Dockerfile Lines to Remove

```dockerfile
# REMOVE these lines from images/base/Dockerfile:
  iptables \
  ipset \
  aggregate \
# (keep iproute2 and dnsutils — per Claude's Discretion, useful for debugging)

# REMOVE these lines:
# Copy default network policy and firewall script
COPY policy.json /etc/agent-sandbox/policy.json
COPY init-firewall.py /usr/local/bin/

USER root

RUN chmod 644 /etc/agent-sandbox/policy.json && \
  chmod +x /usr/local/bin/init-firewall.py
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| iptables/ipset with DNS resolution at container start | Squid forward proxy with dstdomain ACL | Phase 1 (now) | Removes NET_ADMIN requirement; eliminates stale IP caching; simplifies entrypoint by 25 lines |
| Per-container firewall initialization (init-firewall.py) | Shared proxy container enforces policy for all sandboxes | Phase 1 (now) | One ACL config for N sandboxes; startup becomes deterministic |
| policy.json with IP resolution | allowlist.txt with dstdomain hostnames | Phase 1 (now) | Policy stays current as CDN IPs rotate; human-readable format |
| `cap_add: [NET_ADMIN, NET_RAW]` per sandbox | No capability elevation required | Phase 1 (now) | Reduced attack surface per sandbox container |

**Deprecated/outdated after Phase 1:**
- `images/base/init-firewall.py`: Completely removed, not archived
- `images/base/policy.json`: Superseded by `images/proxy/allowlist.txt`
- `images/agents/claude/policy.json`: Domains migrated to shared allowlist; file removed
- `images/agents/copilot/policy.json`: Domains migrated to shared allowlist; file removed
- `cap_add: [NET_ADMIN, NET_RAW]` in docker-compose.yml: Removed

---

## Open Questions

1. **Health check target URL**
   - What we know: CONTEXT.md specifies `curl -sf -x http://localhost:3128 http://example.com`; `example.com` is not in the allowlist; Squid returns 403 (curl exit 0)
   - What's unclear: Is the intent to verify the proxy accepts and routes (even with 403), or to verify a specific allowed domain is reachable?
   - Recommendation: Use `squid -k check` as the primary health signal (validates process + config). If a network probe is needed, use `curl -sf -x http://localhost:3128 http://mise-versions.jdx.dev` (an allowlisted domain). The planner should pick one and be explicit.

2. **`iproute2` and `dnsutils` retention in base image**
   - What we know: Marked as Claude's Discretion. Currently installed for firewall use (`ip route` in init-firewall.py). Both are useful debug tools.
   - What's unclear: Whether they're needed by any agent workflow or only for firewall init
   - Recommendation: Keep both in the base image. `dnsutils` provides `dig`/`getent` which are useful for verifying proxy DNS resolution during testing. `iproute2` provides `ip` which is useful for network debugging. Neither is a security risk. Cost: ~3MB additional image size.

3. **Allowlist host mount path convention**
   - What we know: CONTEXT.md says "mountable from host at runtime"; Squid config references `/etc/squid/allowlist.txt`
   - What's unclear: Whether the mount source is `./config/allowlist.txt` (project-level config dir) or `./images/proxy/allowlist.txt`
   - Recommendation: `./config/allowlist.txt` as the host mount source (matches ARCHITECTURE.md pattern), with `./images/proxy/allowlist.txt` as the file baked into the image (same content, separate paths). Compose volume binding: `- ./config/allowlist.txt:/etc/squid/allowlist.txt:ro` (optional, only mounted when file exists).

---

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | None detected — manual docker-based smoke tests |
| Config file | None — Wave 0 creates basic shell-based test |
| Quick run command | `bash tests/smoke-proxy.sh` |
| Full suite command | `bash tests/smoke-proxy.sh --full` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| PROXY-01 | Proxy container runs independently, persists across sandbox restarts | smoke | `docker compose ps proxy \| grep Up` | Wave 0 |
| PROXY-02 | Allowed domain passes ACL; blocked domain returns 403 | smoke | `docker compose exec agent-sandbox curl -sf -x http://proxy:3128 https://api.anthropic.com` | Wave 0 |
| PROXY-03 | SNI hostname verified — CONNECT to allowed domain succeeds, spoofed hostname rejected | smoke | `docker compose exec agent-sandbox curl -sf -x http://proxy:3128 https://api.anthropic.com` | Wave 0 |
| PROXY-04 | Multiple sandbox containers all routed through single proxy (visible in access log) | smoke | `docker logs agent-sandbox-proxy 2>&1 \| grep CONNECT` after running two sandboxes | Wave 0 |
| PROXY-05 | Sandbox container cannot reach internet directly (without proxy) | smoke | `docker compose exec agent-sandbox curl --noproxy '*' -sf --connect-timeout 3 https://api.anthropic.com` (must fail) | Wave 0 |
| PROXY-06 | HTTP_PROXY and HTTPS_PROXY set in sandbox environment | smoke | `docker compose exec agent-sandbox env \| grep -i proxy` | Wave 0 |
| PROXY-07 | Sandbox waits for proxy health before starting | smoke | `docker compose stop proxy && docker compose up -d agent-sandbox` (sandbox stays waiting) | Wave 0 |
| MIG-01 | init-firewall.py absent from image and not executed | smoke | `docker compose exec agent-sandbox test ! -f /usr/local/bin/init-firewall.py` | Wave 0 |
| MIG-02 | NET_ADMIN and NET_RAW not present on sandbox container | smoke | `docker inspect agent-sandbox \| python3 -c "import json,sys; c=json.load(sys.stdin); print(c[0]['HostConfig']['CapAdd'])"` (must be null) | Wave 0 |

### Sampling Rate

- **Per task commit:** `docker compose ps proxy && docker compose exec agent-sandbox getent hosts proxy`
- **Per wave merge:** `bash tests/smoke-proxy.sh`
- **Phase gate:** Full smoke suite green before `/gsd:verify-work`

### Wave 0 Gaps

- [ ] `tests/smoke-proxy.sh` — covers all PROXY-* and MIG-* requirements
- [ ] `tests/smoke-proxy.sh` needs: `docker compose up -d proxy`, wait for health, run checks, `docker compose down`

---

## Sources

### Primary (HIGH confidence)

- Squid official docs: https://wiki.squid-cache.org/Features/SslBump — ssl_bump peek/splice behavior, no CA cert requirement
- Squid ACL docs: https://wiki.squid-cache.org/SquidFaq/SquidAcl — dstdomain ACL syntax, leading dot for subdomains
- Docker Compose networking: https://docs.docker.com/compose/how-tos/networking/ — `internal: true` network behavior
- Docker Compose startup order: https://docs.docker.com/compose/how-tos/startup-order/ — `service_healthy` condition
- Debian bookworm squid package: https://packages.debian.org/bookworm/squid — version 5.7-2+deb12u5, confirms OpenSSL build
- Existing codebase: `images/base/Dockerfile`, `images/base/entrypoint.sh`, `images/base/init-firewall.py`, `docker-compose.yml`, `images/agents/claude/policy.json`, `images/agents/copilot/policy.json` — authoritative ground truth on what changes

### Secondary (MEDIUM confidence)

- jimangel.io Docker+Squid dual-network topology — verified against Docker Compose `internal: true` docs
- `.planning/research/STACK.md`, `.planning/research/ARCHITECTURE.md`, `.planning/research/PITFALLS.md` — prior research produced for this project, HIGH confidence for this codebase

### Tertiary (LOW confidence)

- None — all critical claims verified against official sources or existing codebase

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — Debian bookworm squid version confirmed in packages.debian.org; Docker Compose `internal: true` confirmed in official docs; existing codebase read directly
- Architecture: HIGH — dual-network pattern confirmed against official Docker docs; existing compose file read directly; CONTEXT.md decisions are locked
- Pitfalls: HIGH — derived from official Squid docs, existing codebase analysis, and prior research in PITFALLS.md

**Research date:** 2026-03-24
**Valid until:** 2026-04-24 (stable: Squid 5.7, Debian bookworm, Docker Compose v2 — no fast-moving components)
