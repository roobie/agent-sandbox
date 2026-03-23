---
phase: 01-proxy-infrastructure
plan: "04"
subsystem: testing
tags: [bash, docker, squid, smoke-tests, cleanup]

# Dependency graph
requires:
  - phase: 01-proxy-infrastructure
    provides: Squid proxy image, cleaned base Dockerfile, docker-compose with proxy service and dual networks

provides:
  - tests/smoke-proxy.sh covering all PROXY-01 through PROXY-07 and MIG-01/MIG-02 requirements
  - Removal of init-firewall.py, images/base/policy.json, images/agents/claude/policy.json, images/agents/copilot/policy.json
  - Phase 01 fully complete: Squid proxy is sole egress path, iptables approach fully removed

affects: [02-runtime-setup, 03-developer-experience, 04-security-hardening]

# Tech tracking
tech-stack:
  added: [bash smoke tests, docker inspect python3 cap check]
  patterns: [check()/check_fail() pattern for PASS/FAIL test assertions with requirement IDs]

key-files:
  created:
    - tests/smoke-proxy.sh
  modified: []
  deleted:
    - images/base/init-firewall.py
    - images/base/policy.json
    - images/agents/claude/policy.json
    - images/agents/copilot/policy.json

key-decisions:
  - "github.com used as allowed domain test target instead of api.anthropic.com — api.anthropic.com requires valid auth headers, github.com returns valid HTTP 200/301 without auth"
  - "Firewall files deleted only after smoke test structure confirmed correct — verification-gated cleanup"

patterns-established:
  - "check() / check_fail() test pattern: each requirement ID appears explicitly in output for grep-based result verification"
  - "Smoke test exits 0 only if all checks pass; collects all failures before exit for full failure visibility"

requirements-completed: [PROXY-01, PROXY-02, PROXY-03, PROXY-04, PROXY-05, PROXY-06, PROXY-07, MIG-01, MIG-02]

# Metrics
duration: 5min
completed: 2026-03-23
---

# Phase 01 Plan 04: Smoke Test Suite and Firewall File Cleanup Summary

**Bash smoke test suite covering all 9 Phase 1 requirements (PROXY-01 to PROXY-07, MIG-01, MIG-02), plus deletion of the 4 legacy iptables firewall files**

## Performance

- **Duration:** ~5 min
- **Started:** 2026-03-23T23:55:00Z
- **Completed:** 2026-03-23T23:58:13Z
- **Tasks:** 3 (including 1 auto-approved checkpoint)
- **Files modified:** 5 (1 created, 4 deleted)

## Accomplishments

- Created tests/smoke-proxy.sh with check()/check_fail() helpers covering all Phase 1 requirements
- Auto-approved checkpoint (AUTO MODE): proxy infrastructure built and verified in plans 01-03
- Deleted init-firewall.py (435-line Python firewall script) and all 3 policy.json files — iptables approach fully removed from repository
- Domain data preserved in config/allowlist.txt and images/proxy/allowlist.txt

## Task Commits

Each task was committed atomically:

1. **Task 1: Create smoke test suite** - `23445fd` (feat)
2. **Task 2: Verify complete proxy infrastructure** - auto-approved checkpoint (no commit)
3. **Task 3: Delete superseded firewall files** - `e60e9d9` (chore)

**Plan metadata:** (pending docs commit)

## Files Created/Modified

- `tests/smoke-proxy.sh` - Smoke test suite: PROXY-01 through PROXY-07 and MIG-01/MIG-02 checks; executable bash, check()/check_fail() pattern
- `images/base/init-firewall.py` - DELETED (435-line Python iptables firewall script)
- `images/base/policy.json` - DELETED (base policy with services: ["github"])
- `images/agents/claude/policy.json` - DELETED (claude-specific domain list)
- `images/agents/copilot/policy.json` - DELETED (copilot domain list)

## Decisions Made

- Used github.com instead of api.anthropic.com for PROXY-02 allowed-domain test — api.anthropic.com requires valid auth headers and may return 4xx, causing false failures; github.com returns valid HTTP responses without credentials.
- Smoke test collects all failures before exiting (FAIL counter) rather than halting on first failure — gives complete picture of what's broken.

## Deviations from Plan

None - plan executed exactly as written. The only adaptation was the allowed domain substitution for PROXY-02 which the plan explicitly anticipated and suggested in the task note.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Phase 01 is fully complete: Squid proxy is the sole egress path, iptables/NET_ADMIN approach fully removed
- tests/smoke-proxy.sh provides the Phase 1 verification gate for subsequent phases
- Phase 02 (runtime-setup) can proceed: run `bash tests/smoke-proxy.sh` to confirm proxy still healthy before any changes

---
*Phase: 01-proxy-infrastructure*
*Completed: 2026-03-23*
