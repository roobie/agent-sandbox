# Pitfalls Research

**Domain:** Container-based coding agent sandboxes with proxy-based egress control
**Researched:** 2026-03-24
**Confidence:** HIGH (critical pitfalls verified against official docs and real-world reports)

---

## Critical Pitfalls

### Pitfall 1: HTTPS CONNECT Tunneling Defeats Domain-Level Whitelisting

**What goes wrong:**
Squid's ACL domain whitelist enforces which *destinations* agents may CONNECT to, but the CONNECT method is a raw TCP tunnel — Squid cannot inspect the payload. Any tool that speaks raw TCP over port 443 (SSH-over-HTTPS, WebSocket tunnels, DNS-over-HTTPS, custom agent exfiltration) can reach a whitelisted host and bypass all content-level controls. The whitelist stops connections to *unlisted* hosts but says nothing about what travels *through* a CONNECT to an allowed host.

**Why it happens:**
Developers assume "domain whitelist = content whitelist." For plain HTTP that is roughly true. For HTTPS it is not: the proxy sees `CONNECT api.github.com:443` and then forwards opaque bytes. The threat model is exfiltration of secrets via a whitelisted endpoint (e.g., a GitHub Gist, a pastebin-like service on an allowed CDN domain).

**How to avoid:**
Clearly define the threat model before configuring ACLs. This sandbox's stated goal is preventing exfiltration to *unauthorized destinations* — that is achievable with CONNECT whitelisting and is the right scope. Do not claim content-level inspection unless SSL-bump is implemented (which introduces its own pitfalls — see Pitfall 2). Document the boundary explicitly: the proxy enforces *destination*, not *content*.

**Warning signs:**
- Requirements creep toward "we need to see what the agent is sending" — this leads to SSL-bump complexity.
- Policy documents that conflate "allowed domain" with "allowed action."

**Phase to address:**
Proxy foundation phase — define threat model scope in a `SECURITY.md` comment in the Squid config before any ACL work.

---

### Pitfall 2: SSL-Bump Breaks Certificate Pinning and Adds CA Distribution Complexity

**What goes wrong:**
If SSL inspection (ssl-bump) is added to read HTTPS payload, Squid becomes a MITM CA and issues fake certificates for every TLS connection. Any client inside the container that uses certificate pinning (many package registries, cloud SDKs, and modern npm/pip dependencies) will hard-fail with certificate validation errors. Every sandbox container and every tool inside it must trust the proxy's root CA. This creates a CA lifecycle problem: where does the CA cert live, how is it rotated, how are containers updated?

**Why it happens:**
The desire for full visibility over HTTPS traffic is understandable. SSL-bump is the only way to achieve it. The cost — broken pinning, CA distribution — is not obvious until first encountered with a misbehaving package manager.

**How to avoid:**
Do not implement SSL-bump unless certificate pinning is audited across every tool the agent uses. For this project the correct choice is explicit forward proxy (CONNECT tunneling only) — log the destination hostname from the CONNECT request but do not decrypt. This is what the INNOQ sandbox report and Docker's own sandbox documentation recommend.

**Warning signs:**
- curl errors: `SSL certificate problem: unable to get local issuer certificate`
- pip/npm/cargo download failures with TLS errors after enabling ssl-bump
- Container image build failures when Squid is in the path during builds

**Phase to address:**
Proxy foundation phase — explicitly document "no ssl-bump" as an architectural decision in the Squid config.

---

### Pitfall 3: Proxy Not Ready When Sandbox Container Starts

**What goes wrong:**
`docker compose up` starts the proxy container and sandbox containers concurrently. The sandbox container tries to make network requests (mise install, npm install, agent startup checks) before Squid is listening on its port. Connection refused errors appear, and because many package managers retry silently, they succeed on later attempts — masking the race during development. Under higher load or slow starts the race is reliably hit.

**Why it happens:**
Docker Compose `depends_on` without `condition: service_healthy` only waits for the container process to start, not for the service to be ready. Squid takes several seconds to initialize its cache and begin accepting connections.

**How to avoid:**
Add a health check to the Squid container that actually tests the proxy works (make a proxied request through Squid back to a known-good endpoint — the `squid-check` pattern). Use `depends_on: condition: service_healthy` in the sandbox service definition. Do not use `sleep` hacks.

```yaml
# squid container
healthcheck:
  test: ["CMD", "curl", "-sf", "--proxy", "http://localhost:3128", "http://squid-check/"]
  interval: 5s
  timeout: 3s
  retries: 5
  start_period: 10s

# sandbox container
depends_on:
  squid:
    condition: service_healthy
```

**Warning signs:**
- Occasional "connection refused to proxy" errors only on cold start
- Works reliably after `docker compose restart` (proxy already warm)
- Flaky CI/CD builds that pass on retry

**Phase to address:**
Proxy foundation phase — wire health check before writing any sandbox startup logic.

---

### Pitfall 4: Proxy Environment Variables Not Propagated to All Package Managers

**What goes wrong:**
Setting `HTTP_PROXY` and `HTTPS_PROXY` environment variables in the container is necessary but not sufficient. Package managers use inconsistent conventions:

- `curl`, `wget`: respect both upper and lowercase variants
- `npm`: does NOT honor `HTTP_PROXY`/`HTTPS_PROXY` by default in all versions — requires `npm config set proxy` or `.npmrc`
- `pip`: requires `http_proxy` (lowercase) in many versions
- `cargo`: respects `HTTPS_PROXY` but also needs `http.proxy` in `.cargo/config.toml` for some registry operations
- `git`: requires `http.proxy` config or `GIT_HTTP_PROXY_AUTHMETHOD` env var
- `go get`: respects `GOPROXY` — may bypass `HTTPS_PROXY` entirely
- mise itself: uses `HTTP_PROXY`/`HTTPS_PROXY` but only after activation

**Why it happens:**
There is no universal standard for proxy environment variables. Each tool ecosystem evolved independently. One correctly configured `HTTP_PROXY` looks complete but leaves several tools bypassing the proxy entirely.

**How to avoid:**
Set both case variants (`HTTP_PROXY`, `HTTPS_PROXY`, `http_proxy`, `https_proxy`) in the container environment. Add a global git config with `http.proxy`. Add `.cargo/config.toml` with `[http] proxy = "..."`. Test proxy enforcement by watching Squid access logs for each package manager during integration testing, not just manual spot checks.

**Warning signs:**
- Squid ACL blocks a domain but `go get` still fetches it
- `cargo build` succeeds even when Squid is stopped
- Proxy logs show traffic only from curl/wget but not from npm/pip

**Phase to address:**
Proxy integration phase — after proxy is running, add a per-package-manager verification step to the test suite.

---

### Pitfall 5: mise Home Directory Shadowed by devcontainer/Volume Mount

**What goes wrong:**
The current compose file mounts `mise-state:/home/dev/.mise`. When the container image pre-installs language runtimes into `~/.local/share/mise/installs` (the default user install path) during `docker build`, those pre-installed tools are hidden by the volume mount at container runtime. The agent starts with an empty mise state and must re-download all runtimes on first use — breaking offline/air-gapped scenarios and making cold-start latency unpredictable.

**Why it happens:**
The volume mount is correct (it persists mise state across runs), but the Docker image build installs into the path that the volume then shadows. The mise Docker cookbook calls this out explicitly: pre-installed tools must go to the system path (`/usr/local/share/mise/installs`) via `mise install --system` to survive the mount.

**How to avoid:**
Use `mise install --system` in the Dockerfile. Set `MISE_DATA_DIR`, `MISE_CONFIG_DIR`, and `MISE_CACHE_DIR` to paths outside of `/home/dev` in the image. The system install path `/usr/local/share/mise/installs` is not affected by home directory volume mounts.

**Warning signs:**
- `node --version` or `python --version` fails on first container start despite being in the Dockerfile
- `mise list` shows nothing when a fresh volume is attached
- Works after `mise install` is run manually inside the container

**Phase to address:**
Language runtime installation phase — verify with a fresh named volume (not reusing a previously populated volume) before declaring runtimes "installed."

---

### Pitfall 6: iptables Rules Interact with Docker's Own NAT Rules After Migration

**What goes wrong:**
The existing `init-firewall.py` takes care to save and restore Docker's DNS NAT rules (`127.0.0.11` entries) when flushing iptables. After migrating to proxy-based egress, if any iptables remnants remain in the image (or if `init-firewall.py` is still executed), Docker's bridge network NAT rules can be corrupted. The symptom is broken inter-container DNS resolution — sandbox containers can no longer resolve `squid` (the proxy container's hostname) because Docker's embedded DNS stops working.

**Why it happens:**
Docker injects NAT rules into the host's iptables to enable embedded DNS (`127.0.0.11:53`). Any flush-and-rebuild of iptables inside a container that has NET_ADMIN affects only the container's network namespace, but the save/restore logic in `init-firewall.py` is fragile. In the proxy-based architecture, if containers no longer need NET_ADMIN (the goal), `init-firewall.py` should not run at all.

**How to avoid:**
When migrating to proxy-based egress, remove the call to `init-firewall.py` from container entrypoints completely. Do not run both proxy-based egress and iptables-based egress simultaneously. The migration is a clean cutover. Drop `NET_ADMIN` and `NET_RAW` from the container capabilities as a forcing function.

**Warning signs:**
- `getent hosts squid` fails inside sandbox container
- `curl http://squid:3128` gives "Could not resolve host: squid"
- Works immediately after container restart without iptables initialization

**Phase to address:**
Migration phase — verify DNS resolution of the proxy container hostname is the first test after removing iptables code.

---

### Pitfall 7: Sandbox Agents Modifying Squid Configuration or Proxy Routing

**What goes wrong:**
If the Squid container's configuration directory is writable by a container the agent can reach (via a shared volume or a writable bind mount), a malicious or confused agent could modify `squid.conf`, reload Squid, and whitelist arbitrary domains. Similarly, if the agent container has write access to `/etc/hosts` or DNS configuration, it can route around the proxy entirely.

**Why it happens:**
Developers share a volume for convenience (e.g., "one ACL config file shared between proxy and sandbox"). The sandbox container only needs to read the proxy address, not write proxy configuration.

**How to avoid:**
Mount Squid configuration as `:ro` (read-only) in any container that is not the Squid container itself. Never mount the proxy config volume into sandbox containers at all. The INNOQ sandbox report explicitly notes: "Configuration files must be unmodifiable by sandboxed agents." Verify with `docker inspect` that no sandbox container has write access to proxy config paths.

**Warning signs:**
- Compose file shows a shared volume mounted `rw` in both proxy and sandbox services
- Policy/ACL files in a shared volume rather than baked into the proxy image
- Agent able to run `echo "acl all dst 0.0.0.0/0" > /squid/conf/squid.conf`

**Phase to address:**
Hardening phase — audit all volume mounts for write access before multi-agent testing.

---

### Pitfall 8: DNS Tunneling as Remaining Exfiltration Channel

**What goes wrong:**
Proxy-based egress control enforces TCP egress through the proxy, but UDP port 53 (DNS) is typically allowed directly for resolution to work. An agent aware of this can exfiltrate data via DNS queries to a controlled domain (e.g., `<base64-payload>.attacker.com`). This is a slow channel but a real one.

**Why it happens:**
DNS must be allowed for the sandbox to function at all (resolving package registry hostnames, etc.). The `init-firewall.py` explicitly allows UDP/53 outbound. In the proxy architecture, the sandbox container still needs DNS — the proxy itself resolves hostnames — but the *sandbox container* may not need direct DNS access if it uses the proxy for all resolution.

**How to avoid:**
In the proxy architecture, restrict sandbox containers to use only the Docker embedded DNS resolver (`127.0.0.11`) and block direct outbound UDP/53 from sandbox containers at the Docker network level or with a minimal iptables rule (if NET_ADMIN is retained for this purpose). Alternatively, accept this as out-of-scope for the threat model and document it. The INNOQ report acknowledges DNS tunneling as a "remaining gap."

**Warning signs:**
- Threat model documentation that says "all egress controlled" without qualifying DNS
- Sandbox container's `/etc/resolv.conf` points to an external resolver rather than `127.0.0.11`

**Phase to address:**
Hardening phase — threat model documentation should explicitly state DNS tunneling position (mitigated or accepted risk).

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Reuse existing `init-firewall.py` alongside proxy | Faster migration, less to rewrite | Dual enforcement = double complexity, iptables conflicts with proxy routing, NET_ADMIN still required | Never — pick one approach |
| Bake Squid ACLs into image rather than a config file | Simpler deployment | Cannot update whitelist without rebuilding proxy image | Never for active use; acceptable for a fixed demo |
| Use `depends_on` without health check | Simpler compose file | Flaky cold-start races — hard to debug, intermittent failures | Never in the proxy dependency |
| Set only `HTTPS_PROXY` and not `http_proxy` (lowercase) | Looks complete | Several tools (pip, wget, some curl builds) only check lowercase | Never — set both case variants |
| Mount mise cache volume over `~/.mise` without using `--system` installs | Volume persists mise state | Runtimes disappear on fresh volume, confusing first-run experience | Never for distributed image; acceptable for personal single-machine use |

---

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| npm through Squid | Set `HTTP_PROXY` env only | Also set via `npm config set proxy` and `npm config set https-proxy` in Dockerfile; some npm versions ignore env vars |
| Cargo through Squid | Set `HTTPS_PROXY` env only | Add `[http]\nproxy = "http://squid:3128"` to `/home/dev/.cargo/config.toml` in image |
| go modules through Squid | Set `HTTPS_PROXY` env | `GOPROXY` may override; set `GOPROXY=https://proxy.golang.org,direct` and ensure `proxy.golang.org` is whitelisted, or set `GOPROXY=direct` with proxy env |
| git through Squid | None | `git config --global http.proxy http://squid:3128` in image Dockerfile |
| mise install through Squid | Set `HTTP_PROXY` env only | mise respects env vars but verify `mise install` works with proxy before assuming |
| Docker BuildKit during image build | BuildKit ignores proxy on cache hits | Use `--no-cache` when testing proxy configuration; BuildKit caches aggressively |

---

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| Squid disk cache with many simultaneous agents | Package downloads slow down linearly with agent count; disk I/O saturation | Tune `cache_mem` upward (e.g., 256MB) before increasing `cache_dir` size; mount cache dir on tmpfs for dev use | Noticeable at 3+ simultaneous agents doing heavy installs |
| DNS resolution at container start time (existing iptables pattern) | Startup fails if DNS is slow or policy uses IP-based domains that have changed | Proxy-based architecture eliminates this: Squid resolves hostnames, not the sandbox | Per-container on every restart |
| Large `cache_dir` on slow storage | First-use latency for Squid cache init is slow | Keep `cache_dir` small (512MB) or disable disk cache for local dev (use `cache_mem` only) | First boot of proxy container after clearing volumes |

---

## Security Mistakes

| Mistake | Risk | Prevention |
|---------|------|------------|
| Allowing CONNECT on all ports (not just 443/80) | Agent tunnels arbitrary TCP to exfiltration endpoints on non-standard ports | `acl SSL_ports port 443` + `http_access deny CONNECT !SSL_ports` in squid.conf |
| Shared `docker network` between proxy and untrusted containers without network segmentation | Agents can attempt connections to other services on the same Docker network | Use a dedicated internal Docker network for proxy; only expose port 3128 from Squid |
| Proxy container accessible from the host without authentication | Other processes on the host can use the proxy to bypass their own network restrictions | Bind Squid to the internal Docker network only, not `0.0.0.0`; add `http_access deny` for non-sandbox source IPs |
| Credential volumes mounted alongside proxy config | Agent reads API keys from mounted credential volume and exfiltrates via a whitelisted domain | Credential volumes use `:ro` mounts and contain only files the agent specifically needs; avoid mounting the entire `~/.claude` directory if only the auth token is needed |

---

## "Looks Done But Isn't" Checklist

- [ ] **Proxy enforcement:** Often appears to work because the agent makes successful requests — but those requests may bypass the proxy entirely. Verify by stopping the Squid container and confirming sandbox network requests fail.
- [ ] **mise runtimes pre-installed:** `mise list` inside the container shows tools, but if tested with a reused named volume the tools may be from a previous build, not the current image. Test with `docker volume rm` of the mise volume, then start fresh.
- [ ] **Package managers through proxy:** Squid access log shows hits only from curl — npm, cargo, go are going direct. Inspect Squid access log (`/var/log/squid/access.log`) during a full `npm install` to confirm.
- [ ] **Read-only rootfs:** Container starts successfully but agents can still write to `/tmp`, `/home/dev`, `/workspace`. These should be explicit and intentional writable exceptions — document them.
- [ ] **Multi-agent concurrency:** Tested with one agent at a time. Race conditions (proxy startup, volume contention, PID limit hits) only appear under simultaneous load. Run 3+ agents concurrently before declaring multi-agent support complete.
- [ ] **Capability removal:** `NET_ADMIN` removed from sandbox containers in compose file, but the `init-firewall.py` entrypoint still attempts to run (and silently fails). Confirm entrypoint does not call firewall init after migration.

---

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| SSL-bump implemented, now breaking package managers | HIGH | Remove ssl-bump config entirely, switch to splice/peek mode, rebuild proxy image, re-test all package managers |
| mise runtimes hidden by volume mount | LOW | `mise install --system` in Dockerfile rebuild; existing user volumes continue to work (user installs take priority over system) |
| iptables/proxy dual enforcement causing DNS failures | MEDIUM | Remove `init-firewall.py` call from entrypoint, drop NET_ADMIN, rebuild sandbox image, test from clean compose state |
| npm bypassing proxy silently | LOW | Add explicit npm proxy config to Dockerfile, rebuild base image |
| Squid startup race causing flaky agent starts | LOW | Add health check + `service_healthy` condition to compose; no image rebuild needed |

---

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| CONNECT tunneling scope (Pitfall 1) | Proxy foundation — document threat model | Review `SECURITY.md` in Squid config against stated scope |
| No SSL-bump decision (Pitfall 2) | Proxy foundation — architectural decision record | Confirm `ssl_bump` absent from squid.conf |
| Proxy startup race (Pitfall 3) | Proxy foundation — health check wiring | Stop proxy, confirm sandbox fails to start; restart proxy, confirm sandbox starts |
| Package manager proxy propagation (Pitfall 4) | Proxy integration — per-package-manager testing | Squid access log shows entries from npm, cargo, git, pip during installs |
| mise home directory shadowing (Pitfall 5) | Language runtime installation — fresh volume test | `docker volume rm mise-state && docker compose up` — runtimes present immediately |
| iptables migration conflicts (Pitfall 6) | Migration phase — clean cutover | `docker inspect` shows no NET_ADMIN on sandbox; `getent hosts squid` works inside sandbox |
| Proxy config writability (Pitfall 7) | Hardening — volume audit | `docker inspect` shows all proxy config mounts as `:ro` in sandbox services |
| DNS tunneling channel (Pitfall 8) | Hardening — threat model documentation | Threat model doc explicitly states DNS tunneling position |

---

## Sources

- [Squid SSL-Bump explicit configuration](https://wiki.squid-cache.org/ConfigExamples/Intercept/SslBumpExplicit) — official Squid wiki, certificate chain requirements
- [Squid SSL-Bump feature overview](https://wiki.squid-cache.org/Features/SslBump) — HSTS incompatibility, certificate generation
- [Docker proxy configuration](https://docs.docker.com/engine/cli/proxy/) — official Docker docs, env var propagation
- [Docker Compose startup ordering](https://docs.docker.com/compose/how-tos/startup-order/) — `service_healthy` condition
- [mise Docker cookbook](https://mise.jdx.dev/mise-cookbook/docker.html) — system install path, home directory mount caveat
- [salrashid123/squid_proxy](https://github.com/salrashid123/squid_proxy) — production warnings about SSL intercept, no-entrypoint issues
- [Docker network/firewall iptables](https://docs.docker.com/engine/network/firewall-iptables/) — Docker NAT rule interaction
- [INNOQ: sandboxed coding agents with network control (2026-03)](https://www.innoq.com/en/blog/2026/03/dev-sandbox-network/) — real-world implementation: nftables persistence, config immutability, DNS gap
- [Docker sandbox network policies](https://docs.docker.com/ai/sandboxes/network-policies/) — CONNECT-only allowlist pattern
- [ScaleSec: Network Security and Squid](https://scalesec.com/blog/the-missing-half-network-security-and-squid/) — ACL rule ordering, CONNECT port restrictions
- npm proxy bug report: [npm/cli#6930](https://github.com/npm/cli/issues/6930) — env var ignored in certain npm versions
- [Docker Compose health checks](https://last9.io/blog/docker-compose-health-checks/) — `service_healthy` depends_on pattern
- Existing codebase: `images/base/init-firewall.py` — identifies specific Docker DNS NAT restoration pattern that must be preserved or cleanly removed

---
*Pitfalls research for: container-based coding agent sandboxes, proxy egress migration*
*Researched: 2026-03-24*
