---
phase: 2
slug: container-hardening
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-24
---

# Phase 2 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | bash + docker CLI (integration tests via shell scripts) |
| **Config file** | none — tests are inline docker commands |
| **Quick run command** | `docker inspect agent-sandbox --format '{{.HostConfig.ReadonlyRootfs}}'` |
| **Full suite command** | `bash tests/smoke-hardening.sh` |
| **Estimated runtime** | ~10 seconds |

---

## Sampling Rate

- **After every task commit:** Run quick docker inspect check
- **After every plan wave:** Run `bash tests/smoke-hardening.sh`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 10 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 02-01-01 | 01 | 1 | HARD-01 | integration | `docker inspect agent-sandbox --format '{{.HostConfig.ReadonlyRootfs}}'` returns `true` | ❌ W0 | ⬜ pending |
| 02-01-02 | 01 | 1 | HARD-01 | integration | `docker exec agent-sandbox sh -c 'touch /testfile 2>&1; echo $?'` returns nonzero | ❌ W0 | ⬜ pending |
| 02-01-03 | 01 | 1 | HARD-02 | integration | `docker inspect agent-sandbox --format '{{.HostConfig.CapDrop}}'` contains `ALL` | ❌ W0 | ⬜ pending |
| 02-01-04 | 01 | 1 | HARD-02 | integration | `docker inspect agent-sandbox --format '{{.HostConfig.SecurityOpt}}'` contains `no-new-privileges` | ❌ W0 | ⬜ pending |
| 02-01-05 | 01 | 1 | HARD-03 | integration | `docker inspect agent-sandbox --format '{{.HostConfig.SecurityOpt}}'` does NOT contain `seccomp=unconfined` | ❌ W0 | ⬜ pending |
| 02-01-06 | 01 | 1 | HARD-04 | integration | `docker inspect agent-sandbox --format '{{.HostConfig.PidsLimit}}'` returns nonzero | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `tests/smoke-hardening.sh` — integration test script covering all HARD-* requirements

*Created as part of the implementation plan.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| entrypoint UID/GID adjustment under read-only rootfs | HARD-01 | Requires host UID != 500 to trigger failure path | Run `docker compose up` with host user UID != 500, verify container starts or fails gracefully |

---

## Validation Sign-Off

- [ ] All tasks have automated verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 10s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
