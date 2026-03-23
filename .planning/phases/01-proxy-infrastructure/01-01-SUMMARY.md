---
phase: 01-proxy-infrastructure
plan: 01
subsystem: infra
tags: [squid, docker, proxy, egress-control, allowlist]

# Dependency graph
requires: []
provides:
  - Squid proxy container image definition (images/proxy/Dockerfile)
  - Squid configuration with SNI peek/splice and dstdomain ACL (images/proxy/squid.conf)
  - Default domain allowlist baked into image (images/proxy/allowlist.txt)
  - Host-mount override allowlist source (config/allowlist.txt)
affects: [02-base-image-cleanup, 03-compose-wiring, 04-migration-cutover]

# Tech tracking
tech-stack:
  added: [squid 5.7 (debian:bookworm-slim), curl (health check)]
  patterns: [SNI peek/splice for HTTPS inspection without TLS decryption, dstdomain ACL with leading-dot subdomain wildcards, foreground squid (-N) for docker logs capture]

key-files:
  created:
    - images/proxy/Dockerfile
    - images/proxy/squid.conf
    - images/proxy/allowlist.txt
    - config/allowlist.txt
  modified: []

key-decisions:
  - "SNI peek/splice (ssl_bump peek all + ssl_bump splice all) chosen over plain CONNECT tunnel — reads TLS ClientHello SNI to prevent hostname spoofing without decrypting traffic"
  - "Debian bookworm squid package confirmed --with-openssl; build-time assertion added to Dockerfile to fail fast if this ever changes"
  - "All domains use leading-dot format (.github.com) for subdomain wildcard coverage — bare domain (github.com) would only match exact hostname, not CDN subdomains"
  - "config/allowlist.txt is the host-mount override source; images/proxy/allowlist.txt is the image-baked copy — identical content, separate paths for Compose volume mount in Plan 03"
  - "cache deny all: freshness preferred over performance for sandbox use"

patterns-established:
  - "Pattern: dstdomain ACL with leading-dot subdomain wildcards — all allowlist entries must have leading dot"
  - "Pattern: squid -N foreground mode + access_log stdio:/dev/stdout + cache_log stdio:/dev/stderr for docker logs capture"
  - "Pattern: image-baked default config + host-mount override — bake defaults into image, support ./config/ override at Compose volume mount"

requirements-completed: [PROXY-01, PROXY-02, PROXY-03, PROXY-05]

# Metrics
duration: 2min
completed: 2026-03-23
---

# Phase 01 Plan 01: Proxy Container Image Summary

**Squid 5.7 forward proxy with SNI peek/splice, dstdomain allowlist ACL, and consolidated domain list from all policy.json files**

## Performance

- **Duration:** 2 min
- **Started:** 2026-03-23T23:50:10Z
- **Completed:** 2026-03-23T23:51:50Z
- **Tasks:** 2
- **Files modified:** 4 created

## Accomplishments

- Buildable proxy image definition: `docker build -t agent-sandbox-proxy:local images/proxy` is ready
- Squid configuration with SNI peek/splice — verifies TLS destination hostname without decrypting traffic
- Consolidated allowlist.txt replacing policy.json IP-resolution approach with hostname-based ACL

## Task Commits

Each task was committed atomically:

1. **Task 1: Create proxy Dockerfile and squid.conf** - `6f7e096` (feat)
2. **Task 2: Create consolidated allowlist.txt** - `f959a7a` (feat)

## Files Created/Modified

- `images/proxy/Dockerfile` - FROM debian:bookworm-slim, installs squid+curl, asserts --with-openssl, runs squid -N in foreground
- `images/proxy/squid.conf` - http_port 3128, ssl_bump peek/splice, dstdomain ACL, deny-default, stdout/stderr logging, no cache
- `images/proxy/allowlist.txt` - 9 domain entries with leading-dot wildcards (GitHub, Anthropic, Sentry, PyPI, mise)
- `config/allowlist.txt` - Identical copy at host-mount override source path for Compose volume binding in Plan 03

## Decisions Made

- Build-time assertion `RUN squid -v 2>&1 | grep -q "with-openssl"` added to Dockerfile — fails the build immediately if Squid package lacks OpenSSL support rather than producing a container that crashes at runtime
- `files.pythonhosted.org` included in allowlist alongside `pypi.org` — PyPI serves package metadata from pypi.org but downloads from pythonhosted.org CDN; both are required
- No `ports:` binding in Compose (Plan 03 scope) — port 3128 accessible only within Docker internal network

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

The plan's automated verification uses `grep -q "squid -N"` but the Dockerfile CMD uses JSON array syntax `CMD ["squid", "-N", ...]` which doesn't contain the literal substring `squid -N`. All acceptance criteria are met — the `-N` flag is present and correct. The verify grep pattern is a minor false negative in the plan spec, not a code issue.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- images/proxy/ directory is ready for `docker build`
- config/allowlist.txt is ready for Compose volume mount binding in Plan 03
- Plan 02 (base image cleanup) can remove init-firewall.py, policy.json files, and iptables packages
- Plan 03 (compose wiring) can add proxy service with `./config/allowlist.txt:/etc/squid/allowlist.txt:ro` volume mount

---
*Phase: 01-proxy-infrastructure*
*Completed: 2026-03-23*
