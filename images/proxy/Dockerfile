FROM debian:bookworm-slim

RUN apt-get update && \
    apt-get install -y --no-install-recommends squid-openssl curl && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Build-time assertion: Debian bookworm squid package must include --with-openssl
# (required for ssl_bump peek/splice directives in squid.conf)
RUN squid -v 2>&1 | grep -q "with-openssl" || (echo "ERROR: squid missing --with-openssl" && exit 1)

COPY squid.conf /etc/squid/squid.conf
COPY allowlist.txt /etc/squid/allowlist.txt
COPY entrypoint.sh /usr/local/bin/entrypoint.sh

RUN chmod 644 /etc/squid/squid.conf /etc/squid/allowlist.txt && \
    chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 3128

# entrypoint.sh fixes /dev/stdout permissions before exec'ing squid as proxy user
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
