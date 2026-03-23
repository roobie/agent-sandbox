# Codebase Concerns

**Analysis Date:** 2026-03-23

## Tech Debt

**Copilot image still installs Claude Code:**
- Issue: `images/agents/copilot/Dockerfile` (lines 28-30, 36-38, 41-42) installs and configures Claude Code CLI, aliases, and MCP server despite being labeled as a Copilot agent image
- Files: `images/agents/copilot/Dockerfile`
- Impact: Image is bloated with unnecessary Claude-specific tools and aliases that should not be present in a Copilot-only image. Increases attack surface, reduces clarity about agent support
- Fix approach: Replace Claude Code installation with actual Copilot CLI installation (likely via mise or direct APT). Update aliases to point to copilot commands instead of claude aliases

**Duplicate domain in base policy:**
- Issue: `images/base/policy.json` has "github.com" listed twice in the domains array (lines 4-5)
- Files: `images/base/policy.json`
- Impact: Redundant DNS resolution and ipset additions. No functional impact but indicates lack of validation/linting of policy files
- Fix approach: Remove duplicate. Add JSON validation to policy loading in `init-firewall.py` to deduplicate or warn on policy files with duplicate domains

**Incomplete Dockerfile for Copilot image:**
- Issue: `images/agents/copilot/Dockerfile` line 24 has a commented-out `.claude` directory creation with placeholder `_` comment, suggesting incomplete migration or refactoring
- Files: `images/agents/copilot/Dockerfile`
- Impact: Code clarity and maintainability. Someone reading this may be confused about intent
- Fix approach: Either complete the configuration or remove the commented line entirely with a explanatory comment

## Firewall & Network Security

**DNS-based IP resolution is volatile:**
- Issue: `init-firewall.py` function `resolve_domain()` (lines 210-227) resolves domains to IPs at container startup time, but domain-to-IP mappings can change. Multiple DNS queries might return different results
- Files: `images/base/init-firewall.py`
- Impact: If a domain's IP changes between container startup and container use, traffic may be blocked even though the domain was in the allowlist. Particularly problematic for CDNs and services with dynamic IP allocation
- Fix approach: (1) Document this limitation, (2) Consider periodic re-resolution via a cron job or refresh mechanism, (3) Use DNS interception at Layer 7 instead of Layer 3 IPs, (4) For next phase, migrate to proxy-based enforcement (already planned in m5)

**GitHub IP fetch failure is fatal:**
- Issue: `fetch_github_ips()` (lines 173-207) raises FirewallError if GitHub API call fails or returns invalid data, causing container startup to fail entirely
- Files: `images/base/init-firewall.py`, `images/base/entrypoint.sh`
- Impact: If GitHub API is unreachable at container startup time, the container cannot start at all. Blocks legitimate use when GitHub infrastructure is slow or unavailable
- Fix approach: Add graceful degradation: if GitHub IP fetch fails, either (1) skip GitHub service and warn, (2) use cached GitHub IPs from previous run, or (3) allow container to start in restricted mode with only explicitly whitelisted domains

**Docker DNS rule parsing is fragile:**
- Issue: `save_docker_dns_rules()` (lines 94-100) and `restore_docker_dns()` (lines 117-134) parse iptables output by line splitting and then re-parse as command args. If iptables output format changes or includes comments, parsing will fail silently or incorrectly
- Files: `images/base/init-firewall.py`
- Impact: Docker DNS NAT rules may not be properly restored, breaking DNS resolution inside the container. Silent failures make debugging difficult
- Fix approach: (1) Use `iptables-save` and `iptables-restore` with proper format files instead of manual parsing, (2) Add validation that restored rules are actually applied

**IPv6 is completely blocked but not documented:**
- Issue: `init-firewall.py` only configures IPv4 rules (iptables, not ip6tables). All IPv6 traffic is implicitly dropped by kernel default policy. No IPv6 policy file or explicit configuration
- Files: `images/base/init-firewall.py`, docs missing
- Impact: If a domain resolves to IPv6 addresses, those addresses will not be added to allowlist. Container has no IPv6 connectivity at all. May cause silent failures if software tries IPv6 before IPv4
- Fix approach: Either (1) explicitly document IPv6 is not supported, (2) add ip6tables rules mirroring IPv4 rules, or (3) if IPv6 not needed, explicitly disable it in container (sysctl)

**Host network detection uses fragile regex:**
- Issue: `setup_host_network()` (lines 270-294) uses regex `r"^(\d+\.\d+\.\d+)\.\d+$"` to extract /24 network from default route IP. Assumes /32 single host IP. Fails if host uses different subnet mask
- Files: `images/base/init-firewall.py`
- Impact: If host uses non-/24 subnet (e.g., /16), host connectivity will be misconfigured. Container may not reach host despite firewall being set up
- Fix approach: Parse the route line properly using `ip route` output structure (which includes CIDR), or use Python's `ipaddress` module to properly calculate network from IP and netmask

**Firewall idempotency relies on implicit state:**
- Issue: Entrypoint checks if ipset exists to determine if firewall is initialized (`images/base/entrypoint.sh` line 12). If ipset creation succeeds but later initialization fails partially, second run may skip firewall completely
- Files: `images/base/entrypoint.sh`, `images/base/init-firewall.py`
- Impact: Partial firewall failures are silently ignored on rerun, leaving container in inconsistent security state
- Fix approach: (1) Write explicit state file after successful firewall initialization, (2) check state file instead of implicit ipset existence, (3) add detailed logging of what was/wasn't already initialized

## Deployment & Configuration

**Sudoers configuration is missing for devcontainer:**
- Issue: `devcontainer.json` (line 38) runs `sudo /usr/local/bin/init-firewall.py` in postStartCommand but there's no sudoers file in the images to allow this password-less
- Files: `.devcontainer/devcontainer.json`, `images/base/Dockerfile` (missing sudoers setup)
- Impact: In devcontainer mode, the firewall initialization will fail asking for a password which can't be provided. Devcontainer launch hangs or fails
- Fix approach: Create `/etc/sudoers.d/agent-sandbox-firewall` file in base Dockerfile allowing dev user to run init-firewall.py without password

**Hardcoded paths and no validation:**
- Issue: Policy file location is hardcoded as `/etc/agent-sandbox/policy.json` in `init-firewall.py` line 21. POLICY_FILE env var overrides it but no validation it exists before use
- Files: `images/base/init-firewall.py` (lines 21, 410)
- Impact: If POLICY_FILE env var points to non-existent file, load_policy() will fail with generic error. Hard to troubleshoot what went wrong
- Fix approach: Early validation and clear error message when POLICY_FILE doesn't exist before attempting to read

**No rollback mechanism for firewall changes:**
- Issue: If `apply_firewall_rules()` (lines 297-361) is interrupted mid-execution, firewall rules may be in inconsistent state. No mechanism to restore previous known-good state
- Files: `images/base/init-firewall.py`
- Impact: Container may be left with partial firewall (some rules applied, others not), leading to unexpected behavior
- Fix approach: Build a transaction-like mechanism: (1) write rules to temporary ipset, (2) validate, (3) swap or (4) use iptables atomic operations

## Testing & Verification

**Firewall verification is weak:**
- Issue: `verify_firewall()` (lines 364-405) only tests one blocked and one allowed endpoint. If policy has 20 domains, only 1 is tested. False positives likely
- Files: `images/base/init-firewall.py`
- Impact: Misconfigured domains may not be caught. Container may appear to start successfully but later fail when code tries to reach an unlisted domain
- Fix approach: Test multiple domains from policy (sample if large), test both blocked and allowed for each class of endpoint

**No logging of what was added to firewall:**
- Issue: `init-firewall.py` prints to stdout but doesn't log which specific IPs were added for which domains. If firewall doesn't work, hard to debug
- Files: `images/base/init-firewall.py`
- Impact: Troubleshooting firewall issues is difficult. No audit trail of what was configured
- Fix approach: Add structured logging (JSON or syslog) with each operation: domain → resolved IPs → added to ipset

**No test coverage for firewall script:**
- Issue: `init-firewall.py` is 435 lines with complex logic (DNS resolution, IP validation, iptables command building) but there are no unit or integration tests
- Files: `images/base/init-firewall.py`
- Impact: Bugs may be shipped. Refactoring is risky. Regressions go undetected
- Fix approach: Add pytest test suite with mocked subprocess calls, test each function (resolve_domain, validate_cidr, etc.) with valid/invalid inputs

## Fragile Areas

**iptables command construction is error-prone:**
- Issue: Many iptables rules are built as Python lists and passed to subprocess (e.g., lines 306-345). If arguments are missing or malformed, subprocess fails silently if run_cmd_unchecked is used
- Files: `images/base/init-firewall.py`
- Impact: A typo in an iptables rule construction may silently fail, leaving firewall incomplete. Debugging requires examining subprocess output manually
- Fix approach: (1) Validate iptables rules before execution (pre-flight checks), (2) add structured logging of every iptables command with expected effect, (3) verify each command succeeded with follow-up check

**Policy JSON schema is implicit:**
- Issue: Policy file validation (`load_policy()` lines 67-91) checks for "services" and "domains" keys but doesn't enforce a strict schema. Unknown keys are silently ignored
- Files: `images/base/init-firewall.py`
- Impact: Typo in policy key (e.g., "domin" instead of "domains") is silently ignored, no domains loaded, user has no network access with no explanation
- Fix approach: Define explicit JSON schema (JSON Schema spec), validate against it, fail with clear error on unknown/missing keys

**Curl-based verification not representative:**
- Issue: `verify_firewall()` uses curl to test connectivity, but production container may not have curl (or may fail for different reasons). Verification doesn't prove actual workload connectivity
- Files: `images/base/init-firewall.py`
- Impact: Firewall may verify as working but actual tools (npm, pip, etc.) still fail to reach allowed domains due to TLS or other issues
- Fix approach: (1) Test with actual tools used in container (python requests, node fetch, etc.), (2) allow customizable verification commands per agent, (3) separate firewall verification from policy correctness verification

## Security Considerations

**Non-root user has passwordless sudo for firewall:**
- Issue: Devcontainer mode requires sudo to run init-firewall.py. Sudoers file (if created) must allow password-less execution
- Files: To be created: sudoers.d entry
- Current mitigation: None documented
- Recommendations: (1) Limit sudo to only /usr/local/bin/init-firewall.py with no arguments, (2) add audit logging via auditd for sudo calls, (3) consider running firewall as root in entrypoint instead of requiring sudo in devcontainer

**Unprivileged user can re-initialize firewall:**
- Issue: Dev user can execute init-firewall.py which modifies iptables rules. While restricted by capabilities, user could potentially weaken firewall policy
- Files: `images/base/entrypoint.sh` (line 14), `images/base/init-firewall.py`
- Current mitigation: Policy file is read-only (mounted from outside workspace), but user could modify POLICY_FILE env var to point to modified copy if writable
- Recommendations: (1) Enforce policy file is truly immutable (mount as readonly), (2) validate policy file permissions before loading, (3) restrict init-firewall.py to root or remove user access

**Root user access in entrypoint:**
- Issue: Entrypoint runs as root and modifies system files (chown, usermod, iptables). If container is somehow broken into, root access is present
- Files: `images/base/entrypoint.sh`
- Current mitigation: Runs only at startup, drops to non-root before interactive shell
- Recommendations: (1) Minimize time spent as root, (2) consider replacing entrypoint with init-time setup in Dockerfile if possible, (3) audit all root-requiring operations

## Missing Critical Features

**No mechanism to test policy before deployment:**
- Issue: Users must copy policy files and restart containers to test them. No dry-run or syntax check available
- Files: `images/base/init-firewall.py` (missing validation mode)
- Problem: Easy to introduce broken policies that break container on deploy
- Solution: Add --dry-run flag to init-firewall.py that validates policy, resolves domains, shows what would be added without actually modifying iptables

**No observability into what's blocked:**
- Issue: When traffic is blocked, container just fails silently. No log of blocked connections available
- Files: Missing: iptables logging rules
- Problem: Users can't diagnose why their code can't reach a domain (is it blocked by firewall or is domain actually down?)
- Solution: Add iptables rules with --log-prefix to log blocked traffic, pipe logs to syslog

**No support for port-specific allowlists:**
- Issue: Policy only supports domain-based allowlisting. If you want to block ssh to GitHub but allow https, no way to express that
- Files: `images/base/policy.json`, `images/base/init-firewall.py`
- Problem: Coarse-grained control increases risk of unintended access
- Solution: Extend policy schema to support port restrictions: `{ "domain": "example.com", "ports": [443] }`

**No caching of DNS resolutions:**
- Issue: If container restarts frequently, each startup re-resolves all domains, adding latency and DNS server load
- Files: `images/base/init-firewall.py` (missing caching)
- Problem: Slow container startup (extra 5-30 seconds for DNS resolution). Dependency on DNS server availability
- Solution: Cache resolved IPs to a file between runs, validate with --ttl logic, allow cache invalidation

## Test Coverage Gaps

**DNS resolution with multiple A records:**
- What's not tested: `resolve_domain()` when domain has multiple A records. Logic appears to handle it (dedups with `list(set(...))`), but edge case: what if some resolve and some don't mid-resolution?
- Files: `images/base/init-firewall.py` lines 210-227
- Risk: Partial DNS failures may result in incomplete firewall rules without error
- Priority: Medium

**GitHub API fetch with pagination:**
- What's not tested: `fetch_github_ips()` assumes GitHub API returns all IP ranges in single response. GitHub API response has no indication of truncation or pagination
- Files: `images/base/init-firewall.py` lines 173-207
- Risk: If GitHub adds many IP ranges, some may be silently dropped. Firewall would block legitimate GitHub traffic
- Priority: High (GitHub IPs are critical for git operations)

**Policy with no domains or services:**
- What's not tested: Container startup with policy that has `{"services": [], "domains": []}`. Currently, verification will warn (line 403-404) but container still starts
- Files: `images/base/init-firewall.py` lines 364-405
- Risk: Container with network completely blocked except DNS/SSH might be confusing. Should probably be explicit error or different mode
- Priority: Low

**iptables rule conflicts:**
- What's not tested: Behavior when system already has conflicting iptables rules (e.g., from previous incomplete run or system policy)
- Files: `images/base/init-firewall.py` (flush_rules doesn't handle custom chains)
- Risk: If custom chains exist, flush_rules may fail leaving firewall in inconsistent state
- Priority: Medium

**Docker DNS restoration on multiple container restarts:**
- What's not tested: Running `dev-shell` multiple times after initial entrypoint. Docker DNS rules may be restored incorrectly on second call
- Files: `images/base/entrypoint.sh` (idempotency check on line 12), `images/base/init-firewall.py` lines 94-134
- Risk: Second restart may double-create chains causing errors
- Priority: Medium (affects development workflow when restarting)

---

*Concerns audit: 2026-03-23*
