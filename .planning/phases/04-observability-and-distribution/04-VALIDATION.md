---
phase: 4
slug: observability-and-distribution
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-24
---

# Phase 4 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | bash smoke tests (tests/smoke-proxy.sh pattern) |
| **Config file** | none — extends existing smoke test pattern |
| **Quick run command** | `bash tests/smoke-obs.sh` |
| **Full suite command** | `bash tests/smoke-obs.sh && bash tests/smoke-proxy.sh` |
| **Estimated runtime** | ~30 seconds |

---

## Sampling Rate

- **After every task commit:** Run `bash tests/smoke-obs.sh`
- **After every plan wave:** Run `bash tests/smoke-obs.sh && bash tests/smoke-proxy.sh`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 04-01-01 | 01 | 1 | OBS-01 | smoke | `docker logs agent-sandbox-default 2>&1 \| head -5` | ❌ W0 | ⬜ pending |
| 04-01-02 | 01 | 1 | OBS-02 | smoke | `mise run sandbox:stop -n test && grep -q "Container filesystem" /dev/stdout` | ❌ W0 | ⬜ pending |
| 04-01-03 | 01 | 1 | OBS-03 | smoke | `docker logs agent-sandbox-proxy 2>&1 \| grep -q CONNECT` | ✅ | ⬜ pending |
| 04-02-01 | 02 | 1 | DIST-01 | ci | `.github/workflows/build-images.yml contains build-proxy` | ❌ W0 | ⬜ pending |
| 04-02-02 | 02 | 1 | DIST-02 | smoke | `mise run image:build` exits 0 | ✅ | ⬜ pending |
| 04-02-03 | 02 | 1 | DIST-03 | grep | `grep -r "init-firewall\|policy.json" images/ \| wc -l` returns 0 | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `tests/smoke-obs.sh` — observability smoke test script (OBS-01, OBS-02, OBS-03)
- [ ] Extend existing `tests/smoke-proxy.sh` pattern for consistency

*Existing smoke test infrastructure (tests/smoke-proxy.sh) provides the pattern. New test file needed for observability-specific checks.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| GHCR pull succeeds | DIST-01 | Requires pushed image + GHCR auth | After CI runs: `docker pull ghcr.io/<org>/agent-sandbox-claude:latest` |
| Filesystem diff shows meaningful output | OBS-02 | Requires agent activity in sandbox | Start sandbox, create a file, run `mise run sandbox:stop`, verify diff output |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
