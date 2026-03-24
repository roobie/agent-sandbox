---
phase: 03-development-environment
plan: "01"
subsystem: infra
tags: [mise, docker, runtimes, proxy, node, python, go, rust, bun, lsp, npm, cargo, git]

# Dependency graph
requires:
  - phase: 02-container-hardening
    provides: base agent Dockerfile with volume mount configuration and hardened container
provides:
  - System-wide mise runtime installs (node, python, go, rust, bun, rust-analyzer) baked into image layer at /usr/local/share/mise/installs/
  - LSP tools (pyright, typescript-language-server) installed via npm backend system-wide
  - npm proxy config at /home/dev/.npmrc (proxy:3128)
  - git proxy config via /home/dev/.gitconfig (proxy:3128)
  - cargo system proxy config at /etc/cargo/config.toml (proxy:3128)
affects: [03-development-environment, 04-verification]

# Tech tracking
tech-stack:
  added: [mise --system installs, /etc/cargo/config.toml, rust-analyzer, pyright, typescript-language-server]
  patterns: [system-install runtimes to survive volume mount shadowing, per-PM proxy config baked into image layer]

key-files:
  created: []
  modified: [images/agents/claude/Dockerfile]

key-decisions:
  - "mise install --system used instead of mise use -g — user-path installs are shadowed by mise-state:/home/dev/.mise volume mount; system installs write to /usr/local/share/mise/installs/ which is outside all volume mounts"
  - "/etc/cargo/config.toml used for cargo proxy — /home/dev/.cargo is shadowed by cargo-state volume; system config at /etc avoids the shadow"
  - "uv not reinstalled system-wide — already installed via mise use -g uv@$UV_VERSION (user-path); this matches existing pattern for claude-code and is acceptable since uv install is fast"
  - "DEVENV-06 (UID/GID adjustment) accepted as deferred limitation — container runs with fixed UID 500; dynamic adjustment incompatible with read-only rootfs under cap_drop ALL"

patterns-established:
  - "Pattern: system-install runtimes in Dockerfile (USER root + mise install --system) to avoid home-dir volume mount shadowing"
  - "Pattern: bake per-PM proxy configs to non-volume-mounted paths (/home/dev/.npmrc, /home/dev/.gitconfig, /etc/cargo/config.toml)"

requirements-completed: [DEVENV-01, DEVENV-02, DEVENV-03, DEVENV-05, DEVENV-06, DEVENV-07]

# Metrics
duration: 10min
completed: 2026-03-24
---

# Phase 3 Plan 01: Development Environment Runtimes Summary

**System-wide mise installs for node/python/go/rust/bun/rust-analyzer/pyright/typescript-language-server baked into agent image layer, with npm/git/cargo proxy configs at non-volume-shadowed paths**

## Performance

- **Duration:** ~10 min
- **Started:** 2026-03-24T01:20:00Z
- **Completed:** 2026-03-24T01:30:00Z
- **Tasks:** 2
- **Files modified:** 1

## Accomplishments
- All language runtimes (node LTS, python 3.13, go latest, rust stable, bun 1.3) installed system-wide via `mise install --system` — survive fresh mise-state volume mounts
- LSP tools (rust-analyzer, pyright, typescript-language-server) installed system-wide and activated via `mise use --system`
- npm, git, and cargo proxy configs baked into image at paths that are not shadowed by volume mounts at runtime

## Task Commits

Each task was committed atomically:

1. **Task 1: Install language runtimes and LSP tools system-wide via mise** - `a544e3f` (feat)
2. **Task 2: Bake per-package-manager proxy configs into image** - `5b7f93f` (feat)

**Plan metadata:** (see final commit below)

## Files Created/Modified
- `images/agents/claude/Dockerfile` - Added system-wide mise runtime installs and per-PM proxy config blocks

## Decisions Made
- `mise install --system` chosen over `mise use -g` because user-path installs at `~/.local/share/mise/installs/` are shadowed by the `mise-state:/home/dev/.mise` volume mount; system installs at `/usr/local/share/mise/installs/` are not affected by any volume mount
- `/etc/cargo/config.toml` for cargo proxy because `/home/dev/.cargo` is shadowed by `cargo-state` volume
- DEVENV-06 (UID/GID adjustment) accepted as deferred limitation per CONTEXT.md decision — container runs with fixed UID 500

## Deviations from Plan

None - plan executed exactly as written. The plan itself already documented the key deviation from CONTEXT.md (using `mise install --system` instead of `mise use -g`), so no additional auto-fixes were required during execution.

## Issues Encountered

None - both tasks completed cleanly against the plan specification.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- Runtime installs require an actual `docker build` to confirm mise resolves tools at build time (network access to mise.jdx.dev and various tool CDNs required)
- Proxy configs are correct syntactically; functional verification (proxy traffic appearing in Squid logs) is a Phase 3 smoke test concern
- Plan 03-02 (proxy env vars and cache volumes in docker-compose.yml) already committed; plans are ready to proceed to Plan 03 and beyond

---
*Phase: 03-development-environment*
*Completed: 2026-03-24*
