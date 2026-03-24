# Phase 3: Development Environment - Context

**Gathered:** 2026-03-24
**Status:** Ready for planning

<domain>
## Phase Boundary

Sandbox containers arrive with a fully-functional development environment — all language runtimes pre-installed and accessible, per-package-manager proxy configuration active so all install traffic routes through Squid, and mise tasks on the host covering the full sandbox lifecycle. This phase does NOT change the proxy infrastructure (Phase 1) or hardening directives (Phase 2).

</domain>

<decisions>
## Implementation Decisions

### Runtime installation in Dockerfile
- Install all runtimes via `mise use -g` in the claude agent Dockerfile (extends existing pattern at line 25-29)
- Runtimes: Node (latest LTS), Python (3.12+), Go (latest), Rust 1.94.x, uv 0.10.x, Bun 1.3.x, rust-analyzer (latest)
- Claude Code and uv already installed this way — extend with remaining runtimes
- mise-state named volume persists `~/.local/share/mise/` across container rebuilds
- The home dir volume mount means runtimes installed via `mise use -g` land in the volume, not the image layer — this is acceptable because the volume persists

### LSP tooling
- rust-analyzer installed via mise (already in runtime list)
- pyright: install via `mise use -g npm:pyright` (npm-based)
- typescript-language-server: install via `mise use -g npm:typescript-language-server` (npm-based)
- These are installed alongside runtimes in the Dockerfile

### Per-package-manager proxy configuration
- **npm**: Create `/home/dev/.npmrc` with `proxy=http://proxy:3128` and `https-proxy=http://proxy:3128`
- **cargo**: Create `/home/dev/.cargo/config.toml` with `[http]` proxy setting (note: cargo volume mount may shadow this — write to /etc/cargo/ or use env var `CARGO_HTTP_PROXY`)
- **git**: `git config --global http.proxy http://proxy:3128`
- **Go**: Set `GOPROXY=https://proxy.golang.org,direct` in compose env (Go respects HTTP_PROXY for the actual fetch, GOPROXY controls the module proxy endpoint)
- All configs baked into image so tools work immediately without post-start setup

### mise tasks for host orchestration
- Tasks defined in project-root `mise.toml` (host-side, not inside container)
- Naming convention: `proxy:start`, `proxy:stop`, `proxy:status`, `sandbox:build`, `sandbox:run`, `sandbox:stop`, `image:build`
- `proxy:start` — `docker compose up -d proxy` and wait for healthy
- `proxy:stop` — `docker compose stop proxy`
- `proxy:status` — `docker compose ps proxy`
- `sandbox:build` — `python3 images/build.py all`
- `sandbox:run` — starts sandbox container, accepts `NAME` and `WORKSPACE` args for multi-instance
- `sandbox:stop` — stops sandbox by name
- `image:build` — alias for `sandbox:build`

### Multi-sandbox support
- `mise run sandbox:run` accepts `NAME=foo WORKSPACE=/path/to/project` arguments
- Each named sandbox gets `container_name: agent-sandbox-${NAME}`
- Implemented via mise task that generates a docker compose override or runs `docker run` directly with the right flags
- All instances share the single proxy container (already wired via Docker network)

### Package cache volumes
- npm: `npm-cache:/home/dev/.npm`
- pip: `pip-cache:/home/dev/.cache/pip`
- cargo: already have `cargo-state:/home/dev/.cargo` (includes registry cache)
- Go modules: `go-cache:/home/dev/go/pkg/mod`
- Add these named volumes to docker-compose.yml

### UID/GID adjustment (DEVENV-06)
- Entrypoint already has the ETC_WRITABLE guard from Phase 2
- Under read-only rootfs, UID/GID adjustment is skipped (fixed UID 500)
- For Phase 3: add a tmpfs mount at `/etc` overlay OR accept the limitation that host UID must match 500
- Recommended: accept the limitation for now; document workaround (rebuild with different UID build arg)

### Claude's Discretion
- Exact mise tool versions for Node LTS, Python, Go (use latest stable at build time)
- Whether to add additional LSP servers beyond the three specified
- Exact mise task implementation details (shell commands, error handling)
- Whether sandbox:run uses docker compose override files or direct docker run

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Existing code to modify
- `images/agents/claude/Dockerfile` — Current agent image with mise + claude-code + uv already installed; extend with remaining runtimes
- `docker-compose.yml` — Add package cache volumes; mise tasks reference this for lifecycle management
- `mise.toml` — Currently only has `python = "3.13.11"` for host; will be extended with task definitions

### Prior phase context
- `.planning/phases/01-proxy-infrastructure/01-CONTEXT.md` — Proxy env vars (HTTP_PROXY/HTTPS_PROXY) already set in compose
- `.planning/phases/02-container-hardening/02-CONTEXT.md` — Read-only rootfs, tmpfs mounts, entrypoint guards

### Research
- `.planning/research/STACK.md` — mise runtime installation patterns
- `.planning/research/PITFALLS.md` — mise home dir volume shadowing, per-PM proxy config requirements
- `docs/mise.reference.md` — Complete mise reference for task syntax, tool installation, env management

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `images/agents/claude/Dockerfile`: Already has mise APT install + `mise use -g claude-code` + `mise use -g uv` pattern — extend directly
- `mise.toml`: Exists with `python = "3.13.11"` — add `[tasks]` section
- `docker-compose.yml`: Named volumes pattern established (claude-state, mise-state, cargo-state) — extend with cache volumes

### Established Patterns
- Runtime install: `mise use -g <tool>@<version>` as `USER dev` in Dockerfile
- Compose env vars: `${VAR:-default}` substitution (TZ, SANDBOX_* from Phase 2)
- Named volumes: `volume-name:/path` in compose volumes section

### Integration Points
- `images/agents/claude/Dockerfile`: Add `mise use -g` commands for Node, Python, Go, Rust, Bun, rust-analyzer, pyright, typescript-language-server
- `docker-compose.yml`: Add npm-cache, pip-cache, go-cache volumes; add package cache volume mounts
- `mise.toml`: Add full task definitions for proxy and sandbox lifecycle
- `images/base/entrypoint.sh`: May need proxy config setup if not baked into image
- Per-PM config files: .npmrc, .cargo/config.toml, git config in Dockerfile

</code_context>

<specifics>
## Specific Ideas

- Runtimes must work immediately in a fresh sandbox without post-start install (DEVENV-02 success criterion)
- Package manager traffic must appear in Squid access logs (verify proxy routing works for each PM)
- Two named sandboxes must run simultaneously against different workspaces
- mise tasks should be copy-paste simple: `mise run proxy:start && mise run sandbox:run`

</specifics>

<deferred>
## Deferred Ideas

- Devcontainer mode support (ORCH-07 in v2) — VS Code extension writes conflict with read-only rootfs
- UID/GID dynamic adjustment under read-only rootfs — accept fixed UID 500 for now
- Additional LSP servers beyond rust-analyzer, pyright, typescript-language-server

</deferred>

---

*Phase: 03-development-environment*
*Context gathered: 2026-03-24*
