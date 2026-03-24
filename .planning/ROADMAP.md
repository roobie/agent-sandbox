# Roadmap: Agent Sandbox

## Overview

Four phases that take the project from its current per-container iptables approach to a published, hardened Squid-proxy-based sandbox toolkit. Phase 1 establishes the proxy infrastructure and cleanly removes the iptables approach — this is the architectural pivot everything else depends on. Phase 2 closes the container hardening baseline. Phase 3 builds out the full development environment with language runtimes and mise-based orchestration. Phase 4 adds observability and publishes the finished image.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [x] **Phase 1: Proxy Infrastructure** - Squid proxy container with dual-network topology, domain allowlist ACL, and complete iptables migration cutover (completed 2026-03-23)
- [x] **Phase 2: Container Hardening** - Read-only rootfs, capability dropping, resource limits, and seccomp baseline (completed 2026-03-24)
- [ ] **Phase 3: Development Environment** - Full language runtime suite via mise, per-package-manager proxy config, and mise task orchestration
- [ ] **Phase 4: Observability and Distribution** - Filesystem diff logging, Squid access log auditing, and GHCR image publishing via CI

## Phase Details

### Phase 1: Proxy Infrastructure
**Goal**: The shared Squid proxy container is the sole egress path for all sandbox containers, enforcing a domain allowlist ACL via HTTPS SNI peek/splice; the old iptables approach is fully removed.
**Depends on**: Nothing (first phase)
**Requirements**: PROXY-01, PROXY-02, PROXY-03, PROXY-04, PROXY-05, PROXY-06, PROXY-07, MIG-01, MIG-02
**Success Criteria** (what must be TRUE):
  1. Running `docker compose up proxy` starts a Squid container that passes its health check before any sandbox starts
  2. A sandbox container cannot make a direct TCP connection to a blocked domain — the connection is denied by Squid ACL, not by iptables in the sandbox
  3. A sandbox container can successfully reach a domain on the allowlist (e.g., `curl https://github.com` works, `curl https://example-blocked.com` fails with a Squid error)
  4. Two sandbox containers started simultaneously both route through the same Squid proxy and appear in the same access log
  5. `init-firewall.py` is absent from all image layers; sandbox containers carry no NET_ADMIN or NET_RAW capabilities
**Plans**: 4 plans

Plans:
- [ ] 01-01-PLAN.md — Proxy container image (Dockerfile, squid.conf, allowlist.txt)
- [ ] 01-02-PLAN.md — Base image migration (remove firewall packages and entrypoint block)
- [ ] 01-03-PLAN.md — Compose orchestration and build tooling (docker-compose.yml, build.py)
- [ ] 01-04-PLAN.md — Smoke test suite and old file deletion

### Phase 2: Container Hardening
**Goal**: Sandbox containers run with minimal privileges — read-only filesystem, all capabilities dropped, default seccomp profile, and configurable resource limits.
**Depends on**: Phase 1
**Requirements**: HARD-01, HARD-02, HARD-03, HARD-04
**Success Criteria** (what must be TRUE):
  1. A running sandbox container has a read-only rootfs; writes to `/` fail but writes to `/tmp` succeed
  2. `docker inspect` on a running sandbox shows `CapAdd: null`, `SecurityOpt: [no-new-privileges]`, and no CAP_NET_ADMIN
  3. CPU, memory, and PID limits can be changed via environment variable or config before `sandbox:run` without modifying the Compose file
**Plans**: 2 plans

Plans:
- [ ] 02-01-PLAN.md — Smoke test scaffold, compose hardening directives, and entrypoint read-only rootfs fix
- [ ] 02-02-PLAN.md — Build, start, and human verification of all HARD-* requirements

### Phase 3: Development Environment
**Goal**: Sandbox containers arrive with a fully-functional development environment — all language runtimes pre-installed and accessible, per-package-manager proxy configuration active so all install traffic routes through Squid, and mise tasks on the host covering the full sandbox lifecycle.
**Depends on**: Phase 2
**Requirements**: DEVENV-01, DEVENV-02, DEVENV-03, DEVENV-04, DEVENV-05, DEVENV-06, DEVENV-07, ORCH-01, ORCH-02, ORCH-03, ORCH-04
**Success Criteria** (what must be TRUE):
  1. Inside a fresh sandbox with a newly-removed cache volume, `node --version`, `python --version`, `go version`, `rustc --version`, `bun --version`, and `uv --version` all succeed without any post-start installation
  2. Running `npm install lodash` inside a sandbox produces entries in the Squid access log confirming the traffic traversed the proxy (not a direct connection)
  3. Package cache volumes (npm, pip, cargo, go) survive sandbox stop/start — a second `npm install` of the same package does not re-download from the internet
  4. `mise run proxy:start`, `mise run sandbox:run`, and `mise run sandbox:stop` work from the host to manage the full lifecycle
  5. Two named sandbox instances can run simultaneously against different workspaces via a single `mise run sandbox:run NAME=foo WORKSPACE=...` invocation pattern
**Plans**: 4 plans

Plans:
- [ ] 03-01-PLAN.md — Dockerfile: system-wide runtime installs + proxy config files baked into image
- [ ] 03-02-PLAN.md — Compose: package cache volumes, proxy env vars, and expanded Squid allowlist
- [ ] 03-03-PLAN.md — mise.toml: host lifecycle tasks (proxy, sandbox, image)
- [ ] 03-04-PLAN.md — Integration smoke test and human verification checkpoint

### Phase 4: Observability and Distribution
**Goal**: Sandbox activity is auditable via Docker logs and filesystem diffs; images are published to GHCR so users can pull without building locally; all existing Docker artifacts are either integrated or explicitly removed.
**Depends on**: Phase 3
**Requirements**: OBS-01, OBS-02, OBS-03, DIST-01, DIST-02, DIST-03
**Success Criteria** (what must be TRUE):
  1. After a sandbox run, `docker logs <container>` shows the agent's stdout/stderr and a filesystem diff summary is emitted on stop
  2. Squid access logs are reachable from the host (via volume or `docker logs`) and show which domains the agent contacted during a run
  3. `docker pull ghcr.io/<org>/agent-sandbox:latest` succeeds without a local build; the image is published by a GitHub Actions workflow on push to main
  4. `mise run image:build` builds the image locally from source; no orphaned Dockerfiles or compose fragments exist from the old iptables approach
**Plans**: TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3 → 4

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Proxy Infrastructure | 4/4 | Complete   | 2026-03-23 |
| 2. Container Hardening | 2/2 | Complete   | 2026-03-24 |
| 3. Development Environment | 0/TBD | Not started | - |
| 4. Observability and Distribution | 0/TBD | Not started | - |
