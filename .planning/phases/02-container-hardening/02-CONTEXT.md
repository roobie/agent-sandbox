# Phase 2: Container Hardening - Context

**Gathered:** 2026-03-24
**Status:** Ready for planning

<domain>
## Phase Boundary

Sandbox containers run with minimal privileges — read-only filesystem, all capabilities dropped, default seccomp profile, and configurable resource limits. This phase hardens the container runtime without changing the proxy infrastructure (Phase 1) or the development environment inside (Phase 3).

</domain>

<decisions>
## Implementation Decisions

### Read-only rootfs and writable paths
- docker-compose.yml `read_only: true` on the agent-sandbox service
- Writable tmpfs mounts for runtime paths that must be writable:
  - `/tmp` — general temp files (tmpfs, 256MB, noexec)
  - `/run` — runtime state files (tmpfs, 64MB)
  - `/home/dev/.zsh_history` or the commandhistory volume already handles this
- Existing named volumes (claude-state, command-history, mise-state, cargo-state, local-bin-state) already provide writable storage for persistent state — these are not affected by read_only
- The workspace bind mount (`.:/workspace`) remains writable — this is where agents do their work

### Capability dropping
- `cap_drop: [ALL]` on the agent-sandbox service
- No capabilities added back — proxy approach eliminated need for NET_ADMIN/NET_RAW (Phase 1)
- `security_opt: [no-new-privileges:true]` prevents privilege escalation

### Seccomp profile
- Use Docker's default seccomp profile (do not specify a custom one)
- This blocks ~44 dangerous syscalls while allowing normal development tooling
- Custom seccomp tuning deferred to v2 after observing what agents actually need

### Resource limits
- Default values in docker-compose.yml, overridable via environment variables:
  - CPU: `${SANDBOX_CPUS:-2}` (2 CPUs default)
  - Memory: `${SANDBOX_MEMORY:-4g}` (4GB default)
  - PIDs: `${SANDBOX_PIDS:-512}` (512 processes default)
- Compose `deploy.resources.limits` section for cpus and memory
- `pids_limit` for PID limit
- No reservation (limits only, not guaranteed resources)

### Configuration mechanism
- Environment variables with defaults in docker-compose.yml
- Users override by setting `SANDBOX_CPUS=4` etc. before `docker compose up`
- No separate config file needed for this — compose env var substitution handles it

### Claude's Discretion
- Exact tmpfs size limits (256MB for /tmp is a starting point)
- Whether to add additional tmpfs mounts discovered during testing (e.g., /var/tmp)
- Exact PID limit value (512 is generous; 256 may suffice)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase 1 artifacts (foundation)
- `docker-compose.yml` — Current compose file with proxy wiring (Phase 2 adds hardening on top)
- `.planning/phases/01-proxy-infrastructure/01-CONTEXT.md` — Prior decisions about network topology and capability removal

### Research
- `.planning/research/STACK.md` — Container hardening recommendations
- `.planning/research/PITFALLS.md` — Devcontainer + read-only rootfs conflict note
- `docs/research.md` — Prior research on sandbox hardening patterns

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `docker-compose.yml`: Already has the agent-sandbox service definition — Phase 2 adds `read_only`, `cap_drop`, `security_opt`, `pids_limit`, and `deploy.resources.limits` to it
- Existing named volumes provide writable storage that's unaffected by read_only

### Established Patterns
- Compose env var substitution: `${TZ:-America/Los_Angeles}` pattern already used for TZ — extend for resource limits
- Service-level configuration in docker-compose.yml (not external config files)

### Integration Points
- `docker-compose.yml`: Add hardening directives to agent-sandbox service
- `images/base/Dockerfile`: May need to ensure /tmp and /run exist with correct permissions
- `images/base/entrypoint.sh`: May need adjustments if read-only rootfs affects startup

</code_context>

<specifics>
## Specific Ideas

- Resource limits should be easy to override without editing compose file (env vars)
- The proxy container does NOT get hardened in this phase — it needs write access for Squid cache/logs
- Devcontainer mode may need separate treatment (VS Code writes to container filesystem) — defer to Phase 3 or later

</specifics>

<deferred>
## Deferred Ideas

- Devcontainer compatibility with read-only rootfs — needs VS Code extension path analysis, separate effort
- Custom seccomp profile tuned to agent workloads — v2 requirement

</deferred>

---

*Phase: 02-container-hardening*
*Context gathered: 2026-03-24*
