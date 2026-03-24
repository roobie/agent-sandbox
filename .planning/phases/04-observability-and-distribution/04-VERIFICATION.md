---
phase: 04-observability-and-distribution
verified: 2026-03-24T04:00:00Z
status: passed
score: 10/10 must-haves verified
re_verification: false
---

# Phase 4: Observability and Distribution Verification Report

**Phase Goal:** Sandbox activity is auditable via Docker logs and filesystem diffs; images are published to GHCR so users can pull without building locally; all existing Docker artifacts are either integrated or explicitly removed.
**Verified:** 2026-03-24
**Status:** passed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| #  | Truth | Status | Evidence |
|----|-------|--------|----------|
| 1  | User can view sandbox container logs via mise run sandbox:logs | VERIFIED | `mise.toml` line 111: `[tasks."sandbox:logs"]` with `docker logs $ARGS "agent-sandbox-${NAME}"` (line 126) |
| 2  | User can view proxy logs via mise run proxy:logs | VERIFIED | `mise.toml` line 23: `[tasks."proxy:logs"]` with `docker logs $ARGS agent-sandbox-proxy` (line 36) |
| 3  | User can follow proxy logs in real time via mise run proxy:logs --follow | VERIFIED | `proxy:logs` has `flag "--follow -f"` usage block; conditional `--follow` appended to `$ARGS` when set |
| 4  | User sees container filesystem changes printed at sandbox stop time | VERIFIED | `sandbox:stop` emits `=== Container filesystem changes ===` and runs `docker diff "${CONTAINER}"` (line 141) before `docker stop` |
| 5  | User sees workspace git diff summary printed at sandbox stop time | VERIFIED | `sandbox:stop` emits `=== Workspace changes ===`, runs `docker inspect` Go template to recover workspace path, then `git -C "$WORKSPACE" diff --stat` |
| 6  | Diff output appears BEFORE container is stopped and removed | VERIFIED | `docker diff` at line 141, `docker stop` at line 154 — diff precedes stop by 13 lines |
| 7  | CI workflow builds and pushes proxy image to GHCR on push to main | VERIFIED | `build-proxy` job in `.github/workflows/build-images.yml`; uses `PROXY_IMAGE_NAME` env var pointing to `ghcr.io/<owner>/agent-sandbox-proxy`; triggers on push to main |
| 8  | Proxy image builds in parallel with base image (no dependency between them) | VERIFIED | `build-proxy` job has no `needs:` field; runs independently of `build-base` |
| 9  | Claude image still builds after base (digest pinning intact) | VERIFIED | `build-claude` has `needs: build-base`; build-args line: `BASE_IMAGE=...@${{ needs.build-base.outputs.digest }}` (line 120); `cache-from: type=gha,scope=claude` |
| 10 | No production file outside .planning/ references init-firewall or policy.json as a current mechanism | VERIFIED | `tests/smoke-proxy.sh` references `init-firewall.py` only to assert it is ABSENT from container (MIG-01 regression test). `docs/plan/milestones/` contains historical milestone docs explicitly left in place per SUMMARY decision — not user-facing documentation describing a current mechanism. README, copilot Dockerfile, and all build files are clean. |

**Score:** 10/10 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `mise.toml` | sandbox:logs, proxy:logs tasks and enhanced sandbox:stop | VERIFIED | All three tasks present and substantive: sandbox:logs (lines 111-127), proxy:logs (lines 23-37), sandbox:stop (lines 129-157) |
| `.github/workflows/build-images.yml` | build-proxy job, scoped caches, updated summary | VERIFIED | build-proxy job (lines 127-177), all 6 cache scope entries present, summary needs all three jobs (line 181) |
| `README.md` | Updated project description reflecting proxy-based architecture | VERIFIED | Contains "Squid proxy", "SNI peek/splice", "allowlist", "mise run", "--cap-drop=ALL", "read-only rootfs"; no iptables/init-firewall/policy.json references |
| `images/agents/copilot/Dockerfile` | Copilot Dockerfile without stale policy.json reference | VERIFIED | No policy.json, no "Override base policy" comment, USER root and mise install block intact |
| `docs/policy/schema.md` | Deleted | VERIFIED | File does not exist; `docs/policy/` directory does not exist |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `mise.toml sandbox:logs` | `docker logs agent-sandbox-${NAME}` | shell command | WIRED | Line 126: `docker logs $ARGS "agent-sandbox-${NAME}"` |
| `mise.toml proxy:logs` | `docker logs agent-sandbox-proxy` | shell command | WIRED | Line 36: `docker logs $ARGS agent-sandbox-proxy` |
| `mise.toml sandbox:stop` | `docker diff agent-sandbox-${NAME}` | pre-stop shell command | WIRED | Line 141: `docker diff "${CONTAINER}"` before `docker stop` at line 154; verified by line number ordering |
| `.github/workflows/build-images.yml build-proxy` | `ghcr.io/*/agent-sandbox-proxy` | docker/build-push-action | WIRED | `images: ${{ env.REGISTRY }}/${{ env.PROXY_IMAGE_NAME }}`; context `./images/proxy`; platforms linux/amd64,linux/arm64 |
| `.github/workflows/build-images.yml build-claude` | `needs.build-base.outputs.digest` | build-args BASE_IMAGE | WIRED | Line 120: `BASE_IMAGE=${{ env.REGISTRY }}/${{ env.BASE_IMAGE_NAME }}@${{ needs.build-base.outputs.digest }}` |
| `README.md` | `config/allowlist.txt` | documentation reference | WIRED | Multiple references to allowlist.txt including format documentation and customization instructions |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| OBS-01 | 04-01-PLAN.md | Agent stdout/stderr captured via Docker logs | SATISFIED | `sandbox:logs` and `proxy:logs` tasks provide `docker logs` access with --follow and --tail flags |
| OBS-02 | 04-01-PLAN.md | Filesystem diff logging: docker diff + git diff at sandbox stop | SATISFIED | `sandbox:stop` captures `docker diff` and `git -C "$WORKSPACE" diff --stat` before `docker stop` |
| OBS-03 | 04-01-PLAN.md | Squid access logs available for auditing | SATISFIED | `proxy:logs` wraps `docker logs agent-sandbox-proxy`; README documents "Access logs stream to docker logs agent-sandbox-proxy for audit" |
| DIST-01 | 04-02-PLAN.md | Container images published to GHCR via CI/CD pipeline | SATISFIED | `build-proxy` job added; all three images (base, claude, proxy) now published via CI on push to main |
| DIST-02 | 04-02-PLAN.md | Images buildable from source via mise task | SATISFIED | `image:build` task exists (alias for `sandbox:build`, both present in mise.toml lines 39-45); confirmed pre-existing, no change needed |
| DIST-03 | 04-03-PLAN.md | Existing Docker artifacts evaluated — reused or replaced, not orphaned | SATISFIED | `docs/policy/schema.md` and `docs/policy/example.json` deleted; copilot Dockerfile COPY policy.json removed; README rewritten; historical docs/plan/milestones/ left in place intentionally (describe completed past work) |

All 6 required requirement IDs accounted for. No orphaned requirements identified for Phase 4 in REQUIREMENTS.md.

### Anti-Patterns Found

No anti-patterns detected in modified files:
- `mise.toml`: No TODO/FIXME/placeholder comments; all task implementations are substantive with real docker command wiring
- `.github/workflows/build-images.yml`: No placeholder steps; build-proxy job is fully implemented
- `README.md`: No placeholders; content accurately describes current architecture
- `images/agents/copilot/Dockerfile`: No stale references; builds without referencing non-existent files

### Human Verification Required

#### 1. sandbox:stop diff output at runtime

**Test:** Start a sandbox with `mise run sandbox:run --workspace /some/git/repo`, make a file change inside the container, then run `mise run sandbox:stop`
**Expected:** Terminal shows "=== Container filesystem changes ===" section with docker diff output (files added/changed/deleted), followed by "=== Workspace changes ===" with git diff --stat summary, then container stops
**Why human:** Requires running containers; static analysis confirms the code path is correct but cannot verify runtime output formatting

#### 2. proxy:logs --follow live tailing

**Test:** With proxy running (`mise run proxy:start`), run `mise run proxy:logs --follow`, then make an outbound HTTP request from a sandbox
**Expected:** New log lines appear in real time in the terminal
**Why human:** Requires live containers and network activity to verify streaming behavior

#### 3. CI workflow produces GHCR image pull URL

**Test:** Trigger a push to main branch; inspect GHA job summary
**Expected:** Summary table shows three image digests (base, claude, proxy); `docker pull ghcr.io/<owner>/agent-sandbox-proxy:latest` succeeds without building locally
**Why human:** Requires a live CI run; cannot verify GHCR push success from static analysis

### Gaps Summary

No gaps. All 10 observable truths are verified, all 5 artifacts exist and are substantive and wired, all 6 key links are connected, and all 6 requirement IDs are satisfied.

One note on the stale-reference check: `tests/smoke-proxy.sh` references `init-firewall.py` but only to verify the file is ABSENT from the container (MIG-01 regression test). This is correct behavior, not a stale reference. The `docs/plan/milestones/` files contain historical pre-migration planning docs that were explicitly preserved as a record of completed work per the SUMMARY decision log.

---

_Verified: 2026-03-24T04:00:00Z_
_Verifier: Claude (gsd-verifier)_
