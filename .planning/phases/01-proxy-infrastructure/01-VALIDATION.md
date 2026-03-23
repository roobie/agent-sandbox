---
phase: 1
slug: proxy-infrastructure
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-24
---

# Phase 1 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | bash + docker CLI (integration tests via shell scripts) |
| **Config file** | none — tests are inline docker/curl commands |
| **Quick run command** | `docker compose exec sandbox curl -sf -x http://squid:3128 https://github.com` |
| **Full suite command** | `mise run test:proxy` |
| **Estimated runtime** | ~15 seconds |

---

## Sampling Rate

- **After every task commit:** Run quick connectivity check
- **After every plan wave:** Run `mise run test:proxy`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 15 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 01-01-01 | 01 | 1 | PROXY-01 | integration | `docker compose ps proxy --format json \| jq '.State'` | ❌ W0 | ⬜ pending |
| 01-01-02 | 01 | 1 | PROXY-02 | integration | `docker compose exec sandbox curl -sf -x http://squid:3128 https://blocked.example.com; echo $?` | ❌ W0 | ⬜ pending |
| 01-01-03 | 01 | 1 | PROXY-03 | integration | `docker compose logs proxy \| grep -q 'CONNECT'` | ❌ W0 | ⬜ pending |
| 01-01-04 | 01 | 1 | PROXY-04 | integration | `docker compose exec sandbox-2 curl -sf -x http://squid:3128 https://github.com` | ❌ W0 | ⬜ pending |
| 01-01-05 | 01 | 1 | PROXY-05 | integration | `docker compose exec sandbox curl -sf https://example.com; echo $?` (must fail — no direct internet) | ❌ W0 | ⬜ pending |
| 01-01-06 | 01 | 1 | PROXY-06 | integration | `docker compose exec sandbox env \| grep HTTP_PROXY` | ❌ W0 | ⬜ pending |
| 01-01-07 | 01 | 1 | PROXY-07 | integration | `docker compose up sandbox --wait` (depends_on healthy) | ❌ W0 | ⬜ pending |
| 01-02-01 | 02 | 1 | MIG-01 | file check | `docker compose exec sandbox test ! -f /usr/local/bin/init-firewall.py` | ❌ W0 | ⬜ pending |
| 01-02-02 | 02 | 1 | MIG-02 | integration | `docker inspect sandbox \| jq '.[0].HostConfig.CapAdd'` (must be null) | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `tests/test-proxy.sh` — integration test script covering all PROXY-* and MIG-* requirements
- [ ] mise task `test:proxy` — runs the integration test suite

*These are created as part of the implementation plans, not as a separate wave.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| SNI hostname verification | PROXY-03 | Requires crafting a spoofed CONNECT vs actual TLS hostname | Manually attempt CONNECT to github.com:443 but send TLS ClientHello with different SNI; verify Squid denies |

---

## Validation Sign-Off

- [ ] All tasks have automated verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 15s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
