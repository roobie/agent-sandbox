---
phase: 3
slug: development-environment
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-24
---

# Phase 3 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | bash + docker CLI (integration tests) |
| **Config file** | none — inline docker commands |
| **Quick run command** | `docker exec agent-sandbox node --version` |
| **Full suite command** | `bash tests/smoke-devenv.sh` |
| **Estimated runtime** | ~20 seconds |

---

## Sampling Rate

- **After every task commit:** Run quick version check
- **After every plan wave:** Run `bash tests/smoke-devenv.sh`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 20 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 03-01-01 | 01 | 1 | DEVENV-01 | integration | `docker exec sandbox dpkg -l git curl ripgrep` | ❌ W0 | ⬜ pending |
| 03-01-02 | 01 | 1 | DEVENV-02 | integration | `docker exec sandbox node --version && python --version && go version && rustc --version && bun --version && uv --version` | ❌ W0 | ⬜ pending |
| 03-01-03 | 01 | 1 | DEVENV-05 | integration | `docker exec sandbox which rust-analyzer && which pyright` | ❌ W0 | ⬜ pending |
| 03-02-01 | 02 | 1 | DEVENV-07 | integration | `docker exec sandbox npm config get proxy` returns proxy URL | ❌ W0 | ⬜ pending |
| 03-02-02 | 02 | 1 | DEVENV-04 | integration | second npm install doesn't re-download (cache hit) | ❌ W0 | ⬜ pending |
| 03-03-01 | 03 | 2 | ORCH-01 | integration | `mise run proxy:start` succeeds | ❌ W0 | ⬜ pending |
| 03-03-02 | 03 | 2 | ORCH-02 | integration | `mise run sandbox:run` succeeds | ❌ W0 | ⬜ pending |
| 03-03-03 | 03 | 2 | ORCH-03 | integration | Two named sandboxes run simultaneously | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `tests/smoke-devenv.sh` — integration test covering all DEVENV-* and ORCH-* requirements

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Package manager traffic in Squid logs | DEVENV-07 | Requires reading Squid access log during install | Run `npm install lodash` inside sandbox, check `docker logs agent-sandbox-proxy` for npm registry requests |

---

## Validation Sign-Off

- [ ] All tasks have automated verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 20s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
