---
phase: 01-proxy-infrastructure
plan: "02"
subsystem: infra
tags: [docker, iptables, ipset, entrypoint, base-image, firewall]

requires: []
provides:
  - "Base Dockerfile free of iptables, ipset, aggregate packages and firewall COPY directives"
  - "entrypoint.sh free of firewall initialization block — starts directly with cd /workspace"
affects: [01-proxy-infrastructure, 01-03-PLAN, 01-04-PLAN]

tech-stack:
  added: []
  patterns:
    - "Base image no longer needs NET_ADMIN or NET_RAW capabilities"

key-files:
  created: []
  modified:
    - images/base/Dockerfile
    - images/base/entrypoint.sh

key-decisions:
  - "Kept iproute2 and dnsutils in Dockerfile — useful for debugging network routes and verifying proxy DNS resolution"
  - "USER root added before COPY entrypoint.sh to ensure correct permissions after removing the firewall USER root block"
  - "init-firewall.py and policy.json intentionally kept on disk pending Plan 04 smoke test confirmation"

patterns-established:
  - "Clean cutover pattern: remove firewall tooling from base image, physical deletion deferred to Plan 04 after smoke tests"

requirements-completed: [MIG-01, MIG-02]

duration: 5min
completed: 2026-03-24
---

# Phase 01 Plan 02: Base Image Firewall Removal Summary

**Stripped iptables/ipset/aggregate from base Dockerfile and removed firewall init block from entrypoint.sh, completing the base image side of the proxy migration cutover**

## Performance

- **Duration:** ~5 min
- **Started:** 2026-03-23T23:51:17Z
- **Completed:** 2026-03-23T23:56:00Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments

- Removed iptables, ipset, and aggregate packages from apt-get install block in base Dockerfile
- Removed COPY/chmod block for policy.json and init-firewall.py from Dockerfile
- Removed 16-line firewall initialization block from entrypoint.sh
- Container startup now proceeds directly to cd /workspace after set -e header

## Task Commits

Each task was committed atomically:

1. **Task 1: Clean firewall packages and COPY directives from base Dockerfile** - `a2a8131` (feat)
2. **Task 2: Remove firewall initialization block from entrypoint.sh** - `6f7e096` (feat)

**Plan metadata:** (docs commit below)

## Files Created/Modified

- `images/base/Dockerfile` - Removed iptables, ipset, aggregate packages and firewall COPY/chmod directives; added USER root before entrypoint COPY
- `images/base/entrypoint.sh` - Removed ipset/init-firewall.py conditional block, cd /workspace is now the first executable statement

## Decisions Made

- Kept iproute2 and dnsutils in Dockerfile — iproute2 is useful for debugging network routes; dnsutils provides dig/getent needed to verify proxy DNS resolution post-migration
- init-firewall.py and policy.json remain on disk intentionally — physical deletion deferred to Plan 04 after smoke tests pass
- USER root added before COPY entrypoint.sh — this was previously in the firewall block that was removed; needed for writing to /usr/local/bin/

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Restored USER root before entrypoint COPY**
- **Found during:** Task 1 (clean firewall packages and COPY directives)
- **Issue:** The removed firewall block contained `USER root` which was also required for the subsequent `COPY entrypoint.sh /usr/local/bin/` and `RUN chmod +x` operations. Without it, those steps would run as the non-root `${USERNAME}` user and fail to write to /usr/local/bin/.
- **Fix:** Added `USER root` directive immediately before the entrypoint COPY section
- **Files modified:** images/base/Dockerfile
- **Verification:** Dockerfile reviewed and USER root is in place before COPY entrypoint.sh
- **Committed in:** a2a8131 (Task 1 commit)

---

**Total deviations:** 1 auto-fixed (1 bug)
**Impact on plan:** Fix was essential for Dockerfile correctness. No scope creep.

## Issues Encountered

None beyond the auto-fixed USER root issue above.

## Self-Check: PASSED

All files and commits verified present.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Base image no longer needs NET_ADMIN or NET_RAW capabilities
- Plan 03 can now remove cap_add from docker-compose.yml
- Plan 04 can delete init-firewall.py and policy.json after smoke tests confirm the proxy approach works end-to-end

---
*Phase: 01-proxy-infrastructure*
*Completed: 2026-03-24*
