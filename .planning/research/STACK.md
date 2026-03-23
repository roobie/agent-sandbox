# Stack Research

**Domain:** Container-based AI coding agent sandbox with proxy egress control
**Researched:** 2026-03-24
**Confidence:** HIGH (core stack), MEDIUM (specific versions), LOW (squid conf patterns — verified via multiple community sources but not official benchmarks)

---

## Recommended Stack

### Core Technologies

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| Debian bookworm slim | 12 (bookworm-slim) | Sandbox container base image | glibc environment expected by most dev toolchains; better package compatibility than Alpine for agent workloads; slim variant balances size with package availability. Already validated in existing codebase. |
| Squid | 5.7 (Debian bookworm apt) | Shared egress proxy container | Standard, production-proven HTTP/HTTPS forward proxy with mature ACL system. `dstdomain` ACL supports domain-based whitelisting out of the box. No SSL bump needed for this threat model — CONNECT tunnel suffices for HTTPS. Available as `squid` or `squid-openssl` in Debian bookworm (5.7-2+deb12u5). |
| Docker Engine | 27+ | Container runtime | Required. No alternative in scope. Compose v2 (bundled as `docker compose`) for multi-container orchestration. |
| Docker Compose (v2) | Compose spec 3.x | Multi-container orchestration | Declares sandbox containers + shared proxy + Docker network. Compose v2 is the current standard (built-in to Docker CLI, not standalone). |
| mise | latest stable (2025.x) | Runtime version management + host-side task orchestration | Already in use for tool installation inside agent containers (Claude image). Naturally extends to host-side `mise tasks` for sandbox lifecycle (build, run, stop, proxy management). Replaces Makefile/justfile for this project. |
| Python 3.13 | 3.13.x | Build automation script (images/build.py) | Already used for `images/build.py`. Stdlib only — no heavyweight framework needed. Keep as-is. |

### Proxy Container

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| `ubuntu/squid` Docker image | `5.2-22.04_beta` (Canonical) | Pre-built Squid image OR build own from Debian bookworm | Canonical maintains this with security patches. Alternative: install `squid` via apt in a Debian bookworm container (gives 5.7) for consistency with sandbox base. Use `ubuntu/squid` if you want a maintained upstream image; build from bookworm if you prefer one base distro. |
| Squid ACL files | n/a | Domain whitelist/blacklist config | Mount a `whitelist.acl` file into the proxy container. Squid reads it at startup. Hot-reloading via `squid -k reconfigure`. Managed by policy-as-JSON concept evolved from existing `policy.json`. |

### Language Runtimes (inside sandbox, via mise)

| Runtime | Version | Purpose | Why |
|---------|---------|---------|-----|
| Node.js | 22 LTS | Agent tooling (Claude Code runs on Node) | Node 22 is the current LTS. Claude Code requires Node. |
| Python | 3.13 | General scripting, uv, agent scripts | Latest stable. uv (Astral) replaces pip/virtualenv for speed. |
| uv | 0.6.x (latest) | Python package management | Installs in milliseconds vs pip. Already used in Claude agent image (`mise use -g uv@$UV_VERSION`). |
| Go | 1.24 | Go project support | Current stable. |
| Rust | stable (1.84+) | Rust project support | mise `rust = "stable"` tracks stable channel. |
| Bun | 1.2.x | JS runtime/package manager alternative | Fast installs, used by some agent workflows. |
| rust-analyzer | latest | Rust LSP for agent code intelligence | Installed via mise `cargo` backend or aqua. |

### Container Hardening Layer

| Control | Mechanism | Notes |
|---------|-----------|-------|
| Non-root execution | UID/GID 500 `dev` user, `gosu` for entrypoint UID adjustment | Already implemented in base image. |
| Capability drop | `--cap-drop=ALL` in Compose | Proxy-based egress eliminates need for `NET_ADMIN`/`NET_RAW` (currently required for iptables). This is the key capability win from switching to Squid. |
| No new privileges | `--security-opt=no-new-privileges` | Prevents privilege escalation via setuid binaries. |
| Read-only rootfs | `--read-only` + `--tmpfs /tmp` | Filesystem immutability at runtime. |
| Seccomp | Docker default profile | Default Docker seccomp blocks ~44 syscalls. Custom profile optional for stricter hardening. |
| Resource limits | `--memory`, `--cpus`, `--pids-limit` | Configurable per sandbox in Compose or `docker run`. |
| Execution timeout | `timeout` command or PID 1 wrapper | Prevents runaway agent processes. |

### Development/Host Tooling

| Tool | Purpose | Notes |
|------|---------|-------|
| mise (host) | Task runner: `mise run sandbox:build`, `mise run proxy:start`, etc. | `mise.toml` at repo root defines all lifecycle tasks. Already present. |
| justfile | Current task runner (existing) | Will be superseded by mise tasks; keep during transition. |
| Docker Compose | Container lifecycle | `docker compose up/down` wrapped in mise tasks. |
| GitHub Actions | CI: build + publish images | On push to main: build images, push to GHCR. |

---

## Installation

```bash
# Squid in proxy container (Debian bookworm base)
apt-get install -y --no-install-recommends squid

# OR use Canonical maintained image
docker pull ubuntu/squid:5.2-22.04_beta

# Runtimes inside sandbox (via mise)
mise use -g node@22
mise use -g python@3.13
mise use -g go@1.24
mise use -g rust@stable
mise use -g bun@1
mise use -g uv@latest

# Claude Code (existing pattern)
mise use -g claude-code@latest
```

---

## Alternatives Considered

| Category | Recommended | Alternative | Why Not |
|----------|-------------|-------------|---------|
| Egress control | Squid (shared proxy) | Per-container iptables/ipset | iptables requires `NET_ADMIN` capability per container, doesn't scale cleanly to N simultaneous sandboxes, DNS resolution at startup is fragile for dynamic IPs. Squid's ACL system handles HTTPS CONNECT natively without capability elevation. |
| Egress control | Squid (explicit forward) | Transparent proxy (iptables redirect to proxy) | Transparent proxy requires `NET_ADMIN` in the sandbox — defeats the purpose. Explicit proxy (HTTP_PROXY env vars) is simpler, requires no host network manipulation, and is universally supported by curl/npm/pip/cargo. |
| Squid config | No SSL bump (CONNECT tunnel only) | SSL bump with CA cert injection | SSL bump breaks certificate pinning, requires distributing a custom CA into every sandbox, adds complexity and attack surface. Domain whitelisting via `dstdomain` works for CONNECT tunnels — Squid sees the SNI/hostname from the CONNECT request. Sufficient for this threat model. |
| Proxy base image | Debian bookworm with `apt install squid` | `ubuntu/squid:5.2-22.04_beta` | Both are valid. Building from bookworm aligns with sandbox base, simplifies one-distro maintenance. Ubuntu/squid is fine if you want Canonical's patch cadence. |
| Squid version | 5.7 (bookworm apt) | Squid 7.x (current upstream) | Squid 7 is the upstream head but not yet packaged in Debian stable. Squid 5.7 in bookworm is LTS-supported and sufficient for explicit forward proxy ACL use case. |
| Runtime mgmt | mise | asdf / nvm / pyenv | mise is already in use in the Claude agent image. Single tool for all runtimes + task runner. Faster (Rust), better DX. |
| Build automation | Python (images/build.py) | Shell script / Makefile | Python is already in use. Good for complex multi-image build orchestration. Keep as-is. |
| Task runner | mise tasks | justfile (current) | mise tasks integrate tool version context automatically. justfile can be kept during transition or removed. |

---

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| `NET_ADMIN` + iptables per container | Requires elevated capability, doesn't compose well across N sandboxes, init-firewall.py adds startup complexity and failure modes | Shared Squid proxy with `HTTP_PROXY` env vars — zero capability requirement on sandbox containers |
| SSL bump / MITM proxy | Breaks certificate pinning (npm, cargo, GitHub APIs all pin or use HSTS), requires CA cert distribution inside sandbox, adds significant configuration complexity | Plain CONNECT tunnel through Squid with `dstdomain` ACL — sufficient for domain whitelisting without decryption |
| gVisor / Kata Containers | Adds significant operational complexity, incompatible with many base images and tool behaviors, hard to run locally on macOS/Windows | Docker with `--cap-drop=ALL`, seccomp, `--read-only` — sufficient for the stated threat model (prevent egress, not prevent container escape by a malicious host binary) |
| Kubernetes | This is a local developer tool, not a production workload cluster | Docker Compose — right scope |
| Per-sandbox proxy sidecar | N sidecars = N proxy configs to manage, N points of failure, higher resource use | Single shared Squid container per host, all sandboxes route through it on a Docker bridge network |
| Alpine Linux base | Missing glibc; mise and many agent CLIs (Claude Code, GitHub CLI) expect glibc; causes hard-to-debug binary incompatibilities | Debian bookworm-slim — glibc, good package availability, reasonable image size |

---

## Stack Patterns by Variant

**If running multiple simultaneous agent sandboxes:**
- All sandboxes join a shared `proxy-net` Docker bridge network
- Single Squid container on that network, DNS name `squid-proxy`
- Each sandbox sets `HTTP_PROXY=http://squid-proxy:3128` and `HTTPS_PROXY=http://squid-proxy:3128`
- Single `whitelist.acl` file controls all sandboxes — one place to manage egress policy

**If running a single sandbox at a time:**
- Same architecture, simpler Compose file
- Proxy container can be started once and left running (`restart: unless-stopped`)
- Sandbox containers start/stop independently

**If sandbox needs internet access to package registries only:**
- Whitelist: `pypi.org`, `npmjs.com`, `crates.io`, `pkg.go.dev`, `api.anthropic.com`, `github.com`
- Deny everything else
- No SSL bump needed — CONNECT tunnel to these domains works via `dstdomain` ACL

**If host is macOS (via Colima or Docker Desktop):**
- Proxy container resolves on Docker bridge network identically to Linux
- `HTTP_PROXY=http://squid-proxy:3128` works without modification
- No iptables manipulation needed — this is another win for proxy-based approach

---

## Version Compatibility

| Package | Compatible With | Notes |
|---------|-----------------|-------|
| Squid 5.7 (Debian bookworm) | Docker 27+ | No known incompatibilities. |
| mise 2025.x | Node 22, Python 3.13, Rust stable | mise core backends track upstream release channels. |
| Docker Compose v2 | Compose spec 3.8+ | v2 syntax; avoid deprecated `version:` top-level field. |
| Claude Code (latest) | Node 22 LTS | Claude Code is distributed via npm, requires Node. Installed via `mise use -g claude-code`. |
| uv 0.6.x | Python 3.13 | uv is runtime-version-agnostic; works with any Python >= 3.8. |
| Debian bookworm-slim | gosu 1.16 | gosu available in bookworm repos for entrypoint UID/GID adjustment. |

---

## Key squid.conf Pattern (No SSL Bump)

For reference — the explicit forward proxy config without decryption:

```squid
# Explicit forward proxy, whitelist-only, no SSL interception
http_port 3128

# ACL: safe ports
acl Safe_ports port 80
acl Safe_ports port 443
acl CONNECT method CONNECT

# Load domain whitelist from file
acl allowed_domains dstdomain "/etc/squid/whitelist.acl"

# Deny non-whitelisted ports
http_access deny !Safe_ports

# Allow CONNECT (HTTPS tunnels) only to whitelisted domains
http_access allow CONNECT allowed_domains
http_access deny CONNECT

# Allow HTTP to whitelisted domains
http_access allow allowed_domains

# Deny everything else
http_access deny all

# Disable caching (sandbox use case — freshness matters more than performance)
cache deny all

# Access log for observability
access_log /var/log/squid/access.log squid
```

`whitelist.acl` (one entry per line, leading dot = subdomain wildcard):
```
.github.com
.npmjs.com
.pypi.org
.files.pythonhosted.org
.crates.io
.static.crates.io
.pkg.go.dev
.sum.golang.org
.api.anthropic.com
.statsig.anthropic.com
.mise-versions.jdx.dev
```

**Critical:** `dstdomain` in Squid matches CONNECT tunnel destinations by hostname from the CONNECT request (not by decrypting the TLS payload). This is sufficient for whitelisting without SSL bump. Subdomain matching with leading `.` covers `npm.npmjs.com`, `registry.npmjs.com`, etc.

---

## Sources

- Squid ACL documentation — https://wiki.squid-cache.org/SquidFaq/SquidAcl (MEDIUM confidence — official Squid wiki)
- Squid dstdomain with CONNECT (no SSL bump) — https://wiki.squid-cache.org/Features/HTTPS (MEDIUM — official)
- Squid security best practice config — https://github.com/password123456/setup-squid-proxy-with-security-best-practice (MEDIUM — community, cross-validated with official docs)
- ubuntu/squid Docker Hub — https://hub.docker.com/r/ubuntu/squid (HIGH — Canonical official)
- Debian bookworm squid package — https://packages.debian.org/bookworm/squid — version 5.7-2+deb12u5 (HIGH — official Debian)
- Squid 7.x upstream — https://endoflife.date/squid (HIGH — release tracking)
- Docker seccomp profiles — https://docs.docker.com/engine/security/seccomp/ (HIGH — official Docker docs)
- Docker Compose networking — https://docs.docker.com/compose/how-tos/networking/ (HIGH — official)
- Docker proxy env vars — https://docs.docker.com/engine/cli/proxy/ (HIGH — official)
- mise documentation — https://mise.jdx.dev/ (HIGH — official, also cross-referenced via local docs/mise.reference.md)
- Existing codebase analysis — images/base/Dockerfile, images/agents/claude/Dockerfile, docker-compose.yml, images/base/init-firewall.py (HIGH — ground truth)

---

*Stack research for: Container-based AI coding agent sandbox with Squid proxy egress control*
*Researched: 2026-03-24*
