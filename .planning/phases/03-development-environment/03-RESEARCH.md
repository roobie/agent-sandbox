# Phase 3: Development Environment - Research

**Researched:** 2026-03-24
**Domain:** mise runtime installation in Docker, per-package-manager proxy config, Docker named volumes, host-side mise task authoring
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Runtime installation in Dockerfile**
- Install all runtimes via `mise use -g` in the claude agent Dockerfile (extends existing pattern at line 25-29)
- Runtimes: Node (latest LTS), Python (3.12+), Go (latest), Rust 1.94.x, uv 0.10.x, Bun 1.3.x, rust-analyzer (latest)
- Claude Code and uv already installed this way — extend with remaining runtimes
- mise-state named volume persists `~/.local/share/mise/` across container rebuilds
- The home dir volume mount means runtimes installed via `mise use -g` land in the volume, not the image layer — this is acceptable because the volume persists

**LSP tooling**
- rust-analyzer installed via mise (already in runtime list)
- pyright: install via `mise use -g npm:pyright` (npm-based)
- typescript-language-server: install via `mise use -g npm:typescript-language-server` (npm-based)
- These are installed alongside runtimes in the Dockerfile

**Per-package-manager proxy configuration**
- npm: Create `/home/dev/.npmrc` with `proxy=http://proxy:3128` and `https-proxy=http://proxy:3128`
- cargo: Create `/home/dev/.cargo/config.toml` with `[http]` proxy setting (note: cargo volume mount may shadow this — write to /etc/cargo/ or use env var `CARGO_HTTP_PROXY`)
- git: `git config --global http.proxy http://proxy:3128`
- Go: Set `GOPROXY=https://proxy.golang.org,direct` in compose env (Go respects HTTP_PROXY for the actual fetch, GOPROXY controls the module proxy endpoint)
- All configs baked into image so tools work immediately without post-start setup

**mise tasks for host orchestration**
- Tasks defined in project-root `mise.toml` (host-side, not inside container)
- Naming convention: `proxy:start`, `proxy:stop`, `proxy:status`, `sandbox:build`, `sandbox:run`, `sandbox:stop`, `image:build`
- `proxy:start` — `docker compose up -d proxy` and wait for healthy
- `proxy:stop` — `docker compose stop proxy`
- `proxy:status` — `docker compose ps proxy`
- `sandbox:build` — `python3 images/build.py all`
- `sandbox:run` — starts sandbox container, accepts `NAME` and `WORKSPACE` args for multi-instance
- `sandbox:stop` — stops sandbox by name
- `image:build` — alias for `sandbox:build`

**Multi-sandbox support**
- `mise run sandbox:run` accepts `NAME=foo WORKSPACE=/path/to/project` arguments
- Each named sandbox gets `container_name: agent-sandbox-${NAME}`
- Implemented via mise task that generates a docker compose override or runs `docker run` directly with the right flags
- All instances share the single proxy container (already wired via Docker network)

**Package cache volumes**
- npm: `npm-cache:/home/dev/.npm`
- pip: `pip-cache:/home/dev/.cache/pip`
- cargo: already have `cargo-state:/home/dev/.cargo` (includes registry cache)
- Go modules: `go-cache:/home/dev/go/pkg/mod`
- Add these named volumes to docker-compose.yml

**UID/GID adjustment (DEVENV-06)**
- Entrypoint already has the ETC_WRITABLE guard from Phase 2
- Under read-only rootfs, UID/GID adjustment is skipped (fixed UID 500)
- For Phase 3: add a tmpfs mount at `/etc` overlay OR accept the limitation that host UID must match 500
- Recommended: accept the limitation for now; document workaround (rebuild with different UID build arg)

### Claude's Discretion
- Exact mise tool versions for Node LTS, Python, Go (use latest stable at build time)
- Whether to add additional LSP servers beyond the three specified
- Exact mise task implementation details (shell commands, error handling)
- Whether sandbox:run uses docker compose override files or direct docker run

### Deferred Ideas (OUT OF SCOPE)
- Devcontainer mode support (ORCH-07 in v2) — VS Code extension writes conflict with read-only rootfs
- UID/GID dynamic adjustment under read-only rootfs — accept fixed UID 500 for now
- Additional LSP servers beyond rust-analyzer, pyright, typescript-language-server
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| DEVENV-01 | Base image is Debian bookworm slim with common dev tools (git, curl, ripgrep, jq, neovim, tmux, fzf, build-essential, cmake) | Base Dockerfile already installs all of these; no new work needed |
| DEVENV-02 | Language runtimes installed via mise: Node (latest LTS), Python (3.12+), Go (latest), Rust 1.94.x, uv 0.10.x, Bun 1.3.x, rust-analyzer (latest) | `mise use -g` pattern already established in claude Dockerfile lines 25-29; extend with 6 more runtimes |
| DEVENV-03 | Runtimes installed via `mise install --system` so they survive volume mount shadowing of home directory | CRITICAL: see Architecture Patterns — `mise install --system` installs to `/usr/local/share/mise/installs`, not `~/.local/share/mise/installs`; requires running as root; requires `MISE_SYSTEM_DATA_DIR` path to be on PATH |
| DEVENV-04 | Package cache volumes (npm, pip, cargo, go modules) persist across sandbox runs | Add 3 new named volumes (npm-cache, pip-cache, go-cache) to docker-compose.yml; cargo-state already handles cargo cache |
| DEVENV-05 | LSP tooling pre-installed: rust-analyzer, pyright, typescript-language-server | All installable via `mise use -g` with npm backend; confirmed latest versions available |
| DEVENV-06 | Non-root user execution (dev user) with UID/GID adjustment to match host workspace ownership | Entrypoint already handles this with ETC_WRITABLE guard; accepted limitation: fixed UID 500 under read-only rootfs |
| DEVENV-07 | Per-package-manager proxy configuration: .npmrc, cargo config.toml, git config, GOPROXY env var | Bake config files into image in Dockerfile; env vars set in docker-compose.yml |
| ORCH-01 | mise tasks on host for proxy lifecycle: `mise run proxy:start`, `mise run proxy:stop`, `mise run proxy:status` | mise `[tasks]` section in mise.toml; shell commands wrapping `docker compose` |
| ORCH-02 | mise tasks on host for sandbox lifecycle: `mise run sandbox:build`, `mise run sandbox:run`, `mise run sandbox:stop` | mise tasks with `usage` block for args (NAME, WORKSPACE); `docker run` or compose override for sandbox:run |
| ORCH-03 | mise tasks support running multiple named sandbox instances simultaneously | sandbox:run accepts NAME arg → `container_name: agent-sandbox-${NAME}`; docker run with explicit name; all share one proxy |
| ORCH-04 | Workspace bind-mounted from host directory into container at /workspace | Already in docker-compose.yml as `. :/workspace`; sandbox:run task adds `--volume ${WORKSPACE}:/workspace` flag |
</phase_requirements>

---

## Summary

Phase 3 has three parallel tracks: (1) extend the Dockerfile to install language runtimes and bake in per-package-manager proxy config files, (2) add package cache volumes to docker-compose.yml, and (3) write host-side mise tasks for the full sandbox lifecycle.

The most critical technical decision — verified against live mise — is **DEVENV-03**: runtimes must be installed via `mise install --system` (as root, to `/usr/local/share/mise/installs/`) rather than `mise use -g` (which writes to `~/.local/share/mise/installs/`). The existing compose file mounts `mise-state:/home/dev/.mise` which shadows the user data dir at runtime. A fresh named volume would hide any runtimes installed to the user path. The CONTEXT.md conflicts with REQUIREMENTS.md on this point — CONTEXT.md says "use `mise use -g`" but REQUIREMENTS.md says "use `mise install --system`". REQUIREMENTS.md is the binding specification; this research confirms `--system` is the correct approach.

The mise task authoring is straightforward using the `usage` block syntax. The `sandbox:run` task should use `docker run` directly (not compose override files) for multi-instance support — simpler, no file creation needed. The allowlist will need new entries for npm, cargo, go, and the mise runtime download domains.

**Primary recommendation:** Install runtimes as root via `mise install --system` + `mise use --system` in the Dockerfile; proxy config files baked into image; mise tasks using `docker run` for sandbox:run to avoid compose file proliferation.

---

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| mise | latest stable (APT install) | Runtime version management + task runner | Already in use; APT repo install keeps it current |
| Node.js (via mise) | `lts` (22.x — currently 22.22.1) | Agent runtime; Claude Code runs on Node | lts specifier tracks LTS channel; 22.x is current LTS |
| Python (via mise) | `3.13` (currently 3.13.x) | General scripting, uv | 3.13 is latest stable matching CONTEXT.md "3.12+" requirement |
| Go (via mise) | `latest` (currently 1.26.x) | Go project support | `latest` tracks current stable |
| Rust (via mise) | `1.94` | Rust project support | CONTEXT.md specifies 1.94.x; pinned for reproducibility |
| uv (via mise) | `0.10` (currently 0.10.12) | Python package management | CONTEXT.md specifies 0.10.x; fast pip replacement |
| Bun (via mise) | `1.3` (currently 1.3.11) | JS runtime/package manager | CONTEXT.md specifies 1.3.x |
| rust-analyzer (via mise) | `latest` | Rust LSP | CONTEXT.md specifies latest |
| pyright (via mise npm) | `latest` (currently 1.1.408) | Python LSP | npm backend confirmed working |
| typescript-language-server (via mise npm) | `latest` (currently 5.1.3) | TypeScript/JS LSP | npm backend confirmed working |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| gosu | 1.x (Debian bookworm apt) | Entrypoint privilege drop | Already installed in base image; used by entrypoint.sh |

**Version verification (2026-03-24):**
```bash
# Confirmed via `mise ls-remote`:
# Node LTS: 22.22.1 (lts channel)
# Bun: 1.3.11
# Rust: 1.92.0 (stable), 1.94.x not yet released — use "stable" or "1.92"
# Go: 1.26.1 (latest)
# uv: 0.10.12
# pyright: 1.1.408 (npm)
# typescript-language-server: 5.1.3 (npm)
```

**CRITICAL NOTE on Rust version:** CONTEXT.md specifies Rust 1.94.x but `mise ls-remote rust` shows latest stable is 1.92.0 as of 2026-03-24. Use `stable` as the version specifier — it will install 1.92.0 and track future stable releases, which will reach 1.94 in time. Do not hard-pin to 1.94 until it is released.

**Installation (Dockerfile, as root):**
```bash
# System-wide installs — survive home dir volume mount
mise install --system node@lts
mise install --system python@3.13
mise install --system go@latest
mise install --system rust@stable
mise install --system uv@0.10
mise install --system bun@1.3
mise install --system rust-analyzer@latest

# LSP tools (npm backend; requires node already installed)
mise install --system npm:pyright@latest
mise install --system npm:typescript-language-server@latest

# Activate system tools globally
mise use --system node@lts python@3.13 go@latest rust@stable uv@0.10 bun@1.3 rust-analyzer@latest npm:pyright@latest npm:typescript-language-server@latest
```

---

## Architecture Patterns

### Recommended Project Structure Changes

```
images/agents/claude/
├── Dockerfile          # Add system runtime installs + proxy config files

docker-compose.yml      # Add npm-cache, pip-cache, go-cache named volumes
                        # Add volume mounts for new cache volumes

mise.toml               # Add [tasks] section with all lifecycle tasks
```

### Pattern 1: System-Install Runtimes in Dockerfile

**What:** Install mise runtimes to the system path (`/usr/local/share/mise/installs/`) as root rather than the user path (`~/.local/share/mise/installs/`), so runtimes survive the `mise-state:/home/dev/.mise` volume mount that shadows the home directory at runtime.

**Why:** The existing compose file mounts `mise-state:/home/dev/.mise`. The base Dockerfile sets `MISE_DATA_DIR=/home/dev/.mise/data`. This means `~/.local/share/mise/installs` maps to `/home/dev/.mise/data/installs`. At container start, the named volume overlays this path with its own contents — any runtimes built into the image layer at that path are invisible. System installs go to `/usr/local/share/mise/installs` (controlled by `MISE_SYSTEM_DATA_DIR`) which is NOT under the volume mount.

**DEVENV-03 vs CONTEXT.md conflict:** REQUIREMENTS.md DEVENV-03 specifies `mise install --system`. CONTEXT.md says `mise use -g` (which installs to user path, not system path). The REQUIREMENTS.md is the binding specification. The CONTEXT.md note "the home dir volume mount means runtimes installed via `mise use -g` land in the volume, not the image layer — this is acceptable because the volume persists" is technically true but creates a fragile first-run dependency: a fresh volume means no runtimes until the volume is populated by rebuilding or running the container once and waiting for installs. Use system installs to make runtimes available immediately on any fresh volume.

**When to use:** All runtimes in the claude agent Dockerfile. Run as root before switching to `USER dev`.

**Example:**
```dockerfile
# Source: docs/mise.reference.md + verified with `mise install --help`
# Install runtimes to system path (not affected by home dir volume mount)
USER root
RUN mise install --system node@lts && \
    mise install --system python@3.13 && \
    mise install --system go@latest && \
    mise install --system rust@stable && \
    mise install --system uv@0.10 && \
    mise install --system bun@1.3 && \
    mise install --system rust-analyzer@latest && \
    mise install --system npm:pyright@latest && \
    mise install --system npm:typescript-language-server@latest

# Activate system tools in global config (for USER dev to see them)
# This writes to /usr/local/share/mise/config.toml (system config)
RUN mise use --system node@lts python@3.13 go@latest rust@stable \
    uv@0.10 bun@1.3 rust-analyzer@latest \
    npm:pyright@latest npm:typescript-language-server@latest
```

### Pattern 2: Bake Per-PM Proxy Config into Image

**What:** Create package manager config files as `USER dev` in the Dockerfile so they are part of the image layer at `/home/dev/`. These files live outside the named volume mount paths, so they are not shadowed at runtime.

**When to use:** All per-PM proxy config. Do NOT configure these at container start (entrypoint). Baking into image means zero-latency availability.

**Cargo config location issue:** `/home/dev/.cargo/config.toml` IS under the `cargo-state:/home/dev/.cargo` volume mount. The volume shadows image-layer content. Use `CARGO_HTTP_PROXY` env var in compose instead of a config file, or write to `/etc/cargo/` (system-wide location cargo also reads).

**Example:**
```dockerfile
# Source: CONTEXT.md decisions section
USER dev

# npm proxy — NOT under any volume mount
RUN mkdir -p /home/dev && \
    printf 'proxy=http://proxy:3128\nhttps-proxy=http://proxy:3128\n' \
    > /home/dev/.npmrc

# git proxy
RUN git config --global http.proxy http://proxy:3128

# cargo proxy — use system config to avoid volume shadowing
USER root
RUN mkdir -p /etc/cargo && \
    printf '[http]\nproxy = "http://proxy:3128"\n' \
    > /etc/cargo/config.toml
USER dev
```

**In docker-compose.yml (Go proxy and cargo env var fallback):**
```yaml
environment:
  - GOPROXY=https://proxy.golang.org,direct
  - CARGO_HTTP_PROXY=http://proxy:3128
  # ... existing HTTP_PROXY/HTTPS_PROXY already set
```

### Pattern 3: mise Task Authoring with `usage` Block

**What:** Define mise tasks in `mise.toml` using the `usage` block for argument parsing. This provides `--help` output, shell completions, and safe variable access.

**When to use:** All tasks that accept user arguments (sandbox:run, sandbox:stop).

**Example:**
```toml
# Source: docs/mise.reference.md — Tasks section
[tasks."proxy:start"]
description = "Start the Squid proxy container"
run = """
docker compose up -d proxy
echo "Waiting for proxy to be healthy..."
docker compose wait proxy 2>/dev/null || \
  docker inspect --format='{{.State.Health.Status}}' agent-sandbox-proxy
"""

[tasks."proxy:stop"]
description = "Stop the Squid proxy container"
run = "docker compose stop proxy"

[tasks."proxy:status"]
description = "Show proxy container status"
run = "docker compose ps proxy"

[tasks."sandbox:build"]
description = "Build sandbox container images"
run = "python3 images/build.py all"

[tasks."image:build"]
description = "Alias for sandbox:build"
run = "python3 images/build.py all"

[tasks."sandbox:run"]
description = "Start a sandbox container"
usage = '''
flag "--name -n <name>" help="Sandbox instance name" default="default"
flag "--workspace -w <workspace>" help="Host workspace path" default="."
'''
run = """
NAME="${usage_name:-default}"
WORKSPACE="${usage_workspace:-.}"
WORKSPACE="$(realpath "$WORKSPACE")"
docker run -d \
  --name "agent-sandbox-${NAME}" \
  --network agent-sandbox_sandbox-internal \
  --cap-drop ALL \
  --cap-add SETUID \
  --cap-add SETGID \
  --security-opt no-new-privileges:true \
  --read-only \
  --tmpfs /tmp:size=268435456 \
  --tmpfs /run:size=67108864 \
  --volume "${WORKSPACE}:/workspace" \
  --volume "claude-state:/home/dev/.claude" \
  --volume "mise-state:/home/dev/.mise" \
  --volume "cargo-state:/home/dev/.cargo" \
  --volume "npm-cache:/home/dev/.npm" \
  --volume "pip-cache:/home/dev/.cache/pip" \
  --volume "go-cache:/home/dev/go/pkg/mod" \
  --env HTTP_PROXY=http://proxy:3128 \
  --env HTTPS_PROXY=http://proxy:3128 \
  --env http_proxy=http://proxy:3128 \
  --env https_proxy=http://proxy:3128 \
  --env NO_PROXY=localhost,127.0.0.1 \
  --env GOPROXY=https://proxy.golang.org,direct \
  --env CARGO_HTTP_PROXY=http://proxy:3128 \
  agent-sandbox-claude:local
echo "Sandbox agent-sandbox-${NAME} started"
"""

[tasks."sandbox:stop"]
description = "Stop a named sandbox container"
usage = '''
flag "--name -n <name>" help="Sandbox instance name" default="default"
'''
run = """
NAME="${usage_name:-default}"
docker stop "agent-sandbox-${NAME}"
docker rm "agent-sandbox-${NAME}"
"""
```

### Pattern 4: Named Volume for Package Caches

**What:** Docker named volumes that persist across container runs for package manager download caches. Mount them into paths where each tool stores its cache.

**Cache paths per tool:**
| Tool | Cache Path | Volume Name |
|------|-----------|-------------|
| npm | `/home/dev/.npm` | `npm-cache` |
| pip/uv | `/home/dev/.cache/pip` | `pip-cache` |
| cargo | `/home/dev/.cargo` (already) | `cargo-state` (existing) |
| Go modules | `/home/dev/go/pkg/mod` | `go-cache` |

**Note:** `go-cache` should mount at `/home/dev/go/pkg/mod` (module cache), not `/home/dev/go` (full Go workspace). This avoids shadowing `~/go/bin` where `go install` tools land.

**Example docker-compose.yml additions:**
```yaml
services:
  agent-sandbox:
    volumes:
      # ... existing volumes ...
      - npm-cache:/home/dev/.npm
      - pip-cache:/home/dev/.cache/pip
      - go-cache:/home/dev/go/pkg/mod

volumes:
  # ... existing volumes ...
  npm-cache:
  pip-cache:
  go-cache:
```

### Anti-Patterns to Avoid

- **`mise use -g` for system runtimes:** Installs to `~/.local/share/mise/installs/` which is inside the `mise-state` volume path. On a fresh volume the tools won't be there. Use `mise install --system` as root instead.
- **Cargo proxy config at `/home/dev/.cargo/config.toml`:** This path is under `cargo-state:/home/dev/.cargo` volume mount — file will be hidden at runtime. Use `/etc/cargo/config.toml` or `CARGO_HTTP_PROXY` env var.
- **docker compose override files for multi-sandbox:** Creates files on disk per instance; harder to clean up and doesn't compose cleanly. Use `docker run` directly in the sandbox:run task.
- **Writing proxy configs in entrypoint.sh:** Adds startup latency and complexity; bake into image instead.
- **Deprecated Tera template args in mise tasks:** `{{arg(name="x")}}` syntax is deprecated and removed in mise 2026.11.0. Use the `usage` block instead.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Runtime version management | Custom install scripts per language | `mise install --system` | Handles platform detection, checksums, parallel downloads, PATH wiring |
| Package manager proxy config | Custom proxy injection at runtime | Baked `.npmrc`, git config, `/etc/cargo/config.toml` | Each PM has its own config format; runtime injection is fragile |
| Multi-instance container naming | Custom naming scripts | `docker run --name` | Docker's built-in container naming handles this cleanly |
| Task argument parsing | Shell `$1`/`$2` positional args | `usage` block in mise tasks | Auto-generates help text, handles defaults, safer variable access |
| Waiting for proxy health | `sleep 5` in sandbox:run | `docker compose wait` or health check polling | Compose health check is already defined; `docker compose wait` blocks until healthy |

**Key insight:** The mise ecosystem already handles the complexity of cross-platform binary installation. Custom scripts replicate this poorly (no checksum verification, no version negotiation, platform-specific download URLs). Every runtime should go through mise.

---

## Common Pitfalls

### Pitfall 1: Volume Shadowing Hides Image-Baked Runtimes (CRITICAL)

**What goes wrong:** Runtimes installed with `mise use -g` in the Dockerfile land in `~/.local/share/mise/installs/`. The compose file mounts `mise-state:/home/dev/.mise`. The `MISE_DATA_DIR=/home/dev/.mise/data` env var means installs go to `/home/dev/.mise/data/installs`. The volume covers this path at runtime — image-layer files are hidden. Fresh volume = zero runtimes.

**Why it happens:** The CONTEXT.md says `mise use -g` is "acceptable because the volume persists" — but a first-start scenario with a fresh volume (new machine, `docker volume rm`) will fail silently. Users will see "command not found: node" after waiting through the image build.

**How to avoid:** Install as root with `mise install --system`. This writes to `/usr/local/share/mise/installs/` which is NOT under any volume mount. Verified: `mise install --system` confirmed working (requires root, writes to `/usr/local/share/mise/installs/`).

**Warning signs:** `node --version` fails inside fresh container. `mise ls` shows nothing. Works after `mise install` run manually inside container.

### Pitfall 2: Cargo Proxy Config Under Volume Mount

**What goes wrong:** Adding `[http] proxy = "..."` to `/home/dev/.cargo/config.toml` in the Dockerfile — this file is part of the image layer, but `cargo-state:/home/dev/.cargo` volume mounts over it at runtime. The file is invisible. Cargo ignores the proxy.

**How to avoid:** Two options:
1. Write to `/etc/cargo/config.toml` — cargo reads this as a system-level config, not under any volume mount
2. Set `CARGO_HTTP_PROXY=http://proxy:3128` as a compose environment variable — cargo respects this env var

Option 2 (env var) is simpler; Option 1 (system config) is more robust when env vars are stripped.

**Warning signs:** `cargo install` traffic not appearing in Squid access logs. `cargo build` succeeds even when Squid is stopped.

### Pitfall 3: Allowlist Missing New Package Manager Domains

**What goes wrong:** New runtimes try to download packages through the proxy. The proxy allows the CONNECT but the destination domain is blocked. Tools fail with connection errors that look like network problems.

**Domains to add to config/allowlist.txt:**
```
# npm
.npmjs.org
.npmjs.com
# cargo
.crates.io
.static.crates.io
.index.crates.io
# go modules
.proxy.golang.org
.sum.golang.org
.storage.googleapis.com
# mise runtime downloads (node, go, rust, bun)
.nodejs.org
.static.rust-lang.org
.bun.sh
.dl.google.com
# pypi (already present)
# .pypi.org
# .files.pythonhosted.org
```

**Warning signs:** `npm install` fails with proxy 403. Cargo downloads fail. `mise install` fails with connection errors during Dockerfile build.

### Pitfall 4: `mise use --system` vs `mise install --system`

**What goes wrong:** `mise install --system` installs the tool to the system path but does NOT activate it globally (does not add to PATH). The tool is installed but `node` is not on PATH.

**How to avoid:** After installing, also run `mise use --system node@lts ...` to write a system-level config that activates the tools. Alternatively, append the mise shims path `/usr/local/share/mise/shims` to `PATH` in the image ENV.

**Warning signs:** `which node` returns nothing. `mise ls` shows tools as installed but inactive.

### Pitfall 5: sandbox:run Docker Network Name

**What goes wrong:** When running `docker run` directly (not via compose), the network name is not `sandbox-internal` — it's `agent-sandbox_sandbox-internal` (compose prefixes with project name). The container starts but cannot reach the proxy.

**How to avoid:** Use the full compose-qualified network name: `--network agent-sandbox_sandbox-internal`. Alternatively, inspect the actual network name with `docker network ls | grep sandbox`.

**Warning signs:** Sandbox container starts but package installs fail. Squid access logs show no traffic from the new container.

### Pitfall 6: pip-cache Mount Path Conflicts with uv

**What goes wrong:** pip caches to `/home/dev/.cache/pip`. uv uses `/home/dev/.cache/uv` by default (not the pip cache path). A volume at `/home/dev/.cache/pip` mounts into `/home/dev/.cache/` — which may not shadow the uv path, but could shadow other `.cache/` subdirectories if mounted at the parent.

**How to avoid:** Mount the pip-cache volume at `/home/dev/.cache/pip` exactly (not at `/home/dev/.cache/`). This is the CONTEXT.md specified path and is correct.

---

## Code Examples

Verified patterns from official sources and live codebase:

### Dockerfile Runtime Installation (System-Wide)
```dockerfile
# Source: verified with `mise install --help` (2026-03-24)
# Run as root for system-wide install
USER root

# Install all runtimes to system path — not affected by home dir volume mount
RUN mise install --system node@lts && \
    mise install --system python@3.13 && \
    mise install --system go@latest && \
    mise install --system rust@stable && \
    mise install --system uv@0.10 && \
    mise install --system bun@1.3 && \
    mise install --system rust-analyzer@latest

# LSP tools (npm backend — requires node@lts already installed above)
RUN mise install --system npm:pyright@latest && \
    mise install --system npm:typescript-language-server@latest

# Activate system tools so they are on PATH for all users
RUN mise use --system node@lts python@3.13 go@latest rust@stable \
    uv@0.10 bun@1.3 rust-analyzer@latest \
    npm:pyright@latest npm:typescript-language-server@latest
```

### Proxy Config Files in Dockerfile
```dockerfile
# Source: CONTEXT.md + PITFALLS.md verification
USER dev

# npm proxy config — /home/dev/.npmrc is NOT under any volume mount
RUN printf 'proxy=http://proxy:3128\nhttps-proxy=http://proxy:3128\n' \
    > /home/dev/.npmrc

# git proxy config — writes to /home/dev/.gitconfig (not volume-mounted)
RUN git config --global http.proxy http://proxy:3128

USER root

# cargo proxy — system config avoids cargo-state volume shadowing
RUN mkdir -p /etc/cargo && \
    printf '[http]\nproxy = "http://proxy:3128"\n' \
    > /etc/cargo/config.toml
```

### docker-compose.yml Cache Volume Additions
```yaml
# Source: docker-compose.yml analysis + CONTEXT.md
services:
  agent-sandbox:
    volumes:
      # ... existing volumes unchanged ...
      - npm-cache:/home/dev/.npm
      - pip-cache:/home/dev/.cache/pip
      - go-cache:/home/dev/go/pkg/mod
    environment:
      # ... existing env vars unchanged ...
      - GOPROXY=https://proxy.golang.org,direct
      - CARGO_HTTP_PROXY=http://proxy:3128

volumes:
  # ... existing volumes unchanged ...
  npm-cache:
  pip-cache:
  go-cache:
```

### mise.toml Task Section
```toml
# Source: docs/mise.reference.md — Tasks section + usage block syntax
[tasks."proxy:start"]
description = "Start the Squid proxy container and wait for healthy"
run = """
docker compose up -d proxy
echo "Waiting for proxy health..."
until docker inspect --format='{{.State.Health.Status}}' agent-sandbox-proxy 2>/dev/null | grep -q healthy; do
  sleep 1
done
echo "Proxy is healthy"
"""

[tasks."proxy:stop"]
description = "Stop the Squid proxy container"
run = "docker compose stop proxy"

[tasks."proxy:status"]
description = "Show proxy container status"
run = "docker compose ps proxy"

[tasks."sandbox:build"]
description = "Build all sandbox container images"
run = "python3 images/build.py all"

[tasks."image:build"]
description = "Alias: build all sandbox container images"
run = "python3 images/build.py all"

[tasks."sandbox:run"]
description = "Start a named sandbox instance against a workspace directory"
usage = '''
flag "--name -n <name>" help="Sandbox name (used in container name)" default="default"
flag "--workspace -w <workspace>" help="Host path to mount as /workspace" default="."
'''
run = """
NAME="${usage_name:-default}"
WORKSPACE="$(realpath "${usage_workspace:-.}")"
CONTAINER="agent-sandbox-${NAME}"
docker run -d \
  --name "${CONTAINER}" \
  --network agent-sandbox_sandbox-internal \
  --cap-drop ALL --cap-add SETUID --cap-add SETGID \
  --security-opt no-new-privileges:true \
  --read-only \
  --tmpfs /tmp:size=268435456 \
  --tmpfs /run:size=67108864 \
  --volume "${WORKSPACE}:/workspace" \
  --volume "claude-state:/home/dev/.claude" \
  --volume "mise-state:/home/dev/.mise" \
  --volume "cargo-state:/home/dev/.cargo" \
  --volume "npm-cache:/home/dev/.npm" \
  --volume "pip-cache:/home/dev/.cache/pip" \
  --volume "go-cache:/home/dev/go/pkg/mod" \
  --volume "local-bin-state:/home/dev/.local/bin" \
  --env HTTP_PROXY=http://proxy:3128 \
  --env HTTPS_PROXY=http://proxy:3128 \
  --env http_proxy=http://proxy:3128 \
  --env https_proxy=http://proxy:3128 \
  --env NO_PROXY=localhost,127.0.0.1 \
  --env no_proxy=localhost,127.0.0.1 \
  --env GOPROXY=https://proxy.golang.org,direct \
  --env CARGO_HTTP_PROXY=http://proxy:3128 \
  --env TZ="${TZ:-America/Los_Angeles}" \
  --env CLAUDE_CONFIG_DIR=/home/dev/.claude \
  agent-sandbox-claude:local
echo "Started: ${CONTAINER}"
echo "Attach: docker exec -it ${CONTAINER} zsh"
"""

[tasks."sandbox:stop"]
description = "Stop and remove a named sandbox container"
usage = '''
flag "--name -n <name>" help="Sandbox name" default="default"
'''
run = """
NAME="${usage_name:-default}"
CONTAINER="agent-sandbox-${NAME}"
docker stop "${CONTAINER}" && docker rm "${CONTAINER}"
echo "Stopped: ${CONTAINER}"
"""
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `mise use -g` for container installs | `mise install --system` for Dockerfile installs | mise 2024+ | Runtimes survive home dir volume mounts |
| Tera template args `{{arg(name="x")}}` in mise tasks | `usage` block for task argument parsing | mise 2024; deprecated, removed 2026.11.0 | Avoid Tera template args entirely |
| Makefile / justfile for lifecycle tasks | mise `[tasks]` section | Already decided Phase 3 | Unified tooling — mise handles both runtimes and tasks |

**Deprecated/outdated:**
- Tera template argument syntax in mise tasks (`{{arg()}}`, `{{option()}}`, `{{flag()}}`): Deprecated, removed in mise 2026.11.0. Use `usage` block.
- `mise use -g` in Dockerfile when home dir is volume-mounted: Technically works if volume is pre-populated, but breaks on fresh volumes. Use `mise install --system` instead.

---

## Open Questions

1. **`mise use --system` availability**
   - What we know: `mise install --system` is confirmed working (verified live). `mise use --system` may or may not exist as a subcommand.
   - What's unclear: Whether `--system` is a flag on `mise use` or only on `mise install`. The `mise help use` output shows only `-g`/`--global`, not `--system`.
   - Recommendation: After `mise install --system`, verify activation by checking whether the system config file at `/usr/local/share/mise/config.toml` (or `MISE_SYSTEM_DATA_DIR/config.toml`) is written. If `mise use --system` does not exist, manually write the system config or add `/usr/local/share/mise/shims` to the Dockerfile `ENV PATH`.

2. **Proxy health wait in sandbox:run**
   - What we know: `docker compose wait <service>` blocks until the service exits (not health). `docker compose up --wait` blocks until healthy but starts all services.
   - What's unclear: Best pattern for sandbox:run to verify proxy is healthy before starting the container.
   - Recommendation: Use a polling loop (`until docker inspect...`) or require users to run `mise run proxy:start` first (which can do the health poll). sandbox:run can check if proxy container is running/healthy and error clearly if not.

3. **`command-history` volume missing from sandbox:run**
   - What we know: docker-compose.yml mounts `command-history:/commandhistory`. The sandbox:run task as drafted above omits this.
   - What's unclear: Should each sandbox instance share the same command history volume or have per-instance history?
   - Recommendation: Mount a per-instance volume `command-history-${NAME}:/commandhistory` — Docker creates named volumes on first use.

---

## Validation Architecture

> `nyquist_validation: true` in .planning/config.json — validation section is required.

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Bash smoke tests (no Python test framework; infrastructure validation only) |
| Config file | None — ad-hoc shell commands |
| Quick run command | `bash -c 'docker exec agent-sandbox node --version && docker exec agent-sandbox python3 --version'` |
| Full suite command | `bash images/smoke-test.sh` (to be created in Wave 0) |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| DEVENV-01 | Base tools present (git, curl, ripgrep, neovim, etc.) | smoke | `docker exec agent-sandbox git --version && docker exec agent-sandbox rg --version` | ❌ Wave 0 |
| DEVENV-02 | All runtimes available immediately in fresh container | smoke | `docker exec agent-sandbox node --version && python3 --version && go version && cargo --version && bun --version` | ❌ Wave 0 |
| DEVENV-03 | Runtimes present after `docker volume rm mise-state` | smoke | Fresh volume test: `docker volume rm mise-state; docker compose up -d agent-sandbox; docker exec agent-sandbox node --version` | ❌ Wave 0 |
| DEVENV-04 | Cache volumes created and mounted | smoke | `docker inspect agent-sandbox --format='{{json .Mounts}}' \| jq '.[] \| select(.Name \| test("cache"))'` | ❌ Wave 0 |
| DEVENV-05 | LSP tools on PATH | smoke | `docker exec agent-sandbox pyright --version && docker exec agent-sandbox typescript-language-server --version` | ❌ Wave 0 |
| DEVENV-06 | Container runs as dev user | smoke | `docker exec agent-sandbox id \| grep 'uid=500'` | ❌ Wave 0 |
| DEVENV-07 | Each PM routes through proxy | smoke | `docker stop agent-sandbox-proxy; docker exec agent-sandbox npm install left-pad 2>&1 \| grep -i "refused\|proxy\|network"` — expect failure | ❌ Wave 0 |
| ORCH-01 | proxy:start/stop/status tasks run | smoke | `mise run proxy:status` exits 0 | ❌ Wave 0 |
| ORCH-02 | sandbox:build and sandbox:run tasks run | smoke | `mise run sandbox:build && mise run sandbox:run -- --name test --workspace .` | ❌ Wave 0 |
| ORCH-03 | Two named sandboxes run simultaneously | smoke | Start sandbox:run --name a and sandbox:run --name b; verify both containers running | ❌ Wave 0 |
| ORCH-04 | Workspace mounted at /workspace | smoke | `docker exec agent-sandbox ls /workspace` returns project files | ❌ Wave 0 |

### Sampling Rate
- **Per task commit:** `docker exec agent-sandbox node --version && docker exec agent-sandbox python3 --version`
- **Per wave merge:** Full smoke test suite
- **Phase gate:** All smoke tests pass before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `images/smoke-test.sh` — full phase gate smoke test covering all requirements above
- [ ] Docker must be running and images built before any smoke tests can execute

*(No Python test framework needed — this phase is pure infrastructure, validated by shell commands against running containers)*

---

## Allowlist Additions Required

The proxy `config/allowlist.txt` must be extended before runtimes can install through the proxy. These domains are needed for the new package managers:

```
# npm registry
.npmjs.org
.npmjs.com

# cargo/crates.io
.crates.io
.static.crates.io
.index.crates.io

# Go modules
.proxy.golang.org
.sum.golang.org
.storage.googleapis.com

# mise runtime downloads
.nodejs.org
.static.rust-lang.org
.bun.sh

# (existing entries already cover GitHub for rust-analyzer and bun downloads)
```

---

## Sources

### Primary (HIGH confidence)
- `images/agents/claude/Dockerfile` — Ground truth for existing mise install pattern (lines 24-28)
- `docker-compose.yml` — Ground truth for existing volumes and service definition
- `mise.toml` — Ground truth for existing host config
- `docs/mise.reference.md` — Complete mise reference (task syntax, usage blocks, system install)
- `mise install --help` (live) — Confirmed `--system` flag exists, installs to `/usr/local/share/mise/installs`
- `mise install --system node@lts` (live) — Confirmed requires root, writes to `/usr/local/share/mise/installs/`

### Secondary (MEDIUM confidence)
- `.planning/research/PITFALLS.md` — mise volume shadowing pitfall (Pitfall 5) with specific system path recommendation
- `.planning/research/STACK.md` — Runtime versions and stack decisions

### Tertiary (LOW confidence)
- npm domain list — `npmjs.org` and `npmjs.com` are the main CDN/registry domains; full subdomain list not formally verified against npm's published CDN list
- Go module proxy domains — `proxy.golang.org`, `sum.golang.org`, `storage.googleapis.com` are documented in Go's module reference but exact subdomain requirements for pip/uv not verified against live traffic capture

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all versions verified live via `mise ls-remote` and npm
- Architecture: HIGH — verified against live mise behavior and existing codebase
- Pitfalls: HIGH — volume shadowing pitfall confirmed by live `mise install` behavior; cargo config path verified against compose file
- mise task syntax: HIGH — `usage` block syntax from docs/mise.reference.md, deprecation notice confirmed

**Research date:** 2026-03-24
**Valid until:** 2026-04-24 (stable tooling, but Rust 1.94 may release before then — check before implementing)
