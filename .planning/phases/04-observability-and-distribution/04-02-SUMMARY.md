---
phase: 04-observability-and-distribution
plan: "02"
subsystem: infra
tags: [github-actions, ghcr, docker, ci-cd, build-push-action, gha-cache]

# Dependency graph
requires:
  - phase: 01-proxy-infrastructure
    provides: images/proxy directory with Dockerfile and Squid config
provides:
  - build-proxy CI job publishing agent-sandbox-proxy to GHCR on push to main
  - GHA build cache scoping per job (scope=base, scope=claude, scope=proxy)
  - Three-image digest summary in GHA job summary
affects: [future CI changes, proxy image consumers pulling from GHCR]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - GHA cache scoping with scope= parameter on docker/build-push-action to prevent cross-job collision
    - Parallel CI job pattern: proxy runs alongside base (no needs dependency)

key-files:
  created: []
  modified:
    - .github/workflows/build-images.yml

key-decisions:
  - "GHA caches scoped per image (scope=base, scope=claude, scope=proxy) to prevent parallel job cache overwrites"
  - "build-proxy has no needs dependency — runs in parallel with build-base since proxy image is Squid-based and independent of project base image"
  - "Action versions kept at existing levels (build-push-action@v5) for consistency and no-regression"

patterns-established:
  - "Pattern: scope GHA caches when multiple jobs use type=gha cache"
  - "Pattern: parallel CI jobs for independent images (proxy vs base)"

requirements-completed: [DIST-01, DIST-02]

# Metrics
duration: 1min
completed: "2026-03-24"
---

# Phase 04 Plan 02: CI Proxy Image Publishing Summary

**Proxy image (agent-sandbox-proxy) published to GHCR via parallel CI job with scoped GHA caches preventing cross-job collision**

## Performance

- **Duration:** 1 min
- **Started:** 2026-03-24T03:05:31Z
- **Completed:** 2026-03-24T03:06:52Z
- **Tasks:** 1
- **Files modified:** 1

## Accomplishments

- Added `build-proxy` job to CI workflow; runs in parallel with `build-base` (no `needs` dependency)
- Scoped GHA build caches for all three jobs (`scope=base`, `scope=claude`, `scope=proxy`) preventing cache key collisions
- Extended `summary` job to include `build-proxy` in `needs` and add proxy digest row to summary table
- Verified `build-claude` digest pinning (`needs.build-base.outputs.digest`) remains intact

## Task Commits

1. **Task 1: Add build-proxy job and scope GHA caches** - `5800808` (feat)

**Plan metadata:** (created in this step)

## Files Created/Modified

- `.github/workflows/build-images.yml` - Added PROXY_IMAGE_NAME env, build-proxy job, scoped caches on all three jobs, updated summary job

## Decisions Made

- Kept `build-push-action@v5` for the proxy job (matching existing jobs) — v6 upgrade is a separate task; consistent versioning avoids regressions
- `build-proxy` has no `needs` — proxy (Squid-based) has no dependency on the project's base image, parallel execution is correct
- GHA cache scoping applied retroactively to existing `build-base` and `build-claude` jobs as part of the same task — the research (Pitfall 3) identified this as the right time to fix

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required. GHCR publishing uses `secrets.GITHUB_TOKEN` which is automatically provided by GitHub Actions.

## Next Phase Readiness

- Proxy image will publish to `ghcr.io/<owner>/agent-sandbox-proxy:latest` on next push to main
- DIST-01 satisfied: CI/CD pipeline publishes all three images
- DIST-02 already satisfied (noted in plan): `mise run image:build` works locally
- Remaining plans in phase 04: observability tasks (OBS-01 through OBS-03) and cleanup (DIST-03)

## Self-Check: PASSED

- .github/workflows/build-images.yml: FOUND
- 04-02-SUMMARY.md: FOUND
- commit 5800808: FOUND

---
*Phase: 04-observability-and-distribution*
*Completed: 2026-03-24*
