# Phase 4: Observability and Distribution - Context

**Gathered:** 2026-03-24
**Status:** Ready for planning

<domain>
## Phase Boundary

Sandbox activity is auditable via Docker logs and filesystem diffs; images are published to GHCR so users can pull without building locally; all existing Docker artifacts are either integrated or explicitly removed. This phase does NOT change proxy infrastructure (Phase 1), hardening (Phase 2), or the development environment (Phase 3).

</domain>

<decisions>
## Implementation Decisions

### Stdout/stderr capture (OBS-01)
- Docker already captures stdout/stderr by default — `docker logs <container>` works out of the box
- No additional work needed for basic capture
- Add `sandbox:logs` mise task for convenient access: `docker logs agent-sandbox-${NAME}`
- Add `proxy:logs` mise task: `docker logs agent-sandbox-proxy`

### Filesystem diff logging (OBS-02)
- Enhance `sandbox:stop` mise task to capture diffs BEFORE stopping the container
- Run `docker diff agent-sandbox-${NAME}` to show container filesystem changes (files added/modified/deleted outside volumes)
- Run `git -C ${WORKSPACE} diff --stat` to show workspace changes made by the agent
- Output both diffs to stdout so the user sees them in the terminal at stop time
- No separate log file or volume needed — terminal output is sufficient for v1
- Format: clear section headers ("=== Container filesystem changes ===" and "=== Workspace changes ===")

### Squid access log auditing (OBS-03)
- Already working: Squid logs to stdout via `access_log stdio:/dev/stdout` (configured in Phase 1)
- Accessible via `docker logs agent-sandbox-proxy`
- Add `proxy:logs` mise task with optional `--follow` flag for live tailing
- No additional Squid configuration changes needed

### CI/CD image publishing (DIST-01)
- Existing `.github/workflows/build-images.yml` already publishes base and claude images to GHCR
- Add proxy image publishing to the same workflow (third job: `build-proxy`)
- Proxy has no dependencies on base/claude — can build in parallel with base
- Keep existing tag strategy: `latest` on default branch, `sha-` prefix for commit SHAs, semver on releases
- Keep existing multi-platform build: linux/amd64, linux/arm64
- Verify Claude build-arg `BASE_IMAGE` correctly references the GHCR-published base image digest

### Local build via mise task (DIST-02)
- Already working: `mise run image:build` runs `python3 images/build.py all`
- No changes needed — DIST-02 is already satisfied

### Orphaned artifact cleanup (DIST-03)
- Audit all Docker-related files for orphaned artifacts from the pre-proxy iptables era
- Known candidates to evaluate:
  - `images/base/policy.json` — replaced by Squid allowlist (should have been removed in Phase 1)
  - `images/agents/claude/policy.json` — domains migrated to Squid allowlist
  - `images/agents/copilot/policy.json` — domains migrated to Squid allowlist
  - `images/base/init-firewall.py` — should already be removed (Phase 1 MIG-01)
  - `.devcontainer/policy.json` — may still be needed for devcontainer mode
  - `devcontainer/templates/` — evaluate if templates need updating for proxy-based approach
- Rule: if a file is unused and its function has been replaced, remove it; if it's still referenced, update it
- Document any kept files with a comment explaining why they're retained

### Claude's Discretion
- Exact format of filesystem diff output (section headers, spacing)
- Whether to add `--follow` or `--tail` flags to log mise tasks
- Proxy image job ordering in CI workflow (parallel with base, or sequential)
- Whether to add a CI smoke test step after image publishing
- Handling of copilot agent image in CI (currently not published — decide whether to add or skip)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Existing CI/CD
- `.github/workflows/build-images.yml` — Current GHCR publishing workflow for base + claude images; extend with proxy image

### Docker configuration
- `docker-compose.yml` — Current compose with proxy and sandbox services; sandbox:stop task references this
- `mise.toml` — Current mise tasks for proxy/sandbox lifecycle; extend with logs tasks and enhanced stop

### Build system
- `images/build.py` — Build orchestrator with `build_proxy()`, `build_base()`, `build_claude()` functions

### Prior phase context
- `.planning/phases/01-proxy-infrastructure/01-CONTEXT.md` — Squid logging decisions (stdout/stderr via stdio)
- `.planning/phases/02-container-hardening/02-CONTEXT.md` — Read-only rootfs, capability dropping
- `.planning/phases/03-development-environment/03-CONTEXT.md` — mise task patterns, volume strategy

### Artifacts to evaluate for cleanup
- `images/base/policy.json` — Pre-proxy iptables policy file (evaluate for removal)
- `images/agents/claude/policy.json` — Agent-specific iptables policy (evaluate for removal)
- `images/agents/copilot/policy.json` — Agent-specific iptables policy (evaluate for removal)
- `.devcontainer/policy.json` — Devcontainer policy (evaluate: still needed?)
- `devcontainer/templates/` — Template directory (evaluate: needs proxy-era update?)

### Requirements
- `.planning/REQUIREMENTS.md` — OBS-01, OBS-02, OBS-03, DIST-01, DIST-02, DIST-03

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `mise.toml`: Existing task patterns (`proxy:start`, `sandbox:run`, `sandbox:stop`) — extend with `sandbox:logs`, `proxy:logs`, and enhanced `sandbox:stop`
- `.github/workflows/build-images.yml`: Complete GHCR publishing pipeline — extend with proxy image job
- `images/build.py`: Build orchestrator — already has `build_proxy()` function

### Established Patterns
- mise task naming: `{service}:{action}` (e.g., `proxy:start`, `sandbox:run`)
- mise task args via usage blocks: `flag "--name -n <name>"` pattern
- CI workflow: docker/build-push-action@v5 with QEMU for multi-platform, GHA cache
- CI tag strategy: metadata-action@v5 with latest/sha/semver patterns

### Integration Points
- `mise.toml`: Add `sandbox:logs` and `proxy:logs` tasks; enhance `sandbox:stop` with diff capture
- `.github/workflows/build-images.yml`: Add `build-proxy` job; proxy image has no dependency on base
- Orphaned files: audit `images/*/policy.json`, `.devcontainer/policy.json`, `devcontainer/templates/`

</code_context>

<specifics>
## Specific Ideas

- Filesystem diffs shown at sandbox stop time — user sees what the agent changed without extra commands
- Log access should be as easy as `mise run sandbox:logs` — consistent with existing task UX
- CI publishes all three images (proxy, base, claude) so `docker pull` works without local build
- Orphaned iptables-era files must be explicitly removed or documented — no silent leftovers

</specifics>

<deferred>
## Deferred Ideas

- Structured audit log in JSON format (OBS-04 — v2 requirement)
- Real-time filesystem change monitoring via inotifywait (OBS-05 — v2 requirement)
- Copilot agent image publishing in CI — evaluate when copilot agent is mature enough
- Log rotation or aggregation — overkill for local dev tool

</deferred>

---

*Phase: 04-observability-and-distribution*
*Context gathered: 2026-03-24*
