---
phase: 04-observability-and-distribution
plan: 03
subsystem: docs
tags: [squid, proxy, readme, allowlist, documentation, cleanup]

# Dependency graph
requires:
  - phase: 01-proxy-infrastructure
    provides: Squid proxy with allowlist.txt replacing iptables/policy.json
provides:
  - Updated README.md describing current Squid proxy architecture and mise-based workflow
  - Removed stale docs/policy/schema.md and docs/policy/example.json
  - Cleaned copilot Dockerfile with no reference to non-existent policy.json
affects: []

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "README.md now describes proxy-based egress control, not iptables"
    - "Lifecycle workflow documented as mise run proxy:start / sandbox:run / sandbox:stop"

key-files:
  created: []
  modified:
    - README.md
    - images/agents/copilot/Dockerfile
  deleted:
    - docs/policy/schema.md
    - docs/policy/example.json

key-decisions:
  - "docs/policy/example.json removed alongside schema.md — both are iptables-era artifacts with no relevance to Squid proxy architecture"

patterns-established:
  - "Historical planning docs (docs/plan/milestones/) left in place — they describe completed work, not current mechanism"

requirements-completed:
  - DIST-03

# Metrics
duration: 8min
completed: 2026-03-24
---

# Phase 4 Plan 3: Stale Reference Cleanup Summary

**README.md rewritten for Squid proxy architecture with mise lifecycle workflow; copilot Dockerfile and docs/policy/ cleaned of all iptables-era artifacts**

## Performance

- **Duration:** ~8 min
- **Started:** 2026-03-24T03:08:09Z
- **Completed:** 2026-03-24T03:16:00Z
- **Tasks:** 2
- **Files modified:** 3 (1 Dockerfile, 1 README, 2 docs deleted)

## Accomplishments

- Removed COPY policy.json and stale comment from `images/agents/copilot/Dockerfile`
- Rewrote `README.md` from scratch: proxy architecture, SNI peek/splice, allowlist.txt format, mise-based workflow, updated security notes
- Deleted `docs/policy/schema.md` and `docs/policy/example.json` (iptables-era policy.json documentation)

## Task Commits

Each task was committed atomically:

1. **Task 1: Remove stale policy.json reference from copilot Dockerfile** - `fc4e704` (fix)
2. **Task 2: Update README.md and docs/policy/schema.md for proxy-based architecture** - `659733a` (fix)

**Plan metadata:** (docs: complete plan — see final commit)

## Files Created/Modified

- `images/agents/copilot/Dockerfile` - Removed 3 lines: COPY policy.json, chmod, and stale Override comment
- `README.md` - Full rewrite: proxy architecture, allowlist.txt format, mise workflow, SNI description, security notes
- `docs/policy/schema.md` - Deleted (iptables-era policy.json schema documentation)
- `docs/policy/example.json` - Deleted (iptables-era example policy file)

## Decisions Made

- `docs/policy/example.json` removed alongside `schema.md` — both documents the old policy.json format that no longer exists. Rule 2 auto-fix (missing critical: leaving stale example files risks confusing contributors).
- Historical milestone docs in `docs/plan/milestones/` were left in place — they describe completed past work (before the proxy migration), not current mechanism; they are not user-facing documentation.
- Smoke test reference to `init-firewall.py` in `tests/smoke-proxy.sh` was left in place — it tests that `init-firewall.py` is **absent** from the container (correct migration verification), not that it's present.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing Critical] Removed docs/policy/example.json alongside schema.md**
- **Found during:** Task 2 (docs/policy/ directory cleanup)
- **Issue:** After removing schema.md, docs/policy/example.json remained — it documents the old policy.json format and would confuse contributors about the current architecture
- **Fix:** Removed example.json and the now-empty docs/policy/ directory
- **Files modified:** docs/policy/example.json (deleted), docs/policy/ (removed)
- **Verification:** `test -d docs/policy/` returns false
- **Committed in:** 659733a (Task 2 commit)

---

**Total deviations:** 1 auto-fixed (Rule 2 - missing critical)
**Impact on plan:** Auto-fix necessary for completeness — leaving example.json would leave a stale artifact describing the removed mechanism. No scope creep.

## Issues Encountered

None — all changes straightforward.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- No stale iptables-era references remain in any user-facing or build files
- README.md accurately represents the current architecture for new contributors
- Copilot Dockerfile now builds without referencing non-existent files
- Phase 4 cleanup complete; ready for any remaining distribution tasks

---
*Phase: 04-observability-and-distribution*
*Completed: 2026-03-24*
