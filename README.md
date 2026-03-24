# Agent Sandbox

Run AI coding agents in a locked-down local sandbox with:

- Minimal filesystem access (only your repo + project-scoped agent state)
- Restricted outbound network (Squid proxy with domain allowlist via SNI peek/splice)
- Reproducible environments (Debian container with pinned dependencies)

Target platform: [Colima](https://github.com/abiosoft/colima) + [Docker Engine](https://docs.docker.com/engine/) on Apple Silicon. Should work on any Docker-compatible runtime.

## What it does

Creates a sandboxed environment for Claude Code that:

- Routes all outbound traffic through a shared Squid proxy
- Allows only domains listed in `config/allowlist.txt` (HTTPS verified via SNI peek/splice, no TLS decryption)
- Runs as non-root user with all capabilities dropped and read-only rootfs
- Persists Claude credentials and configuration in a Docker volume across container rebuilds

## Quick start (macOS + Colima)

### 1. Install prerequisites

You need docker, docker-compose, and mise installed. We have tested with Colima + Docker Engine; this should work with Docker Desktop for Mac or Podman as well.

```bash
brew install colima docker docker-compose mise
colima start --cpu 4 --memory 8 --disk 60
```

If you previously used Docker Desktop, set your Docker credential helper to `osxkeychain` (not `desktop`) in `~/.docker/config.json`.

### 2. Clone the repo

```bash
git clone https://github.com/mattolson/agent-sandbox.git
cd agent-sandbox
```

### 3. Start the proxy

The shared Squid proxy must be running before starting any sandbox containers:

```bash
mise run proxy:start
```

This starts a single Squid proxy container that all sandbox instances share. It only needs to run once per host session.

### 4. Run a sandbox

```bash
mise run sandbox:run --workspace /path/to/your/project
```

The sandbox container joins the internal Docker network, with all outbound traffic routed through the proxy.

### 5. Enter the sandbox

```bash
docker exec -it agent-sandbox-default zsh
```

### 6. Authenticate Claude Code (first time only)

From inside the container:

```bash
claude
```

This triggers the OAuth flow:

1. Copy the URL and open it in your browser
2. Authorize the application
3. Paste the authorization code back into the terminal
4. Type `/exit` to close Claude

Credentials persist in a Docker volume. You only need to do this once per project.

### 7. Run Claude Code

From inside the container:

```bash
claude
# or as a shortcut for `claude --dangerously-skip-permissions`:
yolo-claude
```

### 8. Stop the sandbox when done

```bash
mise run sandbox:stop
```

This stops and removes the sandbox container. The diff of your workspace is shown on exit.

## Network policy

Outbound traffic is filtered by a Squid proxy using domain-based ACLs. The allowlist lives at `config/allowlist.txt`.

### Allowlist format

One domain per line. A leading dot matches the domain and all subdomains (e.g., `.github.com` matches `github.com`, `api.github.com`, `raw.githubusercontent.com`).

```
# Example entries
.github.com
.api.anthropic.com
.pypi.org
```

### Default allowlist

The default `config/allowlist.txt` includes:

- GitHub (`.github.com`, `.githubusercontent.com`)
- Claude Code (`.api.anthropic.com`, `.statsig.anthropic.com`, `.statsig.com`, `.sentry.io`)
- Package registries (`.pypi.org`, `.npmjs.org`, `.crates.io`, `.proxy.golang.org`, and others)
- Runtime downloads for mise-managed tools (`.nodejs.org`, `.static.rust-lang.org`, `.bun.sh`, etc.)

### Customizing the allowlist

Edit `config/allowlist.txt` and restart the proxy:

```bash
# Add your domains to config/allowlist.txt, then:
mise run proxy:stop
mise run proxy:start
```

The allowlist must live outside the workspace. If the agent could modify it and restart the proxy, it could allow exfiltration to arbitrary destinations.

## How it works

Sandbox containers join an internal Docker network (`sandbox-internal`) with no direct internet access. A shared Squid proxy bridges to the external network:

1. `HTTP_PROXY` and `HTTPS_PROXY` env vars route all container traffic through Squid at `proxy:3128`
2. Squid uses SNI peek/splice to inspect the destination hostname from the TLS ClientHello without decrypting the connection
3. Destinations matching `config/allowlist.txt` are spliced through; all others receive a `TCP_DENIED` response
4. Access logs stream to `docker logs agent-sandbox-proxy` for audit

No TLS decryption. No CA cert injection. No certificate pinning breakage.

## Security notes

This project reduces risk but does not eliminate it. Local dev is inherently best-effort sandboxing.

Key principles:

- Minimal mounts: only the repo workspace + project-scoped agent state
- Prefer short-lived credentials (SSO/STS) and read-only IAM roles
- All capabilities dropped (`--cap-drop=ALL`), read-only rootfs, `no-new-privileges`
- Egress enforced at the network layer via Squid proxy, not by trusting the agent
- Proxy enforcement cannot be bypassed by the agent — the agent container has no direct internet path

## Roadmap

See [`.planning/ROADMAP.md`](./.planning/ROADMAP.md) for the full phased development plan.

## Contributing

PRs welcome for:

- New agent support
- Improved network policies
- Documentation and examples

Please keep changes agent-agnostic where possible and compatible with Colima on macOS.

## Security issues

If you find a sandbox escape or bypass:

- Open a GitHub Security Advisory (preferred), or
- Open an issue with minimal reproduction details

## License

[MIT License](./LICENSE)
