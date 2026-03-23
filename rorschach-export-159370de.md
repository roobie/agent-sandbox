# Research: Simple way to sandbox coding agents

**Run ID:** 159370de-ed68-4b0e-b1a2-94fdeb4796fd  
**Model:** github_copilot/gpt-5-mini  
**Template:** general  
**Date:** 2026-03-23 22:16 UTC  

## Sources

1. [https://www.reddit.com/r/ClaudeCode/comments/1nz46qi/im_exploring_a_secure_sandbox_for_ai_coding/](https://www.reddit.com/r/ClaudeCode/comments/1nz46qi/im_exploring_a_secure_sandbox_for_ai_coding/)
2. [https://www.bunnyshell.com/guides/coding-agent-sandbox/](https://www.bunnyshell.com/guides/coding-agent-sandbox/)
3. [https://www.kdnuggets.com/5-code-sandbox-for-your-ai-agents](https://www.kdnuggets.com/5-code-sandbox-for-your-ai-agents)
4. [https://docs.langchain.com/oss/python/deepagents/sandboxes](https://docs.langchain.com/oss/python/deepagents/sandboxes)
5. [https://cursor.com/blog/agent-sandboxing](https://cursor.com/blog/agent-sandboxing)
6. [Build a coding agent with Modal Sandboxes and LangGraph](https://modal.com/docs/examples/agent)
7. [https://developer.nvidia.com/blog/practical-security-guidance-for-sandboxing-agentic-workflows-and-managing-execution-risk/](https://developer.nvidia.com/blog/practical-security-guidance-for-sandboxing-agentic-workflows-and-managing-execution-risk/)
8. [https://www.docker.com/blog/docker-sandboxes-run-claude-code-and-other-coding-agents-unsupervised-but-safely/](https://www.docker.com/blog/docker-sandboxes-run-claude-code-and-other-coding-agents-unsupervised-but-safely/)
9. [https://www.youtube.com/watch?v=bSAeyJpMRhQ](https://www.youtube.com/watch?v=bSAeyJpMRhQ)
10. [Ask HN: How are you sandboxing coding agents?](https://news.ycombinator.com/item?id=46400129)

## Synthesis

Short answer
Run each agent inside an isolated, ephemeral container (or VM for high-risk tasks) with network disabled or tightly whitelisted, a non‑root user, read‑only rootfs, a small writable tmpfs/workspace, dropped capabilities, resource/time limits, and logging/monitoring. That gives a very good balance of simplicity, repeatability, and practical safety for coding agents. (See details and a minimal docker example below.) [8][9][7][5]

Why this pattern?
- Containers are simple, well‑known, fast to start, and integrate with CI/CD and orchestration—so they’re the practical default for many builders. Docker + container flags provide most of the protections you need for everyday agent workloads. [8][9][10]
- If you need stronger guarantees, run the agent in a dedicated VM or use hardened runtimes like gVisor/Kata Containers (defense‑in‑depth). VMs cost more but reduce host escape risk. [7][10]
- Complement runtime isolation with process/time limits, network controls, ephemeral workspaces, and audit/logging—many escapes are prevented or detected by combining controls. [5][2][3][7]

Key controls to enable (simple checklist)
- Isolation boundary
  - Container per agent run (or VM for high-risk code). [8][9][7][10]
- Least privilege user
  - Run as unprivileged (non‑root) user inside the container. [9][8]
- Filesystem controls
  - Read‑only root filesystem and only mount a small writable workspace (tmpfs or ephemeral volume). Use minimal host mounts and avoid mounting sensitive host paths. [8][5][3]
- Network controls
  - Disable network by default (--network=none) or whitelist specific hosts/IPs via a proxy. Many attacks require network egress. [8][5]
- Capability/ syscall limits
  - Drop Linux capabilities (--cap-drop=ALL) and use seccomp to restrict syscalls. Add AppArmor/SELinux where available. [7][8]
- Resource and time limits
  - CPU, memory, PID limits and execution timeouts to stop runaway processes. [8][5]
- Ephemeral runs + reproducibility
  - Recreate containers/VMs per run and destroy workspaces afterward. Use git worktrees or ephemeral repos for test inputs. [10][2]
- Logging, monitoring, and human review
  - Capture stdout/stderr, filesystem diffs, network logs. Block unknown outputs or queue suspicious runs for manual review. Add an approval/review step for code that touches production. [5][2][7]
- Defense in depth
  - Combine the above: isolation + syscall filters + network policy + monitoring. No single control is foolproof. [7][5]

Tradeoffs and common community patterns
- Convenience vs safety: Docker is convenient and often “good enough” (fast feedback), but not as resistant to escapes as a VM or specialized runtimes (gVisor/Kata). If you need provable isolation, prefer VMs or hardened runtimes. [8][7][10]
- Parallelism: Containers are easy to run in parallel; VMs are heavier. Choose based on workload volume and security needs. [10]
- Defense in depth is recommended: people combine lightweight tools (devcontainers, worktrees, firejail/bubblewrap) for convenience and reserve VMs for high-risk tasks. [10][9][5]

Minimal concrete Docker example
(This is a pragmatic starting point; adapt profiles and seccomp/AppArmor as you harden further.)

docker run --rm \
  --network=none \
  --user 1000:1000 \
  --read-only \
  --tmpfs /tmp:rw,noexec,nosuid,size=64m \
  --memory=256m --cpus=0.5 --pids-limit=100 \
  --cap-drop=ALL --security-opt=no-new-privileges \
  -v /host/agent-workdir:/work:rw \
  my-agent-image:latest \
  timeout 60s python /work/run_agent.py

Notes on the example
- --network=none prevents egress unless you explicitly allow it; replace with a proxy/whitelist as needed. [8][5]
- --read-only + --tmpfs keeps the container filesystem ephemeral; only /work is mounted from host. [8][5]
- --cap-drop and no-new-privileges reduce attack surface; add a custom seccomp profile for better syscall limiting. [7][8]
- The timeout (external or inside the container) ensures the agent can’t run forever. [5]

Higher‑security options to consider (if you need them)
- Run agents inside a dedicated VM (or cloud VMs) if you require stronger host‑escape guarantees. [7][10]
- Use gVisor or Kata Containers to get stronger isolation than stock containers. [7]
- Use language/platform sandboxes and orchestrators (LangChain sandboxes, Modal Sandboxes, LangGraph integrations) to enforce per‑action rules and auditing in your agent framework. These make it easier to implement per-step restrictions and logging. [4][6]
- Instrument the agent’s planning/execution (limit which tools or code it may run) and add a staged approval flow for sensitive outputs. [5][2][3]

Sources and corroboration
- Practical how‑tos and container recommendation: Docker blog and a how‑to video on using Docker to sandbox agents. [8][9]
- Community practices: Ask HN thread describing worktrees, devcontainers, firejail, VMs, and tradeoffs used by practitioners. [10]
- Implementation guidance and examples: Cursor blog (local agent sandbox patterns), Modal Sandboxes + LangGraph example, and LangChain sandbox docs for agent frameworks. [5][6][4]
- Higher‑assurance guidance and defense‑in‑depth recommendations: NVIDIA security guidance recommends threat modeling, syscall profiles, runtimes (gVisor/Kata), and layered controls. [7]
- Practical checklists and tradeoffs: Bunnyshell and KDnuggets lists of sandbox strategies and best practices. [2][3]

Contradictions / tensions to watch
- Ease vs security: community often prefers containers (convenient) but experts emphasize VMs/hardened runtimes if escapes are catastrophic. [8][10][7]
- “No network” vs usefulness: disabling network is safest but can render some agent workflows useless—use a proxy/whitelist per use case. [8][5]
- Complete isolation vs observability: more restrictive environments make debugging and integration testing harder; log and snapshot mechanisms help bridge that gap. [5][2]

Brief summary
For most use cases the simplest, practical sandbox is a per‑run container with network disabled/whitelisted, dropped capabilities, a non‑root user, read‑only rootfs + small writable tmpfs workspace, and strict CPU/memory/time limits; complement that with logging, ephemeral runs, and a human review for sensitive outputs. Upgrade to VMs or hardened runtimes (gVisor/Kata) if your threat model requires stronger host‑escape protection. [8][9][5][7][10]

---
*Generated by rorschach | run_id: 159370de-ed68-4b0e-b1a2-94fdeb4796fd*