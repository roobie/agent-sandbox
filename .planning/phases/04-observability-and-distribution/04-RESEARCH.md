# Phase 04: Observability and Distribution - Research

**Researched:** 2026-03-24
**Domain:** Docker observability (logs, diff), GitHub Actions CI/CD (GHCR publishing), artifact cleanup
**Confidence:** HIGH

## Summary

Phase 4 is predominantly an integration and wiring phase — the hard work (Squid logging, hardened sandbox, mise task infrastructure) is complete from prior phases. The six requirements decompose into four concrete work items: (1) add two mise log tasks and enhance `sandbox:stop` with diff output, (2) add a `build-proxy` job to the CI workflow, (3) verify DIST-02 is satisfied (it is — no work needed), and (4) audit Docker artifacts for orphans.

The main technical finding is that `docker diff` uses `A/C/D` (Added/Changed/Deleted), NOT `A/M/D` — the CONTEXT.md says "modified/deleted" but the Docker CLI uses `C` for changed. This affects the diff output format in `sandbox:stop`. Policy.json files cited in CONTEXT.md as candidates for cleanup do not exist on disk — prior phases already removed them. The devcontainer directory also does not exist. The cleanup scope is narrower than anticipated; the main remaining candidate is verifying no stale references to policy files remain anywhere.

**Primary recommendation:** Wire existing capabilities together. `docker logs` works, Squid logs to stdout already, CI already exists — extend CI with one job, add two tasks, enhance stop task. Invest effort in making the diff output readable and the CI extension correct.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Stdout/stderr capture (OBS-01)**
- Docker already captures stdout/stderr by default — `docker logs <container>` works out of the box
- No additional work needed for basic capture
- Add `sandbox:logs` mise task for convenient access: `docker logs agent-sandbox-${NAME}`
- Add `proxy:logs` mise task: `docker logs agent-sandbox-proxy`

**Filesystem diff logging (OBS-02)**
- Enhance `sandbox:stop` mise task to capture diffs BEFORE stopping the container
- Run `docker diff agent-sandbox-${NAME}` to show container filesystem changes (files added/modified/deleted outside volumes)
- Run `git -C ${WORKSPACE} diff --stat` to show workspace changes made by the agent
- Output both diffs to stdout so the user sees them in the terminal at stop time
- No separate log file or volume needed — terminal output is sufficient for v1
- Format: clear section headers ("=== Container filesystem changes ===" and "=== Workspace changes ===")

**Squid access log auditing (OBS-03)**
- Already working: Squid logs to stdout via `access_log stdio:/dev/stdout` (configured in Phase 1)
- Accessible via `docker logs agent-sandbox-proxy`
- Add `proxy:logs` task with optional `--follow` flag for live tailing
- No additional Squid configuration changes needed

**CI/CD image publishing (DIST-01)**
- Existing `.github/workflows/build-images.yml` already publishes base and claude images to GHCR
- Add proxy image publishing to the same workflow (third job: `build-proxy`)
- Proxy has no dependencies on base/claude — can build in parallel with base
- Keep existing tag strategy: `latest` on default branch, `sha-` prefix for commit SHAs, semver on releases
- Keep existing multi-platform build: linux/amd64, linux/arm64
- Verify Claude build-arg `BASE_IMAGE` correctly references the GHCR-published base image digest

**Local build via mise task (DIST-02)**
- Already working: `mise run image:build` runs `python3 images/build.py all`
- No changes needed — DIST-02 is already satisfied

**Orphaned artifact cleanup (DIST-03)**
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

### Deferred Ideas (OUT OF SCOPE)
- Structured audit log in JSON format (OBS-04 — v2 requirement)
- Real-time filesystem change monitoring via inotifywait (OBS-05 — v2 requirement)
- Copilot agent image publishing in CI — evaluate when copilot agent is mature enough
- Log rotation or aggregation — overkill for local dev tool
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| OBS-01 | Agent stdout/stderr captured via Docker logs | `docker logs <container>` works out of the box; add `sandbox:logs` and `proxy:logs` mise tasks for UX convenience |
| OBS-02 | Filesystem diff logging: docker diff for container changes + git diff for workspace changes, captured at sandbox stop | `docker diff` outputs A/C/D prefixed lines; `git diff --stat` shows file-level summary; both invoked in enhanced `sandbox:stop` before docker stop |
| OBS-03 | Squid access logs available for auditing which domains agents accessed | Squid already logs to stdout; `docker logs agent-sandbox-proxy` works now; `proxy:logs` task with `--follow` flag enables live tailing |
| DIST-01 | Container images published to GHCR via CI/CD pipeline | Extend existing workflow with `build-proxy` job; proxy can run parallel with base (no dependency); use same action versions and tag strategy as existing jobs |
| DIST-02 | Images also buildable from source via mise task (`mise run image:build`) | Already satisfied: `mise run image:build` calls `python3 images/build.py all` which calls `build_proxy()`, `build_base()`, `build_claude()` — no changes needed |
| DIST-03 | Existing Docker artifacts evaluated and either reused or replaced (not left orphaned) | Finding: policy.json files and init-firewall.py do not exist on disk (removed in prior phases); devcontainer directory does not exist; cleanup scope is a verification pass + removing any stale references in comments/README |
</phase_requirements>

## Standard Stack

### Core
| Library/Tool | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| `docker logs` | CLI (Docker 25+) | Capture container stdout/stderr | Built-in; no additional tooling required |
| `docker diff` | CLI (Docker 25+) | Show container filesystem changes since image start | Built-in; outputs A/C/D prefix per changed path |
| `git diff --stat` | git 2.x | Summarize workspace file changes | Already available in sandbox context; --stat gives file-level summary |
| `docker/build-push-action` | v6 (current: v6.18.0) | Build and push multi-platform images in CI | Official Docker action; existing workflow uses v5, v6 is current major |
| `docker/metadata-action` | v5 | Extract tags/labels from git ref | Official Docker action; already used in existing workflow |
| `docker/login-action` | v3 | Authenticate to GHCR | Official Docker action; already used in existing workflow |
| `docker/setup-buildx-action` | v3 | Set up Docker Buildx for multi-platform | Official Docker action; already used in existing workflow |
| `docker/setup-qemu-action` | v3 | QEMU emulation for arm64 cross-build | Official Docker action; already used in existing workflow |
| `actions/checkout` | v4 | Checkout repository | Standard; already used in existing workflow |

### Supporting
| Tool | Purpose | When to Use |
|------|---------|-------------|
| `docker logs --follow` | Live log tailing | `proxy:logs --follow` flag implementation |
| `docker logs --tail N` | Show last N lines | Useful default for `sandbox:logs` to avoid dumping all history |
| `$GITHUB_STEP_SUMMARY` | CI job summary markdown | Already used in existing `summary` job — extend for proxy image digest |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `docker diff` (built-in) | `inotifywait` real-time monitoring | Real-time monitoring deferred to OBS-05 v2; diff at stop time is sufficient for v1 |
| `git diff --stat` | `git diff --name-only` | `--stat` gives line counts which is more informative; both are fine |
| Parallel proxy CI job | Sequential after base | Parallel is faster and correct since proxy has no dependency on base |

**Installation:** No new dependencies. All tools already available.

## Architecture Patterns

### Recommended Project Structure

No new directories. Changes are to existing files:
```
mise.toml                              # Add sandbox:logs, proxy:logs; enhance sandbox:stop
.github/workflows/build-images.yml    # Add build-proxy job; update summary job
```

### Pattern 1: mise Task with Optional Flag

Existing pattern from `sandbox:run` and `sandbox:stop` using usage blocks:

```toml
[tasks."proxy:logs"]
description = "Show Squid proxy logs"
usage = '''
flag "--follow -f" help="Follow log output (live tail)"
flag "--tail -n <lines>" help="Number of lines to show from end" default="100"
'''
run = """
FOLLOW="${usage_follow:-}"
TAIL="${usage_tail:-100}"
ARGS="--tail ${TAIL}"
if [ -n "$FOLLOW" ]; then
  ARGS="$ARGS --follow"
fi
docker logs $ARGS agent-sandbox-proxy
"""
```

### Pattern 2: sandbox:stop with Pre-stop Diff Capture

Insert diff commands before `docker stop`. The container must still be running for `docker diff` and `docker exec` to work:

```bash
# Emit diffs BEFORE stopping — container must be running for docker diff to work
NAME="${usage_name:-default}"

echo ""
echo "=== Container filesystem changes ==="
docker diff "agent-sandbox-${NAME}" || echo "(no changes or container not found)"

echo ""
echo "=== Workspace changes ==="
# docker diff shows container-layer changes; git diff shows workspace bind-mount changes
WORKSPACE=$(docker inspect "agent-sandbox-${NAME}" \
  --format '{{ range .Mounts }}{{ if eq .Destination "/workspace" }}{{ .Source }}{{ end }}{{ end }}' 2>/dev/null || echo "")
if [ -n "$WORKSPACE" ]; then
  git -C "$WORKSPACE" diff --stat 2>/dev/null || echo "(workspace is not a git repo or no changes)"
else
  echo "(could not determine workspace path)"
fi

echo ""
docker stop "agent-sandbox-${NAME}"
docker rm "agent-sandbox-${NAME}"
echo "Sandbox agent-sandbox-${NAME} stopped"
```

**Key insight:** Use `docker inspect` with a format template to dynamically extract the workspace path — avoids hardcoding the `--workspace` arg requirement in `sandbox:stop`.

### Pattern 3: CI Job for Proxy Image (Parallel with Base)

The proxy image has no dependency on base. It can run in parallel:

```yaml
build-proxy:
  runs-on: ubuntu-latest
  permissions:
    contents: read
    packages: write

  outputs:
    digest: ${{ steps.build.outputs.digest }}

  steps:
    - uses: actions/checkout@v4
    - uses: docker/setup-qemu-action@v3
    - uses: docker/setup-buildx-action@v3
    - name: Log in to GHCR
      uses: docker/login-action@v3
      with:
        registry: ${{ env.REGISTRY }}
        username: ${{ github.actor }}
        password: ${{ secrets.GITHUB_TOKEN }}
    - name: Extract metadata
      id: meta
      uses: docker/metadata-action@v5
      with:
        images: ${{ env.REGISTRY }}/${{ env.PROXY_IMAGE_NAME }}
        tags: |
          type=raw,value=latest,enable={{is_default_branch}}
          type=sha,prefix=sha-
          type=semver,pattern={{version}}
          type=semver,pattern={{major}}.{{minor}}
    - name: Build and push
      id: build
      uses: docker/build-push-action@v5
      with:
        context: ./images/proxy
        platforms: linux/amd64,linux/arm64
        push: true
        tags: ${{ steps.meta.outputs.tags }}
        labels: ${{ steps.meta.outputs.labels }}
        cache-from: type=gha
        cache-to: type=gha,mode=max
```

Add `PROXY_IMAGE_NAME` to workflow `env` block and add `build-proxy` to the `summary` job's `needs` array.

### Pattern 4: Workspace Path Extraction via docker inspect

The `sandbox:stop` task does not currently have access to the `--workspace` argument used at start time. Use `docker inspect` to recover it:

```bash
WORKSPACE=$(docker inspect "agent-sandbox-${NAME}" \
  --format '{{ range .Mounts }}{{ if eq .Destination "/workspace" }}{{ .Source }}{{ end }}{{ end }}' 2>/dev/null)
```

This Go template iterates `.Mounts` to find the source path for the `/workspace` destination.

### Anti-Patterns to Avoid

- **Running `docker diff` after `docker stop`:** The container must be running for diff to work. Always call diff BEFORE stop/rm.
- **Assuming `docker diff` uses "M" for modified:** Docker uses "C" (Changed), not "M". Section headers should say "A=Added, C=Changed, D=Deleted".
- **Making `build-proxy` depend on `build-base`:** The proxy image is independent (Squid-based, no project base). Dependency would add unnecessary latency.
- **Hardcoding the workspace path in `sandbox:stop`:** Users can specify custom workspace paths; recover it dynamically from container inspect.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Container filesystem diff | Custom inotify watcher | `docker diff` | Built into Docker; shows changes against the image layer since container start |
| Multi-platform CI builds | Manual docker buildx scripts | `docker/build-push-action` + `setup-qemu-action` | Handles QEMU setup, cache, digest output — the right tool for GitHub Actions |
| Log streaming | Custom log aggregation | `docker logs [--follow]` | Sufficient for local dev tool; structured logging is v2 (OBS-04) |
| Image tag strategy | Custom tagging scripts | `docker/metadata-action` | Handles latest/sha/semver from git refs automatically |

**Key insight:** Docker's built-in observability tools (logs, diff) are sufficient for v1. Don't introduce external monitoring agents.

## Common Pitfalls

### Pitfall 1: docker diff runs after container stop
**What goes wrong:** `docker diff` returns empty output or error if the container has been stopped/removed.
**Why it happens:** `docker diff` reads the container's writable layer, which is cleaned up on `docker rm`.
**How to avoid:** Always invoke `docker diff` before `docker stop` and `docker rm` in `sandbox:stop`.
**Warning signs:** Diff output is always empty; CI tests pass but diff section never shows changes.

### Pitfall 2: Workspace path not available in sandbox:stop
**What goes wrong:** `git diff --stat` fails or runs in the wrong directory because `--workspace` was not passed to stop.
**Why it happens:** `sandbox:stop` only takes `--name`; the workspace path was bound at `sandbox:run` time.
**How to avoid:** Use `docker inspect --format '{{ range .Mounts }}...'` to recover the source path of the `/workspace` mount.
**Warning signs:** "fatal: not a git repository" or diff runs against the wrong directory.

### Pitfall 3: GHA cache key collision between proxy and base builds
**What goes wrong:** Parallel `build-proxy` and `build-base` jobs share the GHA cache namespace and overwrite each other's cache entries.
**Why it happens:** `cache-to: type=gha,mode=max` without a cache key suffix means both jobs write to the same cache scope.
**How to avoid:** Add distinct cache key scopes — `cache-from: type=gha,scope=proxy` and `cache-to: type=gha,mode=max,scope=proxy`. Same for base job: `scope=base`. The existing workflow does not scope caches — this is worth fixing when adding the proxy job.
**Warning signs:** Build times don't improve despite caching; one image always rebuilds from scratch.

### Pitfall 4: docker diff shows noisy system paths
**What goes wrong:** `docker diff` output is cluttered with `/proc`, `/sys`, `/dev` entries or package manager cache entries.
**Why it happens:** Anything written in the container layer (even tmpfs overflow or package installs) shows up.
**How to avoid:** The output is informational — document this expected noise in the task description. For v1 the raw output is fine; filtering is a v2 concern.
**Warning signs:** Users complain about hundreds of diff lines; most are `/proc` or `/tmp` entries.

### Pitfall 5: Incorrect BASE_IMAGE reference in claude CI job
**What goes wrong:** Claude image builds against `latest` tag of base rather than the freshly built digest.
**Why it happens:** If `build-args: BASE_IMAGE=...@${{ needs.build-base.outputs.digest }}` is wrong, docker pulls latest instead.
**How to avoid:** The current workflow already uses digest pinning correctly. When adding the proxy job, verify the `build-claude` job's `needs.build-base.outputs.digest` reference is intact.
**Warning signs:** Claude image uses a stale base (can be verified by inspecting image layers).

## Code Examples

Verified patterns from official sources and existing codebase:

### docker diff output format
```
# Source: https://docs.docker.com/reference/cli/docker/container/diff/
# A = Added, C = Changed (NOT "M" for Modified), D = Deleted
$ docker diff agent-sandbox-default
C /workspace
A /workspace/output.txt
C /tmp
A /tmp/tmpfile123
```

### docker inspect to extract workspace mount source
```bash
# Source: docker inspect --format Go template syntax
WORKSPACE=$(docker inspect "agent-sandbox-${NAME}" \
  --format '{{ range .Mounts }}{{ if eq .Destination "/workspace" }}{{ .Source }}{{ end }}{{ end }}' 2>/dev/null)
```

### docker logs with flags
```bash
# Show last 100 lines
docker logs --tail 100 agent-sandbox-proxy

# Follow live output
docker logs --follow agent-sandbox-proxy

# Combined
docker logs --tail 50 --follow agent-sandbox-proxy
```

### GHA cache scoping for parallel jobs
```yaml
# Source: docker/build-push-action documentation
# In build-proxy job:
cache-from: type=gha,scope=proxy
cache-to: type=gha,mode=max,scope=proxy

# In build-base job:
cache-from: type=gha,scope=base
cache-to: type=gha,mode=max,scope=base
```

### mise usage block with boolean flag
```toml
# Source: existing mise.toml sandbox:run pattern
usage = '''
flag "--follow -f" help="Follow log output (live tail)"
'''
run = """
if [ -n "${usage_follow:-}" ]; then
  docker logs --follow agent-sandbox-proxy
else
  docker logs --tail 100 agent-sandbox-proxy
fi
"""
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| iptables-based egress + policy.json | Squid proxy + allowlist.txt | Phase 1 | policy.json files are now orphaned (already removed) |
| `docker/build-push-action@v5` | v6 is current major (v6.18.0) | 2024 | v5 still works; v6 adds build summary support with Docker Build Cloud |
| Sequential CI jobs (all depend on base) | Proxy can run parallel with base | This phase | Faster CI for independent images |

**Deprecated/outdated:**
- `images/*/policy.json`: iptables domain ACL policy files — already removed in prior phases (confirmed by filesystem scan)
- `images/base/init-firewall.py`: iptables init script — already removed in prior phases (MIG-01)
- `.devcontainer/` directory: does not exist in the repository — no cleanup needed

## Open Questions

1. **Whether to update build-push-action from v5 to v6**
   - What we know: Existing workflow uses v5; v6 is current major; v5 still functions correctly
   - What's unclear: Whether v6 brings any meaningful benefit for this workflow (build summary requires Docker Build Cloud)
   - Recommendation: Keep v5 for existing jobs; use v5 for new proxy job too — consistent versioning, no regressions. Upgrade all to v6 is a separate task if desired.

2. **Copilot agent image in CI (Claude's Discretion)**
   - What we know: `images/agents/copilot/Dockerfile` exists; `build.py` does not have a `build_copilot()` function; CONTEXT.md says "evaluate when copilot agent is mature enough"
   - What's unclear: Whether the copilot Dockerfile is functional
   - Recommendation: Skip copilot in CI for this phase — it is not referenced in any workflow or build.py; deferred per CONTEXT.md.

3. **Residual policy.json references in comments or README**
   - What we know: policy.json files are already gone from disk
   - What's unclear: Whether any README, comment, or config file still references them
   - Recommendation: The DIST-03 cleanup task should grep for "policy.json" and "init-firewall" across the repo to find stale references, then remove/update them.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | bash smoke tests (existing pattern) |
| Config file | none — standalone scripts |
| Quick run command | `bash tests/smoke-proxy.sh` (requires running containers) |
| Full suite command | `bash tests/smoke-proxy.sh && bash tests/smoke-hardening.sh` |

### Phase Requirements -> Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| OBS-01 | `sandbox:logs` outputs container stdout | smoke | `mise run sandbox:logs 2>&1 \| grep -q .` | ❌ Wave 0 |
| OBS-01 | `proxy:logs` outputs proxy stdout | smoke | `mise run proxy:logs 2>&1 \| grep -q .` | ❌ Wave 0 |
| OBS-02 | `sandbox:stop` emits container diff section | smoke | `mise run sandbox:stop 2>&1 \| grep -q "Container filesystem changes"` | ❌ Wave 0 |
| OBS-02 | `sandbox:stop` emits workspace diff section | smoke | `mise run sandbox:stop 2>&1 \| grep -q "Workspace changes"` | ❌ Wave 0 |
| OBS-03 | Squid access logs visible via docker logs | smoke | `docker logs agent-sandbox-proxy 2>&1 \| grep -q "TCP_"` | ❌ Wave 0 |
| DIST-01 | Proxy image name appears in CI workflow | static | `grep -q "agent-sandbox-proxy" .github/workflows/build-images.yml` | ❌ Wave 0 |
| DIST-02 | `mise run image:build` exits 0 | smoke | `mise run image:build` | ✅ (existing) |
| DIST-03 | No policy.json files exist | static | `! find images -name "policy.json" \| grep -q .` | ✅ (already clean) |

**Note:** OBS-01 through OBS-03 smoke tests require running containers (proxy + sandbox). They are integration tests, not unit tests. Run them after `mise run proxy:start && mise run sandbox:run`.

### Sampling Rate
- **Per task commit:** `grep -q "sandbox:logs\|proxy:logs" mise.toml` (static check, no containers needed)
- **Per wave merge:** Full smoke suite with live containers
- **Phase gate:** All static checks pass + manual smoke verification before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `tests/smoke-observability.sh` — covers OBS-01, OBS-02, OBS-03 verification with live containers
- [ ] Static CI check: `grep -q "build-proxy" .github/workflows/build-images.yml`

*(Existing `tests/smoke-proxy.sh` and `tests/smoke-hardening.sh` do not cover OBS or DIST requirements — new smoke file needed)*

## Sources

### Primary (HIGH confidence)
- Docker CLI docs (`docker diff`, `docker logs`, `docker inspect`) — verified A/C/D output format; `--format` Go template for mounts
- Existing codebase (`mise.toml`, `.github/workflows/build-images.yml`, `images/build.py`) — direct inspection of current state

### Secondary (MEDIUM confidence)
- WebSearch: docker/build-push-action v6.18.0 is current — verified via GitHub releases search
- WebSearch: docker diff uses A/C/D (not A/M/D) — confirmed by Docker docs reference in search results

### Tertiary (LOW confidence)
- GHA cache scoping recommendation — based on known GHA cache behavior; not verified against specific docker/build-push-action docs for this version

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all tools are existing or confirmed current versions
- Architecture: HIGH — patterns derived directly from existing codebase and Docker docs
- Pitfalls: HIGH for docker diff timing; MEDIUM for GHA cache scoping

**Research date:** 2026-03-24
**Valid until:** 2026-09-24 (stable tooling; GitHub Actions major versions move slowly)
