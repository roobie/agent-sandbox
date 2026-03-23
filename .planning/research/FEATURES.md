# Feature Research

**Domain:** Local coding agent sandbox containers (Docker-based, self-hosted)
**Researched:** 2026-03-24
**Confidence:** HIGH (multiple current sources, active ecosystem in 2025-2026)

## Feature Landscape

### Table Stakes (Users Expect These)

Features users assume exist. Missing these = product feels incomplete.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Container isolation per agent run | All sandbox products do this; it's the baseline unit of safety | LOW | Already exists in base image |
| Non-root user execution | Security baseline; running as root inside a container is negligent | LOW | Already implemented (dev user uid/gid 500) |
| Network egress control | Without it, agents can exfiltrate data, call arbitrary APIs, phone home | MEDIUM | Pivoting from iptables to Squid proxy |
| Read-only rootfs with writable workspace | Prevents agent from modifying the base system; any tmpfs/volume for writes | LOW | Planned (read-only rootfs + tmpfs) |
| Capability dropping (--cap-drop=ALL) | Standard hardening; expected by security-conscious users | LOW | Planned (--cap-drop=ALL, --security-opt=no-new-privileges) |
| Resource limits (CPU, memory, PIDs) | Prevents runaway agent processes from starving host | LOW | Planned |
| Execution timeouts | Prevents infinite loops or stuck agents consuming resources | LOW | Planned |
| Workspace bind mount (host dir → container) | How agents access the codebase they're working on | LOW | Already implemented |
| Credential isolation (API keys, SSH keys) | Keys must not be readable by arbitrary agent code; scope to intended use | MEDIUM | Partial — credential volumes exist; needs intentional scoping |
| Pre-installed dev toolchain | Agents need git, curl, build tools, language runtimes without setup delays | MEDIUM | Already have Debian base + common tools; expanding with mise |
| Ephemeral runs (destroy after use) | Clean slate prevents state accumulation between agent sessions | LOW | Supported via Docker container lifecycle |
| seccomp profile | Reduces kernel attack surface; expected in hardened container configs | MEDIUM | Planned |

### Differentiators (Competitive Advantage)

Features that set the product apart. Not required, but valued.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Shared Squid proxy for multi-agent egress | One ACL config governs all concurrent sandboxes; simpler than N per-container firewalls | MEDIUM | Core pivot of this milestone; SNI peek/splice avoids MITM |
| Simultaneous multi-sandbox via single proxy | Run N agents in parallel with one egress gateway; eliminates per-container firewall overhead | MEDIUM | Architectural advantage over iptables approach |
| mise-based language runtime suite | All major runtimes (Node, Python, Go, Rust, Bun) pinned and reproducible via .mise.toml | MEDIUM | mise already used for agent tooling; natural extension |
| Package cache volumes across runs | npm, pip, cargo, go module caches survive sandbox lifecycle → faster subsequent runs | LOW | Significant DX win for heavy agent workloads |
| LSP / editor tooling pre-installed | Agents with code intelligence (rust-analyzer, etc.) produce better code | MEDIUM | Differentiates from bare execution sandboxes |
| mise task orchestration on host | Build, run, stop, proxy lifecycle managed with mise tasks; no separate CLI tool needed | LOW | Cohesive developer experience |
| Devcontainer + Docker Compose dual-mode | Works both headless (mise tasks) and with VS Code devcontainer attach | LOW | Already implemented; maintain both modes |
| Published pre-built image (GHCR/Docker Hub) | Zero-build onboarding; pull and run | LOW | Deployment milestone item |
| Policy-as-config for Squid ACLs | Domain allowlist expressed in a config file, not embedded in scripts | LOW | Evolves from existing policy-as-JSON iptables approach |
| Filesystem diff logging | Know exactly what the agent changed; useful for review and audit | MEDIUM | Pairs with stdout/stderr capture for full observability |
| UID/GID adjustment to match host | Workspace files owned by correct user on host after agent writes them | LOW | Already implemented; must survive refactor |

### Anti-Features (Commonly Requested, Often Problematic)

Features that seem good but create problems.

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| GUI / web dashboard | Easier to manage sandboxes visually | Adds significant build/maintenance surface; this is a developer tool, not a SaaS | CLI (mise tasks) is the right interface for this audience |
| Per-container sidecar proxy | Mirrors sidecar patterns from service mesh architectures | N proxies = N configs; harder to audit, higher resource overhead per sandbox | Shared proxy container: one config, one place to change ACLs |
| VM-based isolation (gVisor/Kata/Firecracker) | Stronger isolation than containers | 3-10x startup overhead; overkill for local dev threat model where agent already has workspace access | Container + seccomp + capability drops is sufficient; document the threat model clearly |
| Kubernetes orchestration | Familiar to platform engineers; scales to many sandboxes | Massive operational overhead for a local dev tool; adds cluster management burden | Docker Compose / mise tasks cover the local multi-sandbox use case |
| Agent framework integration (LangChain, Modal) | Tighter integration with orchestration frameworks | This is infrastructure-layer, not framework-layer; coupling at this level creates version dependencies and limits agent choice | Stay container-native; let agent frameworks call docker/mise commands |
| Full network disable (--network=none) | Maximally restrictive | Renders most agent workflows unusable (can't fetch packages, docs, APIs) | Squid proxy with domain allowlist: agents can access what they need, nothing else |
| Inline secret injection via env vars | Convenient for quick starts | Env vars leak into child processes, logs, /proc; visible to agent code | Named volumes for credentials; proxy-side injection for API tokens where possible |
| MITM TLS inspection on Squid | Enables deep packet inspection of HTTPS traffic | Requires installing a CA cert inside the sandbox; significantly increases attack surface and complexity | SNI peek/splice: Squid reads the TLS ClientHello to check the hostname without decrypting — no CA cert needed |
| Long-lived persistent sandbox workspaces (Daytona model) | State persists across sessions | For local dev, state accumulation causes reproducibility problems; each agent run should start clean | Ephemeral containers + persistent cache volumes for package caches only |

## Feature Dependencies

```
[Network egress control via Squid]
    └──requires──> [Squid proxy container running]
                       └──requires──> [Docker network shared between proxy and sandboxes]

[Multi-sandbox simultaneous runs]
    └──requires──> [Shared proxy container]
    └──requires──> [Non-conflicting container naming / compose profiles]

[Package cache across runs]
    └──requires──> [Named Docker volumes for npm/pip/cargo/go caches]
    └──requires──> [Sandbox containers mount those volumes]

[LSP / code intelligence]
    └──requires──> [Language runtimes installed (mise)]
    └──requires──> [Language server binaries installed (rust-analyzer, pyright, etc.)]

[mise task orchestration]
    └──requires──> [mise installed on host]
    └──enhances──> [Language runtimes inside container via mise]

[Devcontainer support]
    └──requires──> [.devcontainer/devcontainer.json]
    └──conflicts──> [Read-only rootfs] (devcontainer extensions write to container; use tmpfs overlay)

[Filesystem diff logging]
    └──requires──> [Stdout/stderr capture baseline]
    └──enhances──> [Observability]

[UID/GID matching]
    └──requires──> [Entrypoint script runs before agent]
    └──prevents──> [File permission problems on workspace bind mount]

[Published pre-built image]
    └──requires──> [CI/CD pipeline]
    └──requires──> [Stable image tag strategy]
```

### Dependency Notes

- **Squid proxy requires shared Docker network:** Sandbox containers must join the proxy's network to route traffic through it. This is a compose-level concern, not a Dockerfile concern.
- **LSP requires runtimes:** Language servers are installed alongside runtimes. Installing rust-analyzer without the Rust toolchain is useless. mise handles this as a unit.
- **Devcontainer conflicts with read-only rootfs:** VS Code extensions write to the container filesystem. Workaround: mount writable tmpfs overlays for extension storage paths, or accept that devcontainer mode relaxes rootfs immutability.
- **Package cache volumes enhance mise runtimes:** mise installs runtimes inside the container; package caches (npm, cargo, pip) persist the download artifacts so re-runs don't re-fetch.

## MVP Definition

### Launch With (v1 — current milestone)

Minimum viable product for the Squid proxy pivot milestone.

- [ ] Shared Squid proxy container with domain allowlist ACL config — core architectural pivot
- [ ] Multiple sandbox containers routing through single proxy simultaneously — validates multi-agent value
- [ ] Squid SNI peek/splice mode (no MITM, no CA cert) — maintains security model without complexity
- [ ] Full language runtime suite via mise (Node, Python, Go, Rust, Bun, uv) — agents need these
- [ ] mise tasks for proxy start/stop and sandbox run/stop on host — cohesive operator experience
- [ ] Package cache volumes (npm, pip, cargo, go) — reduces agent run time significantly
- [ ] Read-only rootfs + writable tmpfs — closes the stateful-container attack surface
- [ ] Process hardening: --cap-drop=ALL, --security-opt=no-new-privileges, seccomp — completes security baseline
- [ ] Resource limits (CPU, memory, PID) and execution timeout — prevents runaway sandboxes
- [ ] Stdout/stderr capture — minimum observability

### Add After Validation (v1.x)

Features to add once the proxy architecture is confirmed working.

- [ ] LSP tooling (rust-analyzer, pyright, tsserver) — add after runtime suite is stable; dependency chain is verified
- [ ] Filesystem diff logging — add after stdout/stderr capture is instrumented; extends observability
- [ ] Published image to GHCR/Docker Hub — add after image is stable enough for external consumption
- [ ] Seccomp profile refinement — start with default Docker seccomp, tune after observing what agents actually need

### Future Consideration (v2+)

Features to defer until the proxy architecture is proven.

- [ ] CLI tool replacing mise tasks — defer until mise tasks prove insufficient; premature abstraction risk
- [ ] Per-project Squid ACL profiles — defer until users have multiple projects with different egress needs
- [ ] Audit trail / structured event log — defer until there's demand for compliance/review workflows

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| Shared Squid proxy | HIGH | MEDIUM | P1 |
| Multi-sandbox simultaneous routing | HIGH | LOW (follows from proxy) | P1 |
| Squid SNI peek/splice (no MITM) | HIGH | MEDIUM | P1 |
| mise runtime suite | HIGH | LOW | P1 |
| Package cache volumes | HIGH | LOW | P1 |
| mise task orchestration | HIGH | LOW | P1 |
| Read-only rootfs + tmpfs | MEDIUM | LOW | P1 |
| Process hardening (cap-drop, seccomp) | MEDIUM | LOW | P1 |
| Resource limits + timeouts | MEDIUM | LOW | P1 |
| Stdout/stderr capture | MEDIUM | LOW | P1 |
| LSP tooling | MEDIUM | MEDIUM | P2 |
| Filesystem diff logging | MEDIUM | MEDIUM | P2 |
| Published pre-built image | MEDIUM | MEDIUM | P2 |
| Seccomp profile tuning | LOW | MEDIUM | P2 |
| CLI tool | LOW | HIGH | P3 |
| Per-project ACL profiles | LOW | MEDIUM | P3 |
| Structured audit log | LOW | HIGH | P3 |

**Priority key:**
- P1: Must have for this milestone launch
- P2: Should have, add when P1 is stable
- P3: Nice to have, future consideration

## Competitor Feature Analysis

| Feature | E2B | Docker Sandboxes | Daytona | This Project |
|---------|-----|-----------------|---------|--------------|
| Isolation model | Firecracker microVM | microVM + private Docker daemon | Docker / Kata / Sysbox | Docker container + seccomp + cap-drop |
| Network egress control | None built-in | Allow/deny lists | Evolving | Squid proxy with domain allowlist |
| Cold start | ~150ms | Fast (VM overhead) | ~27-90ms | ~1-2s (container start, not VM) |
| Language runtimes | Custom Docker images | Node, Python, Go pre-loaded | Via SDK | mise: Node, Python, Go, Rust, Bun, uv |
| Persistence model | Ephemeral + filesystem API | Persistent until removed | Stateful workspaces | Ephemeral containers + persistent cache volumes |
| LSP support | None | None | Built-in | rust-analyzer + language servers |
| Package caching | None built-in | None | None | Named volumes for npm/pip/cargo/go |
| Multi-agent | Kubernetes-scaled | N sandboxes | N sandboxes | N containers → 1 shared proxy |
| Self-hosted | OSS option | No | OSS option | Yes (primary deployment model) |
| Devcontainer | No | No | No | Yes (VS Code attach) |
| Cost | $0.05/hr (SaaS) | Paid service | Paid service | Infrastructure only (local) |
| Orchestration | SDK / REST API | Docker CLI | Python SDK | mise tasks |

**Key local-dev differentiation:** Cloud sandboxes (E2B, Daytona, Modal) are SaaS services — pay-per-second, managed infrastructure, API-driven. This project is the local, self-hosted alternative: runs on your machine, no recurring cost, integrates with your existing Docker/mise workflow, maintains your own ACL policy.

## Sources

- [Modal: Top AI Code Sandbox Products in 2025](https://modal.com/blog/top-code-agent-sandbox-products) — feature matrix across major cloud sandboxes
- [Northflank: Best code execution sandbox for AI agents 2026](https://northflank.com/blog/best-code-execution-sandbox-for-ai-agents) — essential vs differentiating analysis
- [Docker Sandboxes documentation](https://docs.docker.com/ai/sandboxes/) — microVM + private Docker daemon isolation model
- [Firecrawl: AI Agent Sandbox 2026](https://www.firecrawl.dev/blog/ai-agent-sandbox) — table stakes enumeration
- [Pere Villega: I Built Yet Another Sandbox](https://perevillega.com/posts/2026-03-03-ai-sandbox-coding-agents/) — local self-hosted sandbox gaps vs cloud alternatives
- [mfyz: AI Coding Agent Sandbox Container](https://mfyz.com/ai-coding-agent-sandbox-container/) — iptables default-deny + domain whitelist pattern
- [Shayon: Let's Discuss Sandbox Isolation](https://www.shayon.dev/post/2026/52/lets-discuss-sandbox-isolation/) — isolation spectrum and local dev threat model
- [Daniel Demmel: Coding Agents in Secured VS Code Dev Containers](https://www.danieldemmel.me/blog/coding-agents-in-secured-vscode-dev-containers) — devcontainer security patterns
- [Docker Blog: Run Claude Code and More Safely](https://www.docker.com/blog/docker-sandboxes-run-claude-code-and-other-coding-agents-unsupervised-but-safely/) — Docker's positioning on agent sandboxing
- Prior research synthesis: `docs/research.md` — community patterns from HN, Cursor blog, NVIDIA security guidance

---
*Feature research for: local coding agent sandbox (Docker + Squid proxy + mise)*
*Researched: 2026-03-24*
