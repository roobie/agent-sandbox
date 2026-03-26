# mise-en-place — Complete LLM Reference

> **Canonical URL:** https://mise.jdx.dev/
> **Pronounced:** "MEEZ ahn plahs"
> **Written in:** Rust
> **License:** MIT
> **Creator/Maintainer:** @jdx (Jeff Dickey)
> **Formerly known as:** `rtx`

## What mise Is

mise is a unified development environment manager. It does three things:

1. **Dev Tools** — A polyglot tool/runtime version manager. Replaces asdf, nvm, pyenv, rbenv, tfenv, etc.
2. **Environments** — Per-directory environment variable management. Replaces direnv.
3. **Tasks** — A project task runner. Replaces make, npm scripts, etc.

All three are configured through a single `mise.toml` file (or compatible legacy formats), and they compose together: tasks automatically inherit the correct tool versions and env vars.

---

## Installation

```bash
# Recommended: install script
curl https://mise.run | sh

# Homebrew (macOS/Linux)
brew install mise

# Cargo
cargo install mise

# Other: see https://mise.jdx.dev/getting-started.html
```

### Shell Activation

After installing, hook mise into your shell. This is required for automatic tool switching on directory change:

```bash
# Bash
echo 'eval "$(~/.local/bin/mise activate bash)"' >> ~/.bashrc

# Zsh
echo 'eval "$(~/.local/bin/mise activate zsh)"' >> ~/.zshrc

# Fish
echo '~/.local/bin/mise activate fish | source' >> ~/.config/fish/config.fish

# PowerShell
echo '~/.local/bin/mise activate pwsh | Out-String | Invoke-Expression' >> ~/.config/powershell/Microsoft.PowerShell_profile.ps1
```

When activated, every prompt invocation calls `mise hook-env` to update the environment. This exits early if nothing changed — it's very fast.

### Alternative: Shims

Instead of shell activation, mise can use shims (lightweight wrapper scripts in `~/.local/share/mise/shims/`). Shell activation is generally preferred because `which node` returns the real binary path (not a shim), and there's zero overhead per invocation.

---

## Configuration Files

### mise.toml (Primary Format)

The main config format. Can be named `mise.toml` or `.mise.toml`. Place it at the project root.

```toml
min_version = "2024.1.0"   # optional: require minimum mise version

[tools]
node = "22"                 # latest node 22.x
python = "3.12"             # latest python 3.12.x
go = "latest"               # always latest stable
ruby = ["3.3.0", "3.2.2"]  # multiple versions; first is default
terraform = "1.7.0"         # exact pin
java = "{{env.JAVA_VERSION}}" # version from env var
rust = "stable"             # channel name

[env]
NODE_ENV = "development"
DATABASE_URL = "postgresql://localhost/devdb"
PATH = "./node_modules/.bin:{{env.PATH}}"   # prepend to PATH
_.file = ".env.local"       # load vars from dotenv file
_.secret = ["API_KEY"]      # prompt for secrets on first use

[tasks.build]
description = "Build the project"
run = "cargo build --release"

[tasks.test]
description = "Run tests"
run = "cargo test"
depends = ["build"]

[settings]
experimental = true
jobs = 4
```

### .tool-versions (asdf Compatibility)

mise reads asdf's `.tool-versions` files natively:

```
node 22.0.0
python 3.12.0
ruby 3.3.0
```

### Idiomatic Version Files

mise also reads single-tool version files: `.node-version`, `.nvmrc`, `.python-version`, `.ruby-version`, etc. These are disabled by default; enable per-tool via settings.

---

## Configuration Hierarchy

mise discovers config files by walking up the directory tree and merging them hierarchically. More specific (closer to CWD) settings override broader ones:

```
/
├── etc/mise/
│   ├── conf.d/*.toml          # System-wide fragments (highest precedence)
│   ├── config.toml            # System defaults
│   └── config.<env>.toml      # Env-specific system config
└── home/user/
    ├── .config/mise/
    │   ├── conf.d/*.toml      # User fragments
    │   ├── config.toml        # Global user config
    │   ├── config.<env>.toml  # Env-specific user config
    │   ├── config.local.toml  # User-local overrides
    │   └── config.<env>.local.toml
    └── work/
        ├── mise.toml          # Work-wide settings
        └── myproject/
            ├── mise.toml          # Project config
            ├── mise.local.toml    # Local overrides (gitignored)
            ├── mise.<env>.toml    # Env-specific project config
            └── backend/
                └── mise.toml      # Sub-directory config
```

Key rules:
- `mise.local.toml` files are for personal/local overrides and should be `.gitignore`d.
- Environment-specific files (like `mise.development.toml`) load when `MISE_ENV` is set.
- `[tools]` sections merge by overriding per-tool. `[env]` sections merge additively by default.
- Use `mise config ls` to see which config files are active.

### Trust System

Config files can execute arbitrary code (via tasks, hooks, `_.source`). mise requires explicit trust before running untrusted configs:

```bash
mise trust              # trust the mise.toml in CWD
mise trust mise.toml    # trust a specific file
```

In CI, you can set `MISE_TRUSTED_CONFIG_PATHS` or use `mise trust --quiet`.

---

## Dev Tools (Version Management)

### Core Concepts

- **`mise use <tool>@<version>`** — The primary command. Installs the tool AND adds it to `mise.toml`.
- **`mise install`** — Installs all tools listed in config files (does NOT activate them; they must be in a config file).
- **`mise ls`** — List installed tool versions.
- **`mise upgrade`** / **`mise up`** — Upgrade tools within their version constraints. `--bump` upgrades and updates `mise.toml`.
- **`mise x <tool>@<version> -- <command>`** — Run a one-off command with a specific tool version, without persisting to config.
- **`mise where <tool>@<version>`** — Print the install directory for a tool version.
- **`mise which <tool>`** — Print the path to the binary that would be used.

### Version Specifiers

```toml
[tools]
node = "22"           # Fuzzy: latest 22.x.x
node = "22.5.0"       # Exact pin
node = "latest"       # Always latest stable
node = "lts"          # Latest LTS (language-specific)
node = "sub-1:latest" # One version behind latest
node = "path:/opt/node" # Use a pre-installed binary at a custom path
```

### Backends

mise supports multiple backends (installation methods). Each backend knows how to list versions, install, and uninstall tools.

**Priority order for choosing a backend:**
1. Explicit backend prefix: `mise use aqua:golangci/golangci-lint`
2. Environment variable override: `MISE_BACKENDS_<TOOL>=...`
3. Registry lookup (default): `mise use node` → resolved via registry
4. Core tools: Built-in support for node, python, go, java, ruby, etc.
5. Fallback: Suggests available backends

**Backend types (in order of general preference):**

| Backend | Description | Example |
|---------|-------------|---------|
| **core** | Built-in support for major languages (node, python, go, java, ruby, etc.). Best performance. | `core:node` |
| **aqua** | Uses the aqua registry. Good security, many tools. Preferred for non-core tools. | `aqua:hashicorp/terraform` |
| **github** | Downloads releases directly from GitHub. For tools not in aqua. | `github:owner/repo` |
| **gitlab** | Same as github but for GitLab-hosted tools. | `gitlab:owner/repo` |
| **npm** | Installs npm packages globally. Requires node. | `npm:prettier` |
| **pipx** | Installs Python CLI tools in isolated envs. Requires python. | `pipx:black` |
| **go** | `go install` for Go tools. Requires go. | `go:golang.org/x/tools/gopls` |
| **cargo** | `cargo install` for Rust tools. Requires rust. | `cargo:ripgrep` |
| **asdf** | Legacy asdf plugin ecosystem. Linux/macOS only. | `asdf:postgres` |
| **vfox** | Modern plugin system. | `vfox:version-fox/vfox-elixir` |
| **http** | Download from arbitrary URLs with platform-specific configs. | `http:my-tool` |
| **spm** | Swift Package Manager. | `spm:nicklockwood/SwiftFormat` |

### Registry

The registry maps short names to full backend specifications:
- `node` → `core:node`
- `terraform` → `aqua:hashicorp/terraform`
- `watchexec` → `aqua:watchexec/watchexec`

View the registry: `mise registry`

Override for a project:
```toml
[tool_alias]
go = "core:go"
terraform = "aqua:hashicorp/terraform"
```

### Tool Options

```toml
[tools."http:my-tool"]
version = "1.0.0"

[tools."http:my-tool".platforms]
macos-x64 = { url = "https://example.com/my-tool-macos.tar.gz", checksum = "sha256:abc123" }
linux-x64 = { url = "https://example.com/my-tool-linux.tar.gz", checksum = "sha256:def456" }
```

---

## Environment Variables

mise replaces direnv for managing per-project env vars.

```toml
[env]
# Static values
NODE_ENV = "development"
API_URL = "http://localhost:3000"

# Reference other env vars via templates
DATABASE_NAME = "app_{{env.USER}}"

# Modify PATH
PATH = "./node_modules/.bin:{{env.PATH}}"

# Load from dotenv files
_.file = [".env", ".env.local"]

# Source a shell script
_.source = "./scripts/set-env.sh"

# Prompt for secrets (stored locally, never committed)
_.secret = ["API_KEY", "DATABASE_PASSWORD"]
```

Env vars are automatically set when entering the directory and unset when leaving (with shell activation). Templates use the Tera template engine.

### Environment-specific Configuration

The general principle: **`mise.toml` defines *what* env vars are needed (and how to load them), but not the values themselves.** Values come from the environment — a local `.env` file on a dev machine, platform-provided env vars in production.

**Layer 1: `mise.toml` (committed)** — declares structure, defaults, and loading strategy:

```toml
[env]
_.file = ".env"                    # load values from local dotenv (gitignored)
PATH = "./node_modules/.bin:{{env.PATH}}"  # structural, same everywhere
```

**Layer 2: `.env` (gitignored)** — local dev values:

```bash
DATABASE_URL=postgresql://localhost/myapp_dev
SOME_ENV=DEV
API_KEY=dev-key-123
```

**Layer 3: `.env.example` (committed)** — documents required vars for humans:

```bash
DATABASE_URL=    # PostgreSQL connection string
SOME_ENV=        # DEV, STAGING, PROD
API_KEY=         # API key for external service
```

**Layer 4: `mise.local.toml` (gitignored)** — personal overrides that go beyond env vars (e.g., tool versions, extra tasks):

```toml
[env]
SOME_ENV = "DEV"           # alternative to .env for mise-managed vars
DEBUG = "true"             # personal debug flag

[tools]
python = "3.13"            # testing against newer version locally
```

**In production**, there is no `.env` or `mise.local.toml`. The deployment platform (Docker, CI, systemd, cloud) sets env vars directly. Tasks in `mise.toml` reference `$SOME_ENV` and it just works regardless of where the value came from.

The key insight: `mise.toml` is the *schema*, `.env` / `mise.local.toml` are *local instances* of that schema, and production provides its own instance through platform mechanisms.

### Environment Profiles

For cases where you want entirely different config sets (not just env var values), use `MISE_ENV`:

```bash
export MISE_ENV=development
# or
mise -E production run deploy
```

This loads `mise.development.toml` or `mise.production.toml` in addition to the base config. This is heavier than the `.env` approach — use it when you need different tools, tasks, or structural config per environment, not just different variable values.

---

## Tasks

Tasks are commands defined in `mise.toml` or as standalone script files. They automatically inherit the mise environment (tools on PATH + env vars).

### TOML-Defined Tasks

```toml
# Shorthand
tasks.hello = "echo hello"

# Full form
[tasks.build]
description = "Build the CLI"
run = "cargo build --release"
sources = ["Cargo.toml", "src/**/*.rs"]   # skip if unchanged
outputs = ["target/release/mycli"]         # check this for freshness
depends = ["codegen"]                      # run codegen first

[tasks.test]
description = "Run tests"
run = ["cargo test", "cargo clippy"]       # array = sequential commands
env = { RUST_BACKTRACE = "1" }             # task-specific env vars
dir = "{{cwd}}"                            # run from user's CWD

[tasks.deploy]
confirm = "Are you sure you want to deploy?"
depends = ["build", "test"]
run = "scripts/deploy.sh"
```

### File Tasks

Tasks can also be standalone scripts in a `mise-tasks/` directory (or configured `task_config.dir`):

```bash
#!/usr/bin/env bash
# mise-tasks/build
#MISE description="Build the project"
#MISE depends=["lint"]
#MISE sources=["src/**/*"]
#MISE outputs=["dist/**/*"]

set -euo pipefail
cargo build --release
```

File tasks support any language via shebang:

```python
#!/usr/bin/env python3
#MISE description="Generate docs"
import subprocess
subprocess.run(["mkdocs", "build"])
```

### Running Tasks

```bash
mise run build           # run a task
mise build               # shorthand (if no conflict with a mise command)
mise run build test      # run multiple tasks
mise run build -- --flag # pass args after --
mise tasks               # list available tasks (interactive picker if no args)
mise tasks ls            # list all tasks
```

### Task Dependencies & Parallelism

Dependencies are run before the task. By default, independent dependencies run in parallel:

```toml
[tasks.deploy]
depends = ["build", "test"]    # build and test run in parallel, then deploy
run = "scripts/deploy.sh"

[tasks.grouped]
run = [
  { task = "t1" },              # run t1 first
  { tasks = ["t2", "t3"] },    # then t2 and t3 in parallel
  "echo done",                  # then this
]
```

Other dependency types:
- `depends` — must succeed before this task runs
- `wait_for` — must complete (success or failure) before this task runs
- `depends_post` — run after this task completes

### Source/Output Caching

When `sources` and `outputs` are specified, mise skips re-running if outputs are newer than sources (last-modified timestamps).

### Watch Mode

```bash
mise watch -t test         # re-run test task on file changes
mise watch -t build -t test  # watch multiple tasks
```

Uses `watchexec` under the hood (install it with `mise use -g watchexec@latest`).

### Task Arguments with `usage`

The `usage` field is the recommended way to define task arguments. It provides declarative syntax with auto-generated `--help` output and shell completions.

Arguments are available as `usage_`-prefixed env vars and as Tera template variables via the `usage` map.

```toml
[tasks.deploy]
description = "Deploy application"
usage = '''
arg "<environment>" help="Target environment" {
  choices "dev" "staging" "prod"
}
flag "-v --verbose" help="Enable verbose output"
flag "--region <region>" help="AWS region" default="us-east-1" env="AWS_REGION"
'''
run = '''
echo "Deploying to ${usage_environment?} in ${usage_region?}"
[[ "${usage_verbose?}" == "true" ]] && set -x
./deploy.sh "${usage_environment?}" "${usage_region?}"
'''
```

Tera template access (alternative to env vars):

```toml
[tasks.deploy]
usage = '''
arg "<environment>" help="Target environment"
flag "--region <region>" default="us-east-1"
'''
run = '''
echo "Deploying to {{ usage.environment }} in {{ usage.region }}"
'''
```

#### Positional arguments (`arg`)

```kdl
arg "<name>" help="Description"               // Required
arg "[name]" help="Description"               // Optional
arg "<file>" default="config.toml"            // With default
arg "[files]" var=#true                       // Variadic (0+)
arg "<files>" var=#true var_min=2             // Variadic with minimum
arg "<token>" env="API_TOKEN"                 // Backed by env var
arg "<level>" {                               // With choices
  choices "debug" "info" "warn" "error"
}
```

Priority: CLI argument > Environment variable > Default value

#### Flags (`flag`)

```kdl
flag "-f --force"                             // Boolean
flag "-v --verbose" count=#true               // Countable (-vvv = 3)
flag "-o --output <file>" help="Output file"  // With value
flag "--port <port>" default="8080"           // With default
flag "--color" negate="--no-color" default=#true  // Negatable
flag "--color <when>" {                       // With choices
  choices "auto" "always" "never"
  default "auto"
}
```

#### Custom completions

```kdl
arg "<plugin>"
complete "plugin" run="mise plugins ls"
```

#### Bash variable expansion patterns

| Syntax | Behavior | Use case |
|--------|----------|----------|
| `${var?}` | Error if unset | Required args, flags with defaults in usage |
| `${var:?}` | Error if unset/empty | Ensure non-empty |
| `${var:-default}` | Default if unset | Boolean flags without `default=` |
| `${var:+value}` | Use value if set | Conditional flag passing |

#### Variadic args with spaces

```bash
eval "files=($usage_files)"
for f in "${files[@]}"; do
  process "$f"
done
```

#### File task headers

For file tasks, define arguments in `#MISE` or `#USAGE` comment headers:

```bash
#!/usr/bin/env bash
#MISE description "Deploy application"
#USAGE arg "<environment>" help="Deployment environment" {
#USAGE   choices "dev" "staging" "prod"
#USAGE }
#USAGE flag "--dry-run" help="Preview changes without deploying"

ENVIRONMENT="${usage_environment?}"
DRY_RUN="${usage_dry_run:-false}"
```

> **Note:** The old Tera template method (`{{arg(name="file")}}`, `{{option()}}`, `{{flag()}}`) is **deprecated** and will be removed in mise 2026.11.0. Migrate to the `usage` field.

---

## Hooks

Hooks run scripts automatically during directory changes (requires shell activation):

```toml
[hooks]
# Run every time the directory changes
cd = "echo 'directory changed'"

# Run when entering this project (once)
enter = "echo 'entered project'"

# Run when leaving this project
leave = "echo 'left project'"

# Run before/after tool installation (no activation required)
preinstall = "echo 'about to install'"
postinstall = "echo 'just installed: $MISE_INSTALLED_TOOLS'"
```

### Watch Files Hook

```toml
[[watch_files]]
patterns = ["src/**/*.rs"]
run = "cargo build"

[[watch_files]]
patterns = ["*.md"]
task = "docs"   # run a defined task instead
```

Hook environment variables:
- `MISE_ORIGINAL_CWD` — User's current directory
- `MISE_PROJECT_ROOT` — Project root
- `MISE_PREVIOUS_DIR` — Previous directory (on cd)
- `MISE_INSTALLED_TOOLS` — JSON array of installed tools (postinstall only)
- `MISE_WATCH_FILES_MODIFIED` — Colon-separated modified file list (watch_files only)

---

## Key CLI Commands Reference

| Command | Purpose |
|---------|---------|
| `mise use <tool>@<version>` | Install and activate a tool (updates `mise.toml`) |
| `mise use -g <tool>@<version>` | Same but for global config (`~/.config/mise/config.toml`) |
| `mise install` | Install all tools from config files |
| `mise ls` | List installed tools and their active versions |
| `mise ls-remote <tool>` | List available remote versions for a tool |
| `mise upgrade [tool]` | Upgrade tool(s) within version constraints |
| `mise upgrade --bump [tool]` | Upgrade and update version in `mise.toml` |
| `mise x <tool>@<ver> -- <cmd>` | One-off exec with a specific version |
| `mise run <task>` | Run a task |
| `mise watch -t <task>` | Watch mode for a task |
| `mise env` | Print the mise environment (for debugging) |
| `mise where <tool>@<ver>` | Print install directory |
| `mise which <binary>` | Print resolved binary path |
| `mise config ls` | List active config files |
| `mise settings` | View/set configuration settings |
| `mise trust` | Trust a config file |
| `mise self-update` | Update mise itself |
| `mise doctor` | Diagnose issues |
| `mise registry` | View the tool registry |
| `mise edit` | Interactive TUI config editor |
| `mise generate` | Generate git hooks, GitHub actions, task docs, etc. |

---

## Settings

Settings go in `[settings]` in any config file or are set via `mise settings <key>=<value>`. Important ones:

```toml
[settings]
experimental = true           # enable experimental features
jobs = 4                      # parallel installation jobs
auto_install = true           # auto-install missing tools on `mise x` / `mise run`
legacy_version_file = true    # read .nvmrc, .python-version, etc.
paranoid = false              # extra security: require trust for all configs
disable_backends = ["asdf"]   # disable specific backends
always_keep_download = false  # keep downloaded archives
verbose = false               # verbose output
```

Environment variables override settings with the `MISE_` prefix:
- `MISE_NODE_VERSION=20` — Force node version
- `MISE_ENV=production` — Set environment profile
- `MISE_TRUSTED_CONFIG_PATHS=/path1:/path2` — Auto-trust paths
- `MISE_DATA_DIR=~/.mise` — Override data directory
- `MISE_LOG_LEVEL=debug` — Logging verbosity

---

## Important Directories

| Path | Purpose |
|------|---------|
| `~/.local/share/mise/installs/` | Where tools are installed |
| `~/.local/share/mise/shims/` | Shim scripts (if using shims mode) |
| `~/.local/share/mise/downloads/` | Downloaded archives/tarballs |
| `~/.config/mise/config.toml` | Global user config |
| `~/.local/bin/mise` | mise binary (default install location) |

---

## Lockfiles

mise supports lockfiles (`mise.lock`) to pin exact resolved versions:

```bash
mise install          # creates/updates mise.lock
```

This ensures reproducible builds across machines. The lockfile pins the exact version that a fuzzy spec like `node = "22"` resolved to.

---

## CI/CD Usage

### GitHub Actions

```yaml
# .github/workflows/test.yml
name: Tests
on: [push, pull_request]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Install mise
        uses: jdx/mise-action@v2
        with:
          install: true
      - name: Install tools
        run: mise install
      - name: Run tests
        run: mise run test
```

### GitLab CI

```yaml
test:
  image: ubuntu:latest
  before_script:
    - curl https://mise.run | sh
    - eval "$(mise activate bash)"
    - mise install
  script:
    - mise run test
```

### CI Best Practices

- Pin tool versions exactly in CI configs for reproducibility.
- Use lockfiles (`mise.lock`).
- Cache `$MISE_DATA_DIR` for faster runs.
- Disable asdf/vfox backends if not needed: `MISE_DISABLE_BACKENDS=asdf,vfox`.
- Consider a separate `mise.ci.toml` for CI-specific settings.

---

## Security

- **Trust system:** Untrusted config files won't execute tasks or hooks.
- **SLSA provenance verification:** Enable with `settings.slsa_verification = true`.
- **Paranoid mode:** `settings.paranoid = true` requires explicit trust for every config file and re-trust on changes.
- **Checksums:** The aqua and http backends support checksum verification.
- **Disable legacy plugins:** `settings.disable_backends = ["asdf"]` if you don't need them (asdf plugins can run arbitrary shell scripts).

---

## Migration from Other Tools

### From asdf

mise reads `.tool-versions` natively. You can start using mise immediately:

```bash
mise install           # reads existing .tool-versions
mise current --toml    # optionally generate a mise.toml from current state
```

### From nvm

mise reads `.nvmrc` automatically:

```bash
mise use node@$(cat .nvmrc)   # optional explicit migration
```

### From pyenv

mise reads `.python-version`:

```bash
mise use python@$(cat .python-version)
```

### From direnv

Replace `.envrc` with `[env]` in `mise.toml`. mise supports `_.file` to load `.env` files, `_.source` to source shell scripts.

---

## Common Patterns

### Monorepo with Multiple Services

```
monorepo/
├── mise.toml              # shared tools (e.g., node, python)
├── services/
│   ├── api/
│   │   └── mise.toml      # api-specific: python = "3.12"
│   └── frontend/
│       └── mise.toml      # frontend-specific: node = "22"
```

### Pre-commit Hooks

```bash
mise generate git-pre-commit    # creates .git/hooks/pre-commit that runs a mise task
```

### Bootstrap for Teams

```bash
mise generate bootstrap         # creates a bootstrap script for teammates
mise generate task-stubs        # creates bin/ stubs that call mise tasks
```

Team members can run `bin/build` etc. without formally installing mise — the bootstrap script handles it.

### Combined Example

```toml
# mise.toml
[tools]
node = "22"
python = "3.12"
terraform = "1"

[env]
NODE_ENV = "development"
TF_WORKSPACE = "dev"
PATH = "./node_modules/.bin:{{env.PATH}}"
_.file = ".env.local"

[tasks.dev]
description = "Start dev server"
run = "npm run dev"

[tasks.test]
description = "Run all tests"
run = ["npm test", "pytest tests/"]

[tasks.plan]
description = "Terraform plan"
run = """
terraform init
terraform plan
"""

[tasks.deploy]
description = "Deploy everything"
confirm = "Deploy to production?"
depends = ["test", "plan"]
run = "scripts/deploy.sh"
```

---

## Templating

mise uses the [Tera](https://keats.github.io/tera/) template engine in config files. Available context:

- `{{env.VAR}}` — Environment variables
- `{{cwd}}` — Current working directory
- `{{config_root}}` — Directory containing the mise.toml
- `{{mise.arch}}` — System architecture
- `{{mise.os}}` — Operating system

Example:
```toml
[env]
DATABASE_NAME = "app_{{env.USER}}"
RUST_TARGET = "{{mise.arch}}-unknown-linux-gnu"
```

---

## Troubleshooting

```bash
mise doctor           # check for common issues
mise config ls        # see which config files are active
mise env              # print the computed environment
mise ls               # see what's installed and active
mise settings         # view current settings
mise --version        # check mise version
MISE_LOG_LEVEL=debug mise install  # verbose debugging
```

---

## Key Differences from asdf

| Feature | asdf | mise |
|---------|------|------|
| Language | Bash | Rust (much faster) |
| PATH strategy | Shims only | PATH injection (default) + optional shims |
| Config format | `.tool-versions` only | `mise.toml` (TOML) + `.tool-versions` compat |
| Env vars | No | Yes (replaces direnv) |
| Task runner | No | Yes (replaces make/npm scripts) |
| Plugin install | Manual `asdf plugin add` | Automatic on first use |
| Windows support | No | Yes |
| Fuzzy versions | Limited | `latest`, `lts`, `sub-1:latest`, templates |
| Watch mode | No | Yes (`mise watch`) |
| Hooks | No | Yes (cd, enter, leave, pre/postinstall) |
| Security | None | Trust system, SLSA verification, checksums |

