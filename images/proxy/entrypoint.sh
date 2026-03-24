#!/bin/sh
# Make /dev/stdout and /dev/stderr accessible to the proxy user
# so squid can write its logs when running as non-root (uid proxy)
chmod 666 /dev/stdout /dev/stderr 2>/dev/null || true
exec squid -N -f /etc/squid/squid.conf "$@"
