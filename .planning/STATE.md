# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-03-24)

**Core value:** Agents can fetch anything they need from the web but cannot exfiltrate data to unauthorized destinations — enforced at the network layer, not by trusting the agent.
**Current focus:** Phase 1 — Proxy Infrastructure

## Current Position

Phase: 1 of 4 (Proxy Infrastructure)
Plan: 0 of TBD in current phase
Status: Ready to plan
Last activity: 2026-03-24 — Roadmap created

Progress: [░░░░░░░░░░] 0%

## Performance Metrics

**Velocity:**
- Total plans completed: 0
- Average duration: —
- Total execution time: 0 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| - | - | - | - |

**Recent Trend:**
- Last 5 plans: —
- Trend: —

*Updated after each plan completion*

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- [Pre-phase]: Squid proxy over iptables — centralized control, no NET_ADMIN per sandbox, hostname-based ACL stays current on CDNs
- [Pre-phase]: Shared proxy (not sidecar) — one proxy for N sandboxes, one ACL config
- [Pre-phase]: mise for both runtime management (inside container) and lifecycle orchestration (host)

### Pending Todos

None yet.

### Blockers/Concerns

- Migration cutover (Phase 1): Running init-firewall.py alongside proxy simultaneously corrupts Docker DNS NAT — must be a clean single cutover. Verify with `getent hosts squid` inside sandbox immediately after.
- Runtime volume shadowing (Phase 3): mise runtimes must be installed via `mise install --system` in Dockerfile or they get shadowed by home directory volume mounts at runtime.
- Package manager proxy bypass (Phase 3): HTTP_PROXY env alone is insufficient for npm, cargo, git, go — requires per-tool config. Completion gate: verify each package manager appears in Squid access logs during install.

## Session Continuity

Last session: 2026-03-24
Stopped at: Roadmap created, requirements traceability updated, ready for Phase 1 planning
Resume file: None
