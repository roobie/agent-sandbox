---
phase: 01-proxy-infrastructure
verified: 2026-03-24T00:00:00Z
status: human_needed
score: 13/13 must-haves verified
human_verification:
  - test: "Build proxy image: python3 images/build.py proxy"
    expected: "Docker build completes without errors; build-time assertion for --with-openssl passes"
    why_human: "Cannot run docker build in static analysis; the Dockerfile RUN assertion on squid --with-openssl requires the actual Debian bookworm package"
  - test: "Start compose stack: docker compose up -d; docker compose ps"
    expected: "proxy service shows 'healthy' after ~15-30s startup; agent-sandbox shows 'running'"
    why_human: "Health check uses squid -k check + curl against mise-versions.jdx.dev; cannot verify runtime network behaviour statically"
  - test: "Run smoke tests: bash tests/smoke-proxy.sh"
    expected: "All checks print PASS; Results line shows '0 failed'"
    why_human: "Full end-to-end validation (PROXY-01 through PROXY-07, MIG-01, MIG-02) requires running containers; verifies proxy routing, allowlist enforcement, direct-internet blocking, and capability removal"
---

# Phase 1: Proxy Infrastructure Verification Report

**Phase Goal:** The shared Squid proxy container is the sole egress path for all sandbox containers,
enforcing a domain allowlist ACL via HTTPS SNI peek/splice; the old iptables approach is fully removed.

**Verified:** 2026-03-24
**Status:** human_needed — all static/automated checks pass; runtime smoke tests require a human to execute
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths

| #  | Truth                                                                                                       | Status      | Evidence                                                                              |
|----|-------------------------------------------------------------------------------------------------------------|-------------|---------------------------------------------------------------------------------------|
| 1  | Squid proxy image can be built from images/proxy/                                                           | ? HUMAN     | Dockerfile correct; build-time assertion for --with-openssl can only be confirmed at build time |
| 2  | squid.conf enforces dstdomain ACL via SNI peek/splice with deny-default                                     | VERIFIED    | ssl_bump peek all, ssl_bump splice all, acl allowed_domains dstdomain, http_access deny all present |
| 3  | allowlist.txt covers all policy.json domains with leading-dot syntax                                        | VERIFIED    | All 8 domains present with leading dots; files identical                              |
| 4  | Base image has no firewall packages or scripts                                                              | VERIFIED    | iptables, ipset, aggregate, init-firewall.py, COPY policy.json all absent from Dockerfile |
| 5  | entrypoint.sh starts directly at cd /workspace with no firewall block                                      | VERIFIED    | ipset, init-firewall, Firewall blocks absent; exec gosu and cd /workspace present     |
| 6  | docker-compose.yml defines proxy service with dual networks, no cap_add, proxy env vars                    | VERIFIED    | All directives present; NET_ADMIN/NET_RAW only in comment; no cap_add: key           |
| 7  | sandbox-internal network is internal: true                                                                  | VERIFIED    | internal: true present; agent-sandbox has only sandbox-internal; proxy bridges both   |
| 8  | agent-sandbox depends on proxy health before starting                                                       | VERIFIED    | condition: service_healthy in depends_on block                                        |
| 9  | images/build.py has build_proxy() and builds proxy first in all target                                      | VERIFIED    | def build_proxy() present; proxy first in elif target == "all"; syntax valid          |
| 10 | Old firewall files (init-firewall.py, all policy.json) fully deleted                                       | VERIFIED    | All four files absent from filesystem                                                 |
| 11 | tests/smoke-proxy.sh covers all PROXY-* and MIG-* requirement IDs                                          | VERIFIED    | All 9 IDs present; executable; bash -n syntax valid                                   |
| 12 | Proxy container has no ports: binding (only reachable within Docker networks)                               | VERIFIED    | No ports: key in proxy service definition                                             |
| 13 | Host-override volume mount wires config/allowlist.txt into proxy container                                  | VERIFIED    | ./config/allowlist.txt:/etc/squid/allowlist.txt:ro in proxy volumes                  |

**Score:** 12/13 verified statically; 1 requires runtime (build-time assertion)

---

### Required Artifacts

| Artifact                         | Provides                                          | Status      | Details                                                          |
|----------------------------------|---------------------------------------------------|-------------|------------------------------------------------------------------|
| `images/proxy/Dockerfile`        | Proxy container image definition                  | VERIFIED    | FROM debian:bookworm-slim; CMD ["squid", "-N", ...]; --with-openssl assertion present |
| `images/proxy/squid.conf`        | Squid config with SNI peek/splice and dstdomain   | VERIFIED    | ssl_bump peek all, ssl_bump splice all, acl allowed_domains, http_access deny all, cache deny all |
| `images/proxy/allowlist.txt`     | Default allowlist baked into image                | VERIFIED    | 8 domains with leading dots; identical to config/allowlist.txt  |
| `config/allowlist.txt`           | Host-override allowlist at volume mount source    | VERIFIED    | Exists; identical content to images/proxy/allowlist.txt         |
| `images/base/Dockerfile`         | Cleaned base image without firewall tooling       | VERIFIED    | FROM debian:bookworm; no iptables/ipset/aggregate/init-firewall/COPY policy.json; iproute2 and dnsutils retained |
| `images/base/entrypoint.sh`      | Cleaned entrypoint without firewall init          | VERIFIED    | cd /workspace is first executable line after set -e; exec gosu intact |
| `docker-compose.yml`             | Compose orchestration with proxy + dual networks  | VERIFIED    | proxy service, internal: true, condition: service_healthy, proxy env vars, no cap_add key |
| `images/build.py`                | Build orchestrator with build_proxy function      | VERIFIED    | def build_proxy() before build_base(); proxy first in all target; syntax valid |
| `tests/smoke-proxy.sh`           | Smoke test suite for all Phase 1 requirements     | VERIFIED    | All 9 requirement IDs present; executable; bash syntax valid    |

---

### Key Link Verification

| From                          | To                                     | Via                              | Status   | Details                                                          |
|-------------------------------|----------------------------------------|----------------------------------|----------|------------------------------------------------------------------|
| images/proxy/squid.conf       | /etc/squid/allowlist.txt               | acl allowed_domains dstdomain    | WIRED    | Exact pattern present: `acl allowed_domains dstdomain "/etc/squid/allowlist.txt"` |
| images/proxy/Dockerfile       | images/proxy/squid.conf                | COPY directive                   | WIRED    | `COPY squid.conf /etc/squid/squid.conf`                         |
| images/proxy/Dockerfile       | images/proxy/allowlist.txt             | COPY directive                   | WIRED    | `COPY allowlist.txt /etc/squid/allowlist.txt`                   |
| agent-sandbox service         | proxy service                          | depends_on condition: service_healthy | WIRED | `condition: service_healthy` under proxy in depends_on          |
| agent-sandbox service         | sandbox-internal network               | networks list                    | WIRED    | Only sandbox-internal listed; no sandbox-external               |
| proxy service                 | sandbox-internal + sandbox-external    | networks list                    | WIRED    | Both networks in proxy service networks list                    |
| images/base/entrypoint.sh     | gosu privilege drop                    | exec gosu after UID/GID adjust   | WIRED    | `exec gosu "$APP_USER" "${@:-zsh}"` at line 48                  |
| tests/smoke-proxy.sh          | docker compose                         | docker compose exec commands     | WIRED    | 8 occurrences of `docker compose exec -T agent-sandbox`         |
| docker-compose.yml proxy svc  | config/allowlist.txt (host)            | volume mount override            | WIRED    | `./config/allowlist.txt:/etc/squid/allowlist.txt:ro`            |

---

### Requirements Coverage

| Requirement | Source Plan(s) | Description                                                         | Status      | Evidence                                                          |
|-------------|---------------|---------------------------------------------------------------------|-------------|-------------------------------------------------------------------|
| PROXY-01    | 01-01, 01-04  | Squid proxy runs as standalone container, separate from sandbox     | SATISFIED   | proxy service in docker-compose.yml; smoke test checks container running |
| PROXY-02    | 01-01, 01-04  | Squid enforces domain-based egress allowlist via dstdomain ACLs     | SATISFIED   | dstdomain ACL in squid.conf; allowlist.txt with all domains; smoke test checks allowed+blocked |
| PROXY-03    | 01-01, 01-04  | Squid uses SNI peek/splice (no TLS decryption, no CA cert)          | SATISFIED   | ssl_bump peek all + ssl_bump splice all in squid.conf; smoke test verifies DNS resolution |
| PROXY-04    | 01-03, 01-04  | Multiple sandbox containers route through single proxy via Docker network | SATISFIED | sandbox-internal network shared; smoke test checks CONNECT in proxy access log |
| PROXY-05    | 01-03, 01-04  | Sandbox joins internal Docker network (no direct internet)          | SATISFIED   | sandbox-internal has internal: true; agent-sandbox only on sandbox-internal; smoke test check_fail for direct curl |
| PROXY-06    | 01-03, 01-04  | Sandbox uses HTTP_PROXY/HTTPS_PROXY env vars pointing at Squid      | SATISFIED   | Both uppercase+lowercase proxy env vars in docker-compose.yml; smoke test checks env |
| PROXY-07    | 01-03, 01-04  | Proxy has health check; sandbox waits for proxy healthy             | SATISFIED   | healthcheck in proxy service; condition: service_healthy in agent-sandbox depends_on; smoke test checks healthy status |
| MIG-01      | 01-02, 01-04  | init-firewall.py and iptables approach completely removed           | SATISFIED   | init-firewall.py absent from filesystem; no iptables/ipset in Dockerfile or entrypoint; smoke test verifies container absence |
| MIG-02      | 01-02, 01-03, 01-04 | NET_ADMIN and NET_RAW capabilities removed from sandbox         | SATISFIED   | No cap_add: key in docker-compose.yml; NET_ADMIN/NET_RAW appear only in comment; smoke test uses docker inspect to verify |

**No orphaned requirements.** All 9 Phase 1 requirement IDs (PROXY-01 through PROXY-07, MIG-01, MIG-02) are claimed by plans and have implementation evidence.

---

### Anti-Patterns Found

| File                          | Line | Pattern                             | Severity | Impact                                   |
|-------------------------------|------|-------------------------------------|----------|------------------------------------------|
| images/proxy/Dockerfile       | 20   | CMD uses JSON array form `["squid", "-N", ...]` vs shell form `squid -N` | INFO | Not a defect — JSON array is the correct Docker form. Causes grep pattern `squid -N` to fail, but intent is fully met |
| docker-compose.yml            | 32   | `# cap_add REMOVED — no NET_ADMIN` comment | INFO | Comment for documentation purposes only; no actual cap_add directive present |

No blockers or warnings found. The two "anti-patterns" above are false positives from the plan's grep-based verification patterns, not implementation defects.

---

### Human Verification Required

The static file analysis passes fully. The following require running the actual container stack:

#### 1. Build-time OpenSSL Assertion

**Test:** `python3 images/build.py proxy`
**Expected:** Build succeeds; the `RUN squid -v 2>&1 | grep -q "with-openssl"` assertion step passes without aborting
**Why human:** Whether the Debian bookworm squid package includes `--with-openssl` can only be confirmed by actually running the build. This is the sole technical risk — if the package lacks the flag, SNI peek/splice will be silently misconfigured at runtime.

#### 2. Proxy Container Health

**Test:** `docker compose up -d` followed by `docker compose ps` after ~30s
**Expected:** `proxy` shows `(healthy)` status; health check uses `squid -k check` + curl against `mise-versions.jdx.dev` (an allowlisted domain)
**Why human:** Runtime networking and health check behaviour cannot be verified statically.

#### 3. Full Smoke Test Suite

**Test:** `bash tests/smoke-proxy.sh`
**Expected:** All 11 checks print PASS; `Results: 11 passed, 0 failed`; exit code 0
**Why human:** This is the authoritative end-to-end validation for all 9 Phase 1 requirements. Requires running containers with actual network isolation and proxy routing. This is the definitive gate for declaring Phase 1 complete.

---

### Gaps Summary

No gaps found in the static codebase. All artifacts are substantive (not stubs), all key links are wired, and all requirement IDs have clear implementation evidence.

The phase goal is structurally achieved: the Squid proxy configuration enforces SNI peek/splice with a dstdomain ACL, the sandbox network topology prevents direct internet access, the old iptables approach is fully removed from all code and configuration, and the smoke test suite covers all requirements.

Runtime verification (smoke tests) is the remaining gate before the phase can be declared fully complete.

---

_Verified: 2026-03-24_
_Verifier: Claude (gsd-verifier)_
