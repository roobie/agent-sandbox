---
phase: 04-observability-and-distribution
plan: 01
subsystem: infra
tags: [mise, docker, observability, logs, docker-diff, git-diff]

# Dependency graph
requires:
  - phase: 03-development-environment
    provides: mise.toml with sandbox:run and sandbox:stop tasks, usage block patterns

provides:
  - sandbox:logs mise task (docker logs with --name, --follow, --tail flags)
  - proxy:logs mise task (docker logs with --follow, --tail flags)
  - Enhanced sandbox:stop with docker diff + git diff --stat output before stop

affects:
  - 04-02-ci-distribution
  - 04-03-artifact-cleanup

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "mise usage flag short-flag collision avoidance: use -t for --tail when -n is taken by --name"
    - "docker inspect Go template for recovering bind-mount source path at stop time"
    - "pre-stop diff pattern: docker diff + git diff --stat before docker stop/rm"

key-files:
  created: []
  modified:
    - mise.toml

key-decisions:
  - "sandbox:logs uses -t (not -n) as short flag for --tail because -n is reserved for --name"
  - "docker inspect Go template recovers workspace path dynamically — no --workspace arg needed at stop time"
  - "docker diff uses C (Changed), not M (Modified) — legend documents A=Added, C=Changed, D=Deleted"
  - "Workspace check includes [ -d WORKSPACE ] guard for cases where path doesn't exist on host"

patterns-established:
  - "Pattern: mise optional flag with conditional docker logs ARGS construction"
  - "Pattern: docker inspect --format '{{ range .Mounts }}{{ if eq .Destination \"/workspace\" }}{{ .Source }}{{ end }}{{ end }}' for mount source recovery"

requirements-completed:
  - OBS-01
  - OBS-02
  - OBS-03

# Metrics
duration: 2min
completed: 2026-03-24
---

# Phase 04 Plan 01: Observability Tasks Summary

**Three mise tasks wired to docker observability primitives: sandbox:logs and proxy:logs for log access, sandbox:stop enhanced with docker diff + git diff output before container removal**

## Performance

- **Duration:** ~2 min
- **Started:** 2026-03-24T03:05:31Z
- **Completed:** 2026-03-24T03:07:30Z
- **Tasks:** 2
- **Files modified:** 1

## Accomplishments
- Added `proxy:logs` task: `docker logs agent-sandbox-proxy` with `--follow` and `--tail` flags for live tailing and history limits
- Added `sandbox:logs` task: `docker logs agent-sandbox-${NAME}` with `--name`, `--follow`, `--tail` flags; uses `-t` for tail to avoid collision with `-n` (name)
- Enhanced `sandbox:stop` to emit `=== Container filesystem changes ===` (via `docker diff`) and `=== Workspace changes ===` (via `git diff --stat`) BEFORE stopping the container; workspace path recovered dynamically via `docker inspect` Go template

## Task Commits

Each task was committed atomically:

1. **Task 1: Add sandbox:logs and proxy:logs mise tasks** - `fc4e704` (feat)
2. **Task 2: Enhance sandbox:stop with pre-stop diff capture** - `c8788f3` (feat)

**Plan metadata:** `(docs commit — see below)`

## Files Created/Modified
- `mise.toml` - Added proxy:logs and sandbox:logs tasks; replaced sandbox:stop with diff-capturing version

## Decisions Made
- `sandbox:logs` uses `-t` (not `-n`) as the short flag for `--tail` because `-n` is reserved for `--name` in that task
- Workspace path recovery uses `docker inspect --format` Go template rather than requiring `--workspace` argument at stop time — users don't have to remember or re-specify the workspace path
- Legend line `(A=Added, C=Changed, D=Deleted)` documents Docker's use of `C` (not `M`) for modified files
- Workspace check includes `[ -d "$WORKSPACE" ]` guard so the task handles the edge case where a bind-mount source was deleted after `sandbox:run`

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- All OBS-01, OBS-02, OBS-03 requirements satisfied
- `mise run proxy:logs` and `mise run sandbox:logs` ready for smoke testing with live containers
- `mise run sandbox:stop` will show filesystem and workspace diffs before container removal
- Phase 04 Plan 02 (CI/CD distribution) can proceed — proxy image build job is next

---
*Phase: 04-observability-and-distribution*
*Completed: 2026-03-24*

## Self-Check: PASSED

- mise.toml: FOUND
- 04-01-SUMMARY.md: FOUND
- commit fc4e704 (Task 1): FOUND
- commit c8788f3 (Task 2): FOUND
