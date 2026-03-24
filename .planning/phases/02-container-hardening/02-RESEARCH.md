# Phase 2: Container Hardening - Research

**Researched:** 2026-03-24
**Domain:** Docker Compose security primitives — read-only rootfs, capability dropping, seccomp, resource limits
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- `read_only: true` on the agent-sandbox service in docker-compose.yml
- Writable tmpfs mounts: `/tmp` (256MB, noexec), `/run` (64MB)
- Named volumes (claude-state, command-history, mise-state, cargo-state, local-bin-state) are not affected by read_only — they remain writable
- Workspace bind mount `.:/workspace` remains writable
- `cap_drop: [ALL]` on agent-sandbox service
- No capabilities added back (proxy approach eliminated need for NET_ADMIN/NET_RAW in Phase 1)
- `security_opt: [no-new-privileges:true]`
- Use Docker's default seccomp profile — do NOT specify a custom one
- Resource limits with env var defaults: `${SANDBOX_CPUS:-2}`, `${SANDBOX_MEMORY:-4g}`, `${SANDBOX_PIDS:-512}`
- `deploy.resources.limits` for cpus and memory; `pids_limit` for PID limit
- No reservation (limits only)
- Proxy container does NOT get hardened in this phase
- Devcontainer compatibility with read-only rootfs is deferred (out of scope for Phase 2)

### Claude's Discretion

- Exact tmpfs size limits (256MB for /tmp is a starting point)
- Whether to add additional tmpfs mounts discovered during testing (e.g., /var/tmp)
- Exact PID limit value (512 is generous; 256 may suffice)

### Deferred Ideas (OUT OF SCOPE)

- Devcontainer compatibility with read-only rootfs — needs VS Code extension path analysis, separate effort
- Custom seccomp profile tuned to agent workloads — v2 requirement (HARD-05)

</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| HARD-01 | Sandbox containers run with read-only rootfs and writable tmpfs for /tmp | Compose `read_only: true` + long-form volume syntax for tmpfs with size; named volumes already writable |
| HARD-02 | Sandbox containers run with --cap-drop=ALL and --security-opt=no-new-privileges | Compose `cap_drop: [ALL]` + `security_opt: [no-new-privileges:true]`; both confirmed valid in official docs |
| HARD-03 | Sandbox containers use Docker's default seccomp profile (custom tuning deferred) | Default seccomp is active when no `seccomp=unconfined` is set; confirmed blocks ~44 syscalls |
| HARD-04 | Resource limits (CPU, memory, PID) are configurable per sandbox run | Compose `deploy.resources.limits` + `pids_limit` with `${VAR:-default}` substitution; TZ pattern already exists |

</phase_requirements>

---

## Summary

This phase adds four Docker Compose security directives to the `agent-sandbox` service: read-only rootfs with targeted tmpfs writable mounts, all-capabilities-dropped with no-new-privileges, default seccomp enforcement (implicit — no action needed), and configurable resource limits via environment variables.

All changes are confined to `docker-compose.yml` with a possible small adjustment to `images/base/Dockerfile` or `entrypoint.sh` if read-only rootfs reveals writable path requirements at startup. The proxy service is explicitly excluded from this phase.

Phase 1 already removed NET_ADMIN and NET_RAW from the sandbox by eliminating `cap_add` entirely — so `cap_drop: [ALL]` is the natural completion of that work, not a regression risk.

**Primary recommendation:** Add all four hardening directives to the `agent-sandbox` service block in docker-compose.yml. Add a smoke test script that verifies each HARD-xx requirement using `docker inspect` and live container checks. The entrypoint needs validation that it runs cleanly under read-only rootfs — the `gosu` uid/gid adjustment writes nothing to the rootfs, so it should work without modification, but this must be verified by running the container.

---

## Standard Stack

### Core

| Mechanism | Compose Key | Purpose | Source |
|-----------|-------------|---------|--------|
| Read-only rootfs | `read_only: true` | Prevent container from writing to image layers at runtime | Docker official docs |
| tmpfs writable mounts | `volumes` long-form with `type: tmpfs` | Provide writable scratch space without persistent storage | Docker Compose spec |
| Capability drop | `cap_drop: [ALL]` | Remove all Linux capabilities from container process | Docker Compose spec |
| No privilege escalation | `security_opt: [no-new-privileges:true]` | Prevent setuid/setgid binaries from elevating privileges | Docker CLI reference |
| Default seccomp | (implicit — no override) | Block ~44 dangerous syscalls; active unless explicitly disabled | Docker Engine security docs |
| CPU limit | `deploy.resources.limits.cpus` | Cap CPU shares; env var override supported | Docker Compose spec |
| Memory limit | `deploy.resources.limits.memory` | Hard memory cap; OOM kill if exceeded | Docker Compose spec |
| PID limit | `pids_limit` | Prevent fork bombs; env var override supported | Docker Compose spec |

### Supporting

| Pattern | Purpose | When to Use |
|---------|---------|-------------|
| `${VAR:-default}` in compose | Env var override with fallback | Already used for TZ; extend for resource limits |
| Long-form volume syntax (`type: tmpfs`) | Enables `tmpfs.size` configuration | Needed to set 256MB/64MB size caps on tmpfs mounts |
| Short-form `tmpfs:` key | Simpler syntax but no size option | Use only for mounts where size doesn't matter |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Long-form volume syntax for tmpfs | Short-form `tmpfs:` key | Short form does not support size; long form required to enforce 256MB limit |
| `deploy.resources.limits` for CPU/memory | Top-level `mem_limit`/`cpus` | Top-level keys are deprecated in Compose v2; `deploy.resources` is the current standard |
| `no-new-privileges:true` (colon) | `no-new-privileges=true` (equals) | Both are accepted; colon is idiomatic in YAML lists; equals matches Docker CLI reference. Either works. |

**Installation:** No new packages needed. All hardening is Compose configuration only.

---

## Architecture Patterns

### Recommended docker-compose.yml Changes

Add these keys to the `agent-sandbox` service block (no other service is modified):

```yaml
# Source: Docker Compose spec - https://docs.docker.com/reference/compose-file/services/
agent-sandbox:
  # ... existing keys ...
  read_only: true
  cap_drop:
    - ALL
  security_opt:
    - no-new-privileges:true
  pids_limit: ${SANDBOX_PIDS:-512}
  deploy:
    resources:
      limits:
        cpus: '${SANDBOX_CPUS:-2}'
        memory: ${SANDBOX_MEMORY:-4g}
  volumes:
    # ... existing named volumes and workspace bind mount ...
    # Add writable tmpfs mounts for read-only rootfs compatibility:
    - type: tmpfs
      target: /tmp
      tmpfs:
        size: 268435456   # 256MB in bytes
    - type: tmpfs
      target: /run
      tmpfs:
        size: 67108864    # 64MB in bytes
```

**Important:** The long-form `volumes` syntax with `type: tmpfs` must be used to specify `tmpfs.size`. The short-form `tmpfs:` key at service level does not support `size`.

### Pattern 1: tmpfs size in bytes

Docker Compose `tmpfs.size` requires an integer (bytes) or a string with byte unit notation. The official documentation states: "The size for the tmpfs mount in bytes (either numeric or as bytes unit)."

```yaml
# Source: Docker Compose spec volumes reference
- type: tmpfs
  target: /tmp
  tmpfs:
    size: 268435456  # 256 * 1024 * 1024 = 256MB
```

String notation (e.g., `"256m"`) may also work depending on Compose version, but numeric bytes is unambiguous.

### Pattern 2: Resource limits with env var override

The existing `${TZ:-America/Los_Angeles}` pattern extends directly to resource limits. Users export `SANDBOX_CPUS=4` before `docker compose up` to override.

```yaml
# Source: existing docker-compose.yml TZ pattern, extended
deploy:
  resources:
    limits:
      cpus: '${SANDBOX_CPUS:-2}'
      memory: ${SANDBOX_MEMORY:-4g}
pids_limit: ${SANDBOX_PIDS:-512}
```

Note: `cpus` value should be a string in Compose to avoid YAML float parsing issues (e.g., `'2'` not `2`).

### Pattern 3: Default seccomp (no action required)

Docker's default seccomp profile is active on any container that does not explicitly set `seccomp=unconfined`. HARD-03 is satisfied by absence of a security_opt override — no new configuration is needed.

To verify it is active:
```bash
docker inspect agent-sandbox | python3 -c "
import json, sys
c = json.load(sys.stdin)
sec = c[0]['HostConfig']['SecurityOpt']
print('SecurityOpt:', sec)
# Should NOT contain 'seccomp=unconfined'
"
```

### Writable Paths Under read_only: true

Named volumes and bind mounts are unaffected by `read_only: true` — they remain fully writable. The table below documents every writable path:

| Path | Mechanism | Writable? | Notes |
|------|-----------|-----------|-------|
| `/workspace` | bind mount `.:/workspace` | Yes | Agent work directory |
| `/home/dev/.claude` | named volume `claude-state` | Yes | Claude credentials |
| `/commandhistory` | named volume `command-history` | Yes | Shell history |
| `/home/dev/.mise` | named volume `mise-state` | Yes | mise cache/config |
| `/home/dev/.cargo` | named volume `cargo-state` | Yes | Cargo cache |
| `/home/dev/.local/bin` | named volume `local-bin-state` | Yes | Local binaries |
| `/tmp` | tmpfs (new) | Yes | 256MB scratch space |
| `/run` | tmpfs (new) | Yes | 64MB runtime state |
| Everything else | image layer (read_only) | No | Protected |

### Entrypoint Compatibility with read_only: true

The current `entrypoint.sh` runs as root and performs:
1. `stat` on `/workspace` — reads only
2. `groupmod` / `usermod` — modifies `/etc/group` and `/etc/passwd` (rootfs files)
3. `chown` on `/home/dev` and `/commandhistory` — changes metadata on named volumes
4. `exec gosu` — drops to dev user

**Risk:** Steps 2 (`groupmod`/`usermod`) modify `/etc/passwd` and `/etc/group`, which are rootfs files. Under `read_only: true` these writes will fail.

**Mitigation:** The Dockerfile already creates user `dev` with UID/GID 500. If the host workspace is owned by UID 500, `usermod` is skipped (the `if [ "$HOST_UID" != "$(id -u "$APP_USER")" ]` guard). For non-500 UIDs, `usermod`/`groupmod` will fail.

**Resolution options:**
1. Add `/etc/passwd` and `/etc/group` as tmpfs overlays (copy-on-write via tmpfs bind mounts)
2. Use a pre-created shadow copy approach: copy `/etc/passwd` to tmpfs and re-mount
3. Remove UID/GID adjustment from entrypoint (accept fixed UID 500 for Phase 2; revisit in Phase 3 DEVENV-06)

Option 3 is simplest for Phase 2 since DEVENV-06 (UID/GID adjustment) is a Phase 3 concern. However the entrypoint's `chown` calls against named volumes still work since those volumes are writable.

**Practical approach:** Test the container with `read_only: true` against a real workspace and observe which writes fail. The `groupmod`/`usermod` calls are the primary risk. If they fail, the tmpfs overlay for `/etc` approach is the lowest-friction fix.

### Anti-Patterns to Avoid

- **Specifying `security_opt: [seccomp=builtin]` explicitly:** Redundant — default seccomp is already active. The CONTEXT.md decision is correct: don't specify it, just don't disable it.
- **Using short-form `tmpfs:` key for sized mounts:** Short form at service level (`tmpfs: [/tmp, /run]`) does not support size limits. Use long-form volume syntax.
- **Hardcoding resource limits:** Use `${VAR:-default}` so users can tune without editing the compose file.
- **Adding `cap_add:` with any capability:** The decision is zero capabilities. Verify no capabilities leak back in via other service keys.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Syscall filtering | Custom seccomp profile | Docker default seccomp | Default blocks the dangerous 44; custom tuning requires syscall tracing and audit — deferred to v2 (HARD-05) |
| Memory enforcement | Application-level memory checks | `deploy.resources.limits.memory` + OOM killer | Kernel-enforced; no application cooperation needed |
| PID fork bomb protection | Application-level process counting | `pids_limit` | Kernel cgroup enforced; catches all forking including shell scripts |
| Privilege escalation prevention | Application code avoiding setuid | `no-new-privileges:true` + `cap_drop: ALL` | Enforced at kernel level regardless of binary permissions |

**Key insight:** All Phase 2 controls are kernel/runtime enforced. There is nothing to write beyond the docker-compose.yml directives and the smoke test script.

---

## Common Pitfalls

### Pitfall 1: entrypoint.sh fails under read-only rootfs

**What goes wrong:** `groupmod`/`usermod` in `entrypoint.sh` writes to `/etc/passwd` and `/etc/group`. With `read_only: true`, these writes fail with "Read-only file system" and the container exits at startup.

**Why it happens:** The UID/GID adjustment logic was designed before read-only rootfs was a requirement. `/etc` is part of the image layer, not a volume.

**How to avoid:** Either (a) test the container and confirm UID 500 matches the workspace owner so the adjustment is skipped, (b) add `/etc` as a tmpfs overlay, or (c) defer UID/GID adjustment to Phase 3 as part of DEVENV-06. Option (c) is the lowest-risk for Phase 2.

**Warning signs:** Container starts and immediately exits; `docker logs agent-sandbox` shows "Read-only file system" errors from groupmod/usermod.

### Pitfall 2: Named volumes not in the volumes list after adding long-form tmpfs entries

**What goes wrong:** Compose requires all volumes in the `volumes:` key of a service to be listed. When adding long-form `type: tmpfs` entries, they must be appended to the existing `volumes:` list, not replace it. Accidentally overwriting the key removes named volume mounts.

**How to avoid:** Carefully merge the new tmpfs entries into the existing `volumes:` list. Named volumes and bind mounts are short-form and work alongside long-form entries.

**Warning signs:** `claude-state`, `mise-state`, etc. are empty on container start; Claude credentials are missing.

### Pitfall 3: `deploy.resources` ignored in non-Swarm standalone Compose

**What goes wrong:** In older versions of Docker Compose (standalone `docker-compose` v1), `deploy.resources` was only applied when deploying to a Swarm. Standalone `docker compose up` ignored it.

**Why it happens:** Legacy compose v1 behavior. Compose v2 (built into Docker CLI as `docker compose`) applies resource limits in standalone mode.

**How to avoid:** Use `docker compose` (v2, space-separated) not `docker-compose` (v1, hyphen). Verify limits are applied: `docker inspect agent-sandbox | python3 -c "import json,sys; c=json.load(sys.stdin)[0]; print(c['HostConfig']['Memory'], c['HostConfig']['NanoCpus'])"` — non-zero values confirm limits were applied.

**Warning signs:** Memory/CPU limits appear in compose file but `docker inspect` shows `"Memory": 0` and `"NanoCpus": 0`.

### Pitfall 4: Proxy config writability from sandbox (existing pitfall, verify in this phase)

**What goes wrong:** Per PITFALLS.md Pitfall 7 — if the proxy config is accidentally mounted writable into the sandbox, an agent can modify the allowlist. The current compose file mounts `./config/allowlist.txt:/etc/squid/allowlist.txt:ro` only in the proxy service, not in sandbox. This is correct. Adding new volume entries to sandbox must not accidentally include proxy config.

**How to avoid:** After Phase 2 changes, audit `docker inspect agent-sandbox` to confirm no proxy config paths appear in mounts.

### Pitfall 5: `pids_limit` interacts with `deploy.replicas`

**What goes wrong:** If `pids_limit` and `deploy.resources` are both set, and `deploy` also sets `replicas`, the behavior can be confusing. For a single sandbox there is no issue — only one container instance.

**How to avoid:** Do not set `deploy.replicas` unless multiple simultaneous sandboxes are needed (that is Phase 3/ORCH-03 scope). Keep `deploy:` scoped to `resources:` only in this phase.

---

## Code Examples

### Complete agent-sandbox hardening block

```yaml
# Source: Docker Compose spec https://docs.docker.com/reference/compose-file/services/
agent-sandbox:
  image: agent-sandbox-claude:local
  container_name: agent-sandbox
  networks:
    - sandbox-internal
  depends_on:
    proxy:
      condition: service_healthy
  read_only: true
  cap_drop:
    - ALL
  security_opt:
    - no-new-privileges:true
  pids_limit: ${SANDBOX_PIDS:-512}
  deploy:
    resources:
      limits:
        cpus: '${SANDBOX_CPUS:-2}'
        memory: ${SANDBOX_MEMORY:-4g}
  volumes:
    - .:/workspace
    - claude-state:/home/dev/.claude
    - command-history:/commandhistory
    - mise-state:/home/dev/.mise
    - cargo-state:/home/dev/.cargo
    - local-bin-state:/home/dev/.local/bin
    - type: tmpfs
      target: /tmp
      tmpfs:
        size: 268435456    # 256MB
    - type: tmpfs
      target: /run
      tmpfs:
        size: 67108864     # 64MB
  working_dir: /workspace
  stdin_open: true
  tty: true
  environment:
    - TZ=${TZ:-America/Los_Angeles}
    # ... rest of environment unchanged ...
```

### Verification: Inspect applied security settings

```bash
# Verify read-only rootfs
docker inspect agent-sandbox | python3 -c "
import json, sys
c = json.load(sys.stdin)[0]
print('ReadonlyRootfs:', c['HostConfig']['ReadonlyRootfs'])
"

# Verify capabilities dropped (CapAdd should be null/empty, CapDrop should list ALL)
docker inspect agent-sandbox | python3 -c "
import json, sys
c = json.load(sys.stdin)[0]
print('CapAdd:', c['HostConfig']['CapAdd'])
print('CapDrop:', c['HostConfig']['CapDrop'])
"

# Verify resource limits applied
docker inspect agent-sandbox | python3 -c "
import json, sys
c = json.load(sys.stdin)[0]
print('Memory:', c['HostConfig']['Memory'])
print('NanoCpus:', c['HostConfig']['NanoCpus'])
print('PidsLimit:', c['HostConfig']['PidsLimit'])
"

# Verify default seccomp is active (not unconfined)
docker inspect agent-sandbox | python3 -c "
import json, sys
c = json.load(sys.stdin)[0]
opts = c['HostConfig']['SecurityOpt'] or []
print('SecurityOpt:', opts)
unconfined = any('seccomp=unconfined' in o for o in opts)
print('Seccomp unconfined (should be False):', unconfined)
"
```

### Verify writable paths work inside container

```bash
# Test /tmp is writable
docker compose exec -T agent-sandbox bash -c "touch /tmp/test-write && rm /tmp/test-write && echo PASS || echo FAIL"

# Test rootfs is read-only
docker compose exec -T agent-sandbox bash -c "touch /test-write 2>&1 | grep -q 'Read-only' && echo PASS || echo FAIL"

# Test workspace is writable
docker compose exec -T agent-sandbox bash -c "touch /workspace/.hardening-test && rm /workspace/.hardening-test && echo PASS || echo FAIL"
```

---

## State of the Art

| Old Approach | Current Approach | Impact |
|--------------|------------------|--------|
| Per-container iptables + NET_ADMIN | Proxy-based egress + `cap_drop: ALL` | No capability required; Phase 1 completed this |
| Manual `docker run` flags | Compose service-level directives | Reproducible, version-controlled configuration |
| Top-level `mem_limit`/`cpus` keys | `deploy.resources.limits` | Compose v2 standard; v1 keys deprecated |
| Short-form `tmpfs:` | Long-form `volumes` with `type: tmpfs` | Enables size enforcement on tmpfs mounts |

**Deprecated/outdated:**
- `mem_limit`, `memswap_limit`, `cpu_shares` as top-level Compose keys: removed in Compose v2 spec; use `deploy.resources`.
- `--security-opt seccomp:profile.json` (colon separator): equals sign (`=`) is the current CLI standard, but both are accepted by the daemon.

---

## Open Questions

1. **entrypoint.sh UID/GID adjustment under read-only rootfs**
   - What we know: `groupmod`/`usermod` write to `/etc/passwd` and `/etc/group` which are in the read-only image layer
   - What's unclear: Whether the host workspace UID will reliably match 500 in practice; if not, which mitigation to apply
   - Recommendation: Start container with `read_only: true` and observe. If it fails, the simplest fix is to add a tmpfs mount for `/etc` (shadow the entire directory). Alternatively disable UID adjustment for Phase 2 — DEVENV-06 in Phase 3 owns this properly.

2. **Whether `/var/tmp` needs a tmpfs mount**
   - What we know: Some tools (apt, dpkg) use `/var/tmp`; agents in Phase 2 don't install packages so this may not matter
   - What's unclear: Whether any startup scripts or tool configs write to `/var/tmp` at container init
   - Recommendation: Test the container with `read_only: true` and check `docker logs` for `/var/tmp` write errors. Add tmpfs if needed — Claude's Discretion per CONTEXT.md.

3. **tmpfs size format: integer bytes vs string notation**
   - What we know: Docker Compose docs state "bytes (either numeric or as bytes unit)" for `tmpfs.size`
   - What's unclear: Whether string notation like `"256m"` works consistently across Compose versions
   - Recommendation: Use integer bytes (268435456) for guaranteed compatibility; document the human-readable equivalent in a comment.

---

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | bash (existing `tests/smoke-proxy.sh` pattern) |
| Config file | none — standalone bash script |
| Quick run command | `bash tests/smoke-hardening.sh` |
| Full suite command | `bash tests/smoke-proxy.sh && bash tests/smoke-hardening.sh` |

### Phase Requirements to Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| HARD-01 | rootfs is read-only; /tmp is writable tmpfs | smoke | `bash tests/smoke-hardening.sh` (HARD-01 checks) | Wave 0 |
| HARD-02 | cap_drop=ALL applied; no-new-privileges active | smoke | `bash tests/smoke-hardening.sh` (HARD-02 checks) | Wave 0 |
| HARD-03 | default seccomp active (not unconfined) | smoke | `bash tests/smoke-hardening.sh` (HARD-03 check) | Wave 0 |
| HARD-04 | resource limits applied; env var override works | smoke | `bash tests/smoke-hardening.sh` (HARD-04 checks) | Wave 0 |

### Sampling Rate

- **Per task commit:** `bash tests/smoke-hardening.sh`
- **Per wave merge:** `bash tests/smoke-proxy.sh && bash tests/smoke-hardening.sh`
- **Phase gate:** Full suite green (proxy + hardening) before `/gsd:verify-work`

### Wave 0 Gaps

- [ ] `tests/smoke-hardening.sh` — covers HARD-01 through HARD-04 using the same `check`/`check_fail` pattern from `tests/smoke-proxy.sh`

*(The existing `tests/smoke-proxy.sh` covers proxy requirements; the hardening test script is a new file following the same pattern.)*

**Suggested `tests/smoke-hardening.sh` structure:**

```bash
#!/usr/bin/env bash
set -euo pipefail
# check/check_fail helpers (same as smoke-proxy.sh)

# HARD-01: Read-only rootfs — write to rootfs fails
check_fail HARD-01 "Rootfs is read-only (write to / fails)" \
    docker compose exec -T agent-sandbox bash -c "touch /hardening-test-$$"

# HARD-01: /tmp is writable
check HARD-01 "/tmp is writable" \
    docker compose exec -T agent-sandbox bash -c "touch /tmp/hardening-test-$$ && rm /tmp/hardening-test-$$"

# HARD-02: cap_drop=ALL applied (CapAdd is null/empty)
check HARD-02 "No capabilities added (CapAdd is null)" \
    bash -c "docker inspect agent-sandbox | python3 -c \"import json,sys; c=json.load(sys.stdin); exit(0 if c[0]['HostConfig']['CapAdd'] is None else 1)\""

# HARD-02: no-new-privileges in SecurityOpt
check HARD-02 "no-new-privileges is set" \
    bash -c "docker inspect agent-sandbox | python3 -c \"import json,sys; c=json.load(sys.stdin); opts=c[0]['HostConfig']['SecurityOpt'] or []; exit(0 if any('no-new-priv' in o for o in opts) else 1)\""

# HARD-03: default seccomp active (not unconfined)
check HARD-03 "Default seccomp active (not unconfined)" \
    bash -c "docker inspect agent-sandbox | python3 -c \"import json,sys; c=json.load(sys.stdin); opts=c[0]['HostConfig']['SecurityOpt'] or []; exit(1 if any('seccomp=unconfined' in o for o in opts) else 0)\""

# HARD-04: Memory limit applied
check HARD-04 "Memory limit is non-zero" \
    bash -c "docker inspect agent-sandbox | python3 -c \"import json,sys; c=json.load(sys.stdin); exit(0 if c[0]['HostConfig']['Memory'] > 0 else 1)\""

# HARD-04: CPU limit applied
check HARD-04 "CPU limit is non-zero" \
    bash -c "docker inspect agent-sandbox | python3 -c \"import json,sys; c=json.load(sys.stdin); exit(0 if c[0]['HostConfig']['NanoCpus'] > 0 else 1)\""

# HARD-04: PID limit applied
check HARD-04 "PID limit is non-zero" \
    bash -c "docker inspect agent-sandbox | python3 -c \"import json,sys; c=json.load(sys.stdin); exit(0 if c[0]['HostConfig']['PidsLimit'] > 0 else 1)\""
```

---

## Sources

### Primary (HIGH confidence)

- Docker Compose spec — `read_only`, `cap_drop`, `security_opt`, `pids_limit`, `deploy.resources`, `tmpfs` syntax: https://docs.docker.com/reference/compose-file/services/
- Docker Engine security — seccomp default profile, ~44 blocked syscalls: https://docs.docker.com/engine/security/seccomp/
- Docker CLI reference — `--security-opt` supported values including `no-new-privileges=true`: https://docs.docker.com/reference/cli/docker/container/run/#security-opt
- Existing codebase: `docker-compose.yml`, `images/base/Dockerfile`, `images/base/entrypoint.sh`, `tests/smoke-proxy.sh` — ground truth for current state and test patterns

### Secondary (MEDIUM confidence)

- `.planning/research/STACK.md` — Container Hardening Layer table documenting all controls
- `.planning/research/PITFALLS.md` — Pitfall 7 (proxy config writability) and "Looks Done But Isn't" checklist for read-only rootfs
- `docs/research.md` — Independent research synthesis confirming the standard pattern: `--read-only --tmpfs /tmp --cap-drop=ALL --security-opt=no-new-privileges`

### Tertiary (LOW confidence)

- None — all key claims are verified from official Docker documentation

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all directives verified in official Docker Compose spec and CLI reference
- Architecture patterns: HIGH — compose syntax verified; entrypoint compatibility is the one area requiring live testing
- Pitfalls: HIGH — read-only rootfs entrypoint interaction is well-known; verified against existing codebase code paths

**Research date:** 2026-03-24
**Valid until:** 2026-09-24 (Docker Compose spec is stable; no breaking changes expected)
