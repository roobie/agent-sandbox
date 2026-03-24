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

echo "=== Agent Sandbox Hardening Smoke Tests ==="
echo ""

# HARD-01: Rootfs is read-only (write to image layer fails)
check_fail HARD-01 "Rootfs is read-only (write to / fails)" \
    docker compose exec -T agent-sandbox bash -c "touch /hardening-test-ro"

# HARD-01: /tmp is writable tmpfs
check HARD-01 "/tmp is writable" \
    docker compose exec -T agent-sandbox bash -c "touch /tmp/hardening-test-$$ && rm /tmp/hardening-test-$$"

# HARD-01: /run is writable tmpfs
check HARD-01 "/run is writable" \
    docker compose exec -T agent-sandbox bash -c "touch /run/hardening-test-$$ && rm /run/hardening-test-$$"

# HARD-01: ReadonlyRootfs flag is set in inspect output
check HARD-01 "Docker inspect shows ReadonlyRootfs: true" \
    bash -c "docker inspect agent-sandbox | python3 -c \"import json,sys; c=json.load(sys.stdin); exit(0 if c[0]['HostConfig']['ReadonlyRootfs'] else 1)\""

# HARD-02: cap_drop=ALL applied; only SETUID/SETGID added back (needed for gosu user-switch in entrypoint)
# No network capabilities (NET_ADMIN, NET_RAW) or privilege-escalation capabilities should be present
check HARD-02 "No dangerous capabilities added (no NET_ADMIN, NET_RAW, SYS_ADMIN)" \
    bash -c "docker inspect agent-sandbox | python3 -c \"
import json,sys
c=json.load(sys.stdin)
caps=c[0]['HostConfig']['CapAdd'] or []
dangerous={'NET_ADMIN','NET_RAW','SYS_ADMIN','SYS_PTRACE','SYS_MODULE','ALL'}
bad=[cap for cap in caps if cap.upper() in dangerous]
exit(1 if bad else 0)
\""

# HARD-02: CapDrop contains ALL
check HARD-02 "CapDrop contains ALL" \
    bash -c "docker inspect agent-sandbox | python3 -c \"import json,sys; c=json.load(sys.stdin); drops=c[0]['HostConfig']['CapDrop'] or []; exit(0 if 'ALL' in drops else 1)\""

# HARD-02: no-new-privileges is set in SecurityOpt
check HARD-02 "no-new-privileges is set" \
    bash -c "docker inspect agent-sandbox | python3 -c \"import json,sys; c=json.load(sys.stdin); opts=c[0]['HostConfig']['SecurityOpt'] or []; exit(0 if any('no-new-priv' in o for o in opts) else 1)\""

# HARD-03: Default seccomp is active (not unconfined)
check HARD-03 "Default seccomp active (not unconfined)" \
    bash -c "docker inspect agent-sandbox | python3 -c \"import json,sys; c=json.load(sys.stdin); opts=c[0]['HostConfig']['SecurityOpt'] or []; exit(1 if any('seccomp=unconfined' in o for o in opts) else 0)\""

# HARD-04: Memory limit is non-zero
check HARD-04 "Memory limit is non-zero" \
    bash -c "docker inspect agent-sandbox | python3 -c \"import json,sys; c=json.load(sys.stdin); exit(0 if c[0]['HostConfig']['Memory'] > 0 else 1)\""

# HARD-04: CPU limit is non-zero
check HARD-04 "CPU limit is non-zero (NanoCpus)" \
    bash -c "docker inspect agent-sandbox | python3 -c \"import json,sys; c=json.load(sys.stdin); exit(0 if c[0]['HostConfig']['NanoCpus'] > 0 else 1)\""

# HARD-04: PID limit is non-zero
check HARD-04 "PID limit is non-zero" \
    bash -c "docker inspect agent-sandbox | python3 -c \"import json,sys; c=json.load(sys.stdin); exit(0 if c[0]['HostConfig']['PidsLimit'] > 0 else 1)\""

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
