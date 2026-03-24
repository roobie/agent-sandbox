#!/usr/bin/env bash
set -euo pipefail

PASS=0
FAIL=0

check() {
    local id="$1"
    local desc="$2"
    shift 2
    if "$@" >/dev/null 2>&1; then
        echo "PASS [$id] $desc"
        ((++PASS))
    else
        echo "FAIL [$id] $desc"
        ((++FAIL))
    fi
}

check_fail() {
    local id="$1"
    local desc="$2"
    shift 2
    if ! "$@" >/dev/null 2>&1; then
        echo "PASS [$id] $desc (expected failure confirmed)"
        ((++PASS))
    else
        echo "FAIL [$id] $desc (should have failed but succeeded)"
        ((++FAIL))
    fi
}

echo "=== Agent Sandbox Proxy Smoke Tests ==="
echo ""

# PROXY-01: Proxy container is running
check PROXY-01 "Proxy container is running" \
    bash -c "docker compose ps proxy | grep -q 'Up\|running'"

# PROXY-05: Sandbox has no direct internet (must fail without proxy)
check_fail PROXY-05 "Sandbox cannot reach internet directly (no proxy)" \
    docker compose exec -T agent-sandbox \
        curl --noproxy '*' -sf --connect-timeout 3 https://api.anthropic.com

# PROXY-06: Proxy env vars are set in sandbox
check PROXY-06 "HTTP_PROXY env var is set in sandbox" \
    bash -c "docker compose exec -T agent-sandbox env | grep -q 'HTTP_PROXY=http://proxy:3128'"

check PROXY-06 "HTTPS_PROXY env var is set in sandbox" \
    bash -c "docker compose exec -T agent-sandbox env | grep -q 'HTTPS_PROXY=http://proxy:3128'"

# PROXY-02 + PROXY-03: Allowlisted domain passes, blocked domain fails
check PROXY-02 "Allowed domain reaches proxy (github.com)" \
    docker compose exec -T agent-sandbox \
        curl -sf --max-time 10 -x http://proxy:3128 https://github.com

check_fail PROXY-02 "Blocked domain denied by proxy (notallowed.example.com)" \
    docker compose exec -T agent-sandbox \
        curl -sf --max-time 5 -x http://proxy:3128 https://notallowed.example.com

check PROXY-03 "SNI verification: proxy DNS resolves inside sandbox" \
    bash -c "docker compose exec -T agent-sandbox getent hosts proxy | grep -q proxy"

# PROXY-04: Multi-sandbox traffic appears in proxy access log
# Make a second request from sandbox to verify access log has entries
docker compose exec -T agent-sandbox curl -sf --max-time 10 -x http://proxy:3128 https://github.com >/dev/null 2>&1 || true
check PROXY-04 "Proxy access log shows CONNECT entries (multi-sandbox routing visible)" \
    bash -c "docker logs agent-sandbox-proxy 2>&1 | grep -q 'CONNECT'"

# PROXY-07: Health check — proxy service is healthy
check PROXY-07 "Proxy service health check passes" \
    bash -c "docker compose ps proxy | grep -q 'healthy'"

# MIG-01: init-firewall.py is absent from sandbox container
check MIG-01 "init-firewall.py is absent from sandbox container" \
    bash -c "docker compose exec -T agent-sandbox test ! -f /usr/local/bin/init-firewall.py"

# MIG-02: No NET_ADMIN or NET_RAW capabilities on sandbox container
check MIG-02 "Sandbox container has no NET_ADMIN capability" \
    bash -c "docker inspect agent-sandbox | python3 -c \"import json,sys; c=json.load(sys.stdin); caps=c[0]['HostConfig']['CapAdd']; exit(0 if caps is None or 'NET_ADMIN' not in caps else 1)\""

check MIG-02 "Sandbox container has no NET_RAW capability" \
    bash -c "docker inspect agent-sandbox | python3 -c \"import json,sys; c=json.load(sys.stdin); caps=c[0]['HostConfig']['CapAdd']; exit(0 if caps is None or 'NET_RAW' not in caps else 1)\""

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
