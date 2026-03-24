---
phase: 03-development-environment
plan: "03"
subsystem: infra
tags: [mise, docker, squid, sandbox, lifecycle, tasks]

# Dependency graph
requires:
  - phase: 03-development-environment
    provides: "03-02 docker-compose.yml with sandbox service, volume definitions, and network (agent-sandbox_sandbox-internal)"
provides:
  - "mise.toml [tasks] section with 7 lifecycle task definitions"
  - "proxy:start (with health polling), proxy:stop, proxy:status"
  - "sandbox:build, sandbox:run (with --name/--workspace flags), sandbox:stop"
  - "image:build alias for sandbox:build"
affects: [04-smoke-tests, operators, future phases that run sandboxes]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "mise usage block syntax for flag-based argument parsing (usage_name, usage_workspace)"
    - "Docker run with compose-qualified network name (agent-sandbox_sandbox-internal)"
    - "Health polling via until/grep loop instead of docker compose wait"

key-files:
  created: []
  modified:
    - mise.toml

key-decisions:
  - "Health polling uses 'until docker inspect | grep -q healthy' loop — docker compose wait subcommand not universally available across Docker Compose versions"
  - "sandbox:run network flag uses compose-qualified name agent-sandbox_sandbox-internal — bare sandbox-internal does not resolve outside compose context"
  - "Resource limit env vars (SANDBOX_CPUS, SANDBOX_MEMORY, SANDBOX_PIDS) use ${VAR:-default} pattern to match compose behavior"
  - "usage block variable access (${usage_name}) over deprecated Tera template args ({{arg(...)}})"

patterns-established:
  - "Pattern 1: All sandbox lifecycle operations accessible via mise run — single interface for operators"
  - "Pattern 2: Multi-instance support via NAME arg — container names like agent-sandbox-${NAME} enable parallel agent runs"
  - "Pattern 3: usage blocks for task argument declarations — provides --help output and shell completions automatically"

requirements-completed: [ORCH-01, ORCH-02, ORCH-03, ORCH-04]

# Metrics
duration: 1min
completed: 2026-03-24
---

# Phase 3 Plan 03: mise Lifecycle Tasks Summary

**7 mise tasks covering full sandbox lifecycle: proxy start/stop/status with health polling, sandbox build/run/stop with usage-block flags, and image:build alias**

## Performance

- **Duration:** 1 min
- **Started:** 2026-03-24T01:23:18Z
- **Completed:** 2026-03-24T01:24:08Z
- **Tasks:** 2
- **Files modified:** 1

## Accomplishments

- Proxy lifecycle tasks (proxy:start with health polling loop, proxy:stop, proxy:status) added to mise.toml
- Sandbox and image lifecycle tasks (sandbox:build, sandbox:run, sandbox:stop, image:build) added with correct hardening flags, volumes, and network references
- sandbox:run and sandbox:stop use usage blocks for --name/-n and --workspace/-w flags, providing --help output and shell completions
- All 7 tasks parse correctly per `mise tasks` output; no deprecated Tera syntax present

## Task Commits

Each task was committed atomically:

1. **Task 1 + Task 2: All 7 lifecycle tasks written to mise.toml** - `2d50301` (feat)

*Note: Both tasks modified the same file; written in a single atomic operation and committed once.*

**Plan metadata:** (docs commit — see below)

## Files Created/Modified

- `/home/jani/devel/agent-sandbox/mise.toml` - Extended from 2 lines to 90 lines with full [tasks] section containing 7 definitions

## Decisions Made

- Health polling uses `until docker inspect --format='{{.State.Health.Status}}' | grep -q healthy` loop — `docker compose wait` subcommand behavior varies across Docker Compose versions
- Network flag uses compose-qualified name `agent-sandbox_sandbox-internal` — bare `sandbox-internal` does not resolve when using `docker run` outside compose context (RESEARCH.md documented pitfall)
- Usage block variable access `${usage_name:-default}` used throughout — deprecated Tera template `{{arg(...)}}` syntax avoided

## Deviations from Plan

None - plan executed exactly as written. Both tasks delivered in single file write; single commit covers all 7 tasks.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- `mise run proxy:start` / `mise run sandbox:run` / `mise run sandbox:stop` are ready for smoke testing in Phase 04
- Two sandbox instances can be run simultaneously with different `--name` values (e.g., `mise run sandbox:run --name agent1` and `mise run sandbox:run --name agent2`)
- No blockers for next phase

---
*Phase: 03-development-environment*
*Completed: 2026-03-24*
