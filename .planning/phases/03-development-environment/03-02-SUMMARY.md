---
phase: 03-development-environment
plan: "02"
subsystem: infra
tags: [docker-compose, squid, npm, cargo, go, mise, proxy, volumes]

# Dependency graph
requires:
  - phase: 01-proxy-infrastructure
    provides: Squid proxy with allowlist ACL and host-mount override at config/allowlist.txt
  - phase: 02-container-hardening
    provides: Hardened agent-sandbox service with read_only, cap_drop, and named volumes structure
provides:
  - npm-cache, pip-cache, go-cache named volumes in docker-compose.yml persisting package downloads
  - GOPROXY and CARGO_HTTP_PROXY env vars configured in agent-sandbox service
  - Squid allowlist expanded with all npm, cargo, Go modules, and mise runtime download domains
affects:
  - 03-development-environment (subsequent plans using package managers inside sandbox)
  - Any phase that runs npm/cargo/go/pip installs inside the sandbox

# Tech tracking
tech-stack:
  added: []
  patterns:
    - Named volumes for package manager caches mounted at tool-specific cache paths
    - Leading-dot dstdomain syntax for allowlist wildcard subdomain coverage (established Phase 01)
    - Per-tool proxy env vars (GOPROXY, CARGO_HTTP_PROXY) alongside HTTP_PROXY for tool compatibility

key-files:
  created: []
  modified:
    - docker-compose.yml
    - config/allowlist.txt

key-decisions:
  - "go-cache mounted at /home/dev/go/pkg/mod (Go module cache path, not GOPATH root) for correct cache hit behavior"
  - "CARGO_HTTP_PROXY set as env var fallback because cargo-state volume mount shadows config.toml at runtime"
  - "GOPROXY set to proxy.golang.org,direct — allows fallback to direct if proxy module not found"

patterns-established:
  - "Package cache volumes: named volumes mounted at each package manager's native cache directory"
  - "Proxy env vars: use tool-specific vars (GOPROXY, CARGO_HTTP_PROXY) in addition to generic HTTP_PROXY"
  - "Allowlist expansion: group domains by package manager with comments for maintainability"

requirements-completed:
  - DEVENV-04
  - DEVENV-07
  - ORCH-04

# Metrics
duration: 1min
completed: 2026-03-24
---

# Phase 3 Plan 02: Package Cache Volumes and Allowlist Expansion Summary

**Three named cache volumes (npm, pip, go) added to docker-compose.yml with GOPROXY/CARGO_HTTP_PROXY env vars, and Squid allowlist expanded with 11 new domains covering npm, cargo, Go modules, and mise runtime downloads**

## Performance

- **Duration:** ~1 min
- **Started:** 2026-03-24T01:20:19Z
- **Completed:** 2026-03-24T01:21:04Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments

- Added npm-cache, pip-cache, go-cache named volumes with correct mount paths for each package manager's native cache directory
- Added GOPROXY and CARGO_HTTP_PROXY env vars to agent-sandbox service for tool-specific proxy routing
- Expanded config/allowlist.txt from 9 to 20 domain entries covering npm, cargo/crates.io, Go modules, and mise runtime downloads (nodejs.org, rust-lang.org, bun.sh, dl.google.com)

## Task Commits

Each task was committed atomically:

1. **Task 1: Add package cache volumes and proxy env vars to docker-compose.yml** - `10c828a` (feat)
2. **Task 2: Expand Squid allowlist with package manager and runtime download domains** - `0fa5bc1` (feat)

## Files Created/Modified

- `/home/jani/devel/agent-sandbox/docker-compose.yml` - Added 3 named volume declarations, 3 volume mounts, 2 proxy env vars
- `/home/jani/devel/agent-sandbox/config/allowlist.txt` - Added 11 new domain entries in 4 grouped sections

## Decisions Made

- go-cache mounted at `/home/dev/go/pkg/mod` (Go module cache path) rather than GOPATH root — ensures cache hits for `go get` and `go build`
- CARGO_HTTP_PROXY set as env var because cargo-state volume mount shadows ~/.cargo/config.toml at runtime, making file-based proxy config unreliable
- GOPROXY includes `direct` fallback (`proxy.golang.org,direct`) so private/internal modules not in the public proxy still resolve

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Cache volumes and allowlist now enable subsequent Phase 03 plans to install packages (npm, cargo, go, pip) through the Squid proxy without ACL blocks
- GOPROXY and CARGO_HTTP_PROXY ensure tool-specific proxy routing beyond generic HTTP_PROXY
- Remaining concern from STATE.md: runtime volume shadowing for mise runtimes (must install via `mise install --system` in Dockerfile) — addressed in later Phase 03 plans

---
*Phase: 03-development-environment*
*Completed: 2026-03-24*
