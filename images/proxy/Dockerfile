FROM debian:bookworm-slim

RUN apt-get update && \
    apt-get install -y --no-install-recommends squid curl && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Build-time assertion: Debian bookworm squid package must include --with-openssl
# (required for ssl_bump peek/splice directives in squid.conf)
RUN squid -v 2>&1 | grep -q "with-openssl" || (echo "ERROR: squid missing --with-openssl" && exit 1)

COPY squid.conf /etc/squid/squid.conf
COPY allowlist.txt /etc/squid/allowlist.txt

RUN chmod 644 /etc/squid/squid.conf /etc/squid/allowlist.txt

EXPOSE 3128

# -N: foreground mode so Docker captures PID 1 and logs
# Logs route to stdout/stderr via access_log and cache_log in squid.conf
CMD ["squid", "-N", "-f", "/etc/squid/squid.conf"]
