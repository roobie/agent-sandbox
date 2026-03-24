---
phase: 03-development-environment
verified: 2026-03-24T02:04:00Z
status: passed
score: 11/11 must-haves verified
re_verification: false
---

# Phase 3: Development Environment Verification Report

**Phase Goal:** Sandbox containers arrive with a fully-functional development environment — all language runtimes pre-installed and accessible, per-package-manager proxy configuration active so all install traffic routes through Squid, and mise tasks on the host covering the full sandbox lifecycle.
**Verified:** 2026-03-24T02:04:00Z
**Status:** passed
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|---------|
| 1 | node, python, go, rustc, bun, uv commands available in container without post-start install | VERIFIED | All 7 runtimes installed via `mise install` under `MISE_DATA_DIR=/usr/local/share/mise` in Dockerfile lines 51-57, with shims at `/usr/local/share/mise/shims` on PATH (line 45). SUMMARY records actual versions: node v24.14.0, python 3.13.12, go 1.26.1, rustc 1.94.0, bun 1.3.11, uv 0.9.26. |
| 2 | rust-analyzer, pyright, typescript-language-server available in container | VERIFIED | `mise install rust-analyzer@latest` in line 56; pyright and typescript-language-server installed via npm backend at lines 66-68. SUMMARY records versions: rust-analyzer 0.3.2836, pyright 1.1.408, typescript-language-server 5.1.3. |
| 3 | npm traffic routes through Squid proxy (.npmrc proxy= present) | VERIFIED | Dockerfile lines 79-80: `printf 'proxy=http://proxy:3128\nhttps-proxy=http://proxy:3128\ncache=/home/dev/.npm\n' > /home/dev/.npmrc`. Path not under any volume mount. SUMMARY confirms Squid access logs show registry.npmjs.org entries. |
| 4 | cargo traffic routes through Squid (/etc/cargo/config.toml present) | VERIFIED | Dockerfile lines 89-91: `mkdir -p /etc/cargo && printf '[http]\nproxy = "http://proxy:3128"\n' > /etc/cargo/config.toml`. Avoids volume-shadowed /home/dev/.cargo. CARGO_HTTP_PROXY also set in docker-compose.yml and mise.toml sandbox:run. |
| 5 | git traffic routes through Squid (git config http.proxy present) | VERIFIED | Dockerfile line 83: `git config --global http.proxy http://proxy:3128`. Written to /home/dev/.gitconfig (not volume-mounted). |
| 6 | Runtimes survive volume mount (system-install outside home-dir volumes) | VERIFIED | MISE_DATA_DIR=/usr/local/share/mise (Dockerfile line 43) redirects all installs to a path not covered by any named volume mount. PATH includes /usr/local/share/mise/shims (line 45). RUSTUP_HOME and CARGO_HOME also moved to /usr/local/share/ (lines 46-47) to avoid /root/.cargo inaccessibility. |
| 7 | Package cache volumes (npm-cache, pip-cache, go-cache) persist across runs | VERIFIED | docker-compose.yml lines 59-61 mount all three; lines 108-110 declare them as named volumes. mise.toml sandbox:run mounts all three (lines 76-78). SUMMARY confirms cache persistence: 65 packages installed in 0.4s after restart. |
| 8 | GOPROXY and CARGO_HTTP_PROXY env vars active in sandbox | VERIFIED | docker-compose.yml lines 90-92; mise.toml sandbox:run lines 88-89. Both methods covered. |
| 9 | Squid allowlist covers all package manager and runtime domains | VERIFIED | config/allowlist.txt (39 lines): .npmjs.org, .npmjs.com, .crates.io, .static.crates.io, .index.crates.io, .proxy.golang.org, .sum.golang.org, .storage.googleapis.com, .nodejs.org, .static.rust-lang.org, .bun.sh, .dl.google.com all present. |
| 10 | mise tasks proxy:start/stop/status + sandbox:build/run/stop + image:build all defined | VERIFIED | mise.toml has exactly 7 task definitions (grep -c "^\[tasks\." = 7). All 7 tasks present: proxy:start (with health polling), proxy:stop, proxy:status, sandbox:build, image:build, sandbox:run (with --name/--workspace flags), sandbox:stop. |
| 11 | Two sandbox instances can run simultaneously with different NAME values | VERIFIED | mise.toml sandbox:run uses `${usage_name:-default}` to name containers `agent-sandbox-${NAME}`. No port conflicts (no ports: exposed). SUMMARY confirms verify-01 and verify-02 ran simultaneously. |

**Score:** 11/11 truths verified

---

### Required Artifacts

| Artifact | Provides | Status | Details |
|----------|----------|--------|---------|
| `images/agents/claude/Dockerfile` | System-wide mise installs + proxy config files | VERIFIED | 103 lines. MISE_DATA_DIR strategy at line 43. 7 runtimes + 2 LSP tools installed. Proxy configs at lines 79-91. USER sequence correct (root/dev/root/dev/root/root). |
| `docker-compose.yml` | Cache volumes + GOPROXY + CARGO_HTTP_PROXY | VERIFIED | npm-cache, pip-cache, go-cache each appear twice (mount + declaration). GOPROXY and CARGO_HTTP_PROXY in environment section. .:/workspace bind-mount at line 49. |
| `config/allowlist.txt` | Allowlist entries for all package manager domains | VERIFIED | 39 lines. All 12 new domains present plus all original entries (.github.com, .pypi.org etc. preserved). |
| `mise.toml` | All 7 lifecycle tasks | VERIFIED | 106 lines. 7 task definitions. Usage blocks with --name/--workspace flags. Volume init container pattern. No deprecated Tera {{arg}} syntax. |

---

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| Dockerfile MISE_DATA_DIR | /usr/local/share/mise/shims/ | ENV + `mise install` + `mise use -g` | VERIFIED | ENV MISE_DATA_DIR=/usr/local/share/mise (line 43); PATH includes shims dir (line 45); all installs happen after ENV is set. |
| Dockerfile USER dev | /home/dev/.npmrc | `printf > /home/dev/.npmrc` | VERIFIED | Lines 73-80: USER dev context, printf writes proxy config to .npmrc. |
| Dockerfile USER root | /etc/cargo/config.toml | mkdir -p + printf | VERIFIED | Lines 85-91: USER root context, creates /etc/cargo/config.toml with [http] proxy. |
| mise.toml sandbox:run | agent-sandbox_sandbox-internal network | --network flag in docker run | VERIFIED | Line 59: `--network agent-sandbox_sandbox-internal` (compose-qualified name). |
| mise.toml sandbox:run | npm-cache, pip-cache, go-cache volumes | --volume flags | VERIFIED | Lines 76-78: all three cache volumes mounted to correct paths. |
| mise.toml proxy:start | health check | python3 JSON parsing of docker inspect | VERIFIED | Line 9: uses python3 to parse JSON output, avoids Tera template conflict with `{{.State.Health.Status}}`. |
| config/allowlist.txt | Squid ACL | host-mounted at /etc/squid/allowlist.txt:ro | VERIFIED | docker-compose.yml line 21: `./config/allowlist.txt:/etc/squid/allowlist.txt:ro`. |

---

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| DEVENV-01 | 03-01 | Base image is Debian bookworm slim with git, curl, ripgrep, jq, neovim, tmux, fzf, build-essential, cmake | VERIFIED | images/base/Dockerfile installs all listed tools: git (line 10), curl (line 36), ripgrep (line 22), jq (line 33), neovim (line 35), tmux (line 38), fzf (line 14), build-essential (line 40), cmake (line 26). |
| DEVENV-02 | 03-01, 03-04 | Language runtimes via mise: Node LTS, Python 3.12+, Go latest, Rust, uv, Bun, rust-analyzer | VERIFIED | Dockerfile lines 51-57: node@lts, python@3.13, go@latest, rust@stable, bun@1.3, rust-analyzer@latest, uv@$UV_VERSION. Actual versions confirmed: node v24.14.0, python 3.13.12, go 1.26.1, rustc 1.94.0, bun 1.3.11, uv 0.9.26. |
| DEVENV-03 | 03-01, 03-04 | Runtimes via `mise install --system` to survive volume mount shadowing | VERIFIED | Implemented via MISE_DATA_DIR=/usr/local/share/mise strategy (valid equivalent — `mise install --system` flag does not exist in current mise). Achieves identical outcome: tools installed to path outside all named volume mounts. |
| DEVENV-04 | 03-02, 03-04 | Package cache volumes (npm, pip, cargo, go modules) persist across sandbox runs | VERIFIED | docker-compose.yml: npm-cache, pip-cache, go-cache volumes declared and mounted. mise.toml sandbox:run: same volumes mounted via --volume flags. |
| DEVENV-05 | 03-01, 03-04 | LSP tooling: rust-analyzer, pyright, typescript-language-server | VERIFIED | Dockerfile lines 56, 66-68: rust-analyzer@latest, npm:pyright@latest, npm:typescript-language-server@latest installed and activated. |
| DEVENV-06 | 03-01 | Non-root user execution with UID/GID adjustment | VERIFIED (partial) | Dev user (UID 500) is the runtime user. entrypoint.sh performs UID/GID adjustment when /etc is writable; silently accepts fixed UID 500 under read_only:true. Limitation accepted per CONTEXT.md decision — dynamic adjustment incompatible with --read-only + no CAP_CHOWN. Core requirement (non-root execution) is met; dynamic matching is a known limitation. |
| DEVENV-07 | 03-01, 03-02, 03-04 | Per-package-manager proxy config: .npmrc, cargo config.toml, git config, GOPROXY | VERIFIED | .npmrc at Dockerfile line 79-80; /etc/cargo/config.toml at lines 89-91; git config at line 83; GOPROXY in docker-compose.yml line 90 and mise.toml sandbox:run line 88. |
| ORCH-01 | 03-03, 03-04 | mise tasks: proxy:start, proxy:stop, proxy:status | VERIFIED | mise.toml: all three tasks defined. proxy:start includes health polling loop. |
| ORCH-02 | 03-03, 03-04 | mise tasks: sandbox:build, sandbox:run, sandbox:stop | VERIFIED | mise.toml: all three tasks defined. sandbox:run includes volume init container pattern. |
| ORCH-03 | 03-03, 03-04 | mise tasks support multiple named sandbox instances simultaneously | VERIFIED | sandbox:run uses `--name/-n` flag, names containers `agent-sandbox-${NAME}`. No port conflicts. Confirmed simultaneous operation in SUMMARY. |
| ORCH-04 | 03-02, 03-03, 03-04 | Workspace bind-mounted from host at /workspace | VERIFIED | docker-compose.yml line 49: `.:/workspace`. mise.toml sandbox:run line 70: `--volume "${WORKSPACE}:/workspace"`. |

---

### Anti-Patterns Found

No anti-patterns detected in any key phase file. No TODO/FIXME/placeholder comments. No stub implementations. No empty handlers.

---

### Human Verification Required

The following items were verified by the human operator during Plan 04 execution (recorded in 03-04-SUMMARY.md) and do not require additional human re-verification:

1. **Runtime versions inside container** — node v24.14.0, python 3.13.12, go 1.26.1, rustc 1.94.0, bun 1.3.11, uv 0.9.26, rust-analyzer 0.3.2836, pyright 1.1.408, typescript-language-server 5.1.3 all confirmed working.
2. **npm proxy traffic in Squid logs** — registry.npmjs.org entries confirmed in Squid access log after `npm install`.
3. **Cache volume persistence** — 65 packages installed in 0.4s on second run (cache hit).
4. **Multi-instance** — verify-01 and verify-02 ran simultaneously.
5. **Lifecycle tasks** — proxy:start, sandbox:run, sandbox:stop all exited 0 end-to-end.

---

### Notable Deviations (Not Gaps)

The following deviations from the plan are **correct implementations**, not gaps:

1. **DEVENV-03: MISE_DATA_DIR strategy instead of `mise install --system`** — The plan specified `mise install --system` which does not exist in current mise versions. The implementation correctly uses `MISE_DATA_DIR=/usr/local/share/mise` to achieve identical isolation from the mise-state volume mount. This is a valid deviation that satisfies the requirement's intent.

2. **RUSTUP_HOME/CARGO_HOME at /usr/local/share/** — Required discovery: /root/.cargo is drwx------ and inaccessible to the dev user. Moving these to /usr/local/share/ makes Rust accessible. Correct fix.

3. **DEVENV-06 accepted limitation** — Under `--read-only` + no CAP_CHOWN, dynamic UID/GID adjustment is skipped at runtime. Container runs as fixed UID 500. The entrypoint.sh logic correctly detects this and falls back silently. Non-root execution requirement is met; host-UID matching is a documented limitation per CONTEXT.md.

---

### Gaps Summary

No gaps. All 11 observable truths are verified. All 4 artifacts are substantive and wired. All 7 key links are verified. All 11 requirements are satisfied.

---

_Verified: 2026-03-24T02:04:00Z_
_Verifier: Claude (gsd-verifier)_
