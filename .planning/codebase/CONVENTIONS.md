# Coding Conventions

**Analysis Date:** 2026-03-23

## Naming Patterns

**Files:**
- Lowercase with hyphens for shell scripts: `entrypoint.sh`, `init-firewall.py`
- Snake_case for Python modules: `build.py`, `init-firewall.py`
- Constants in UPPERCASE_WITH_UNDERSCORES: `DEFAULT_POLICY_FILE`, `IPSET_NAME`, `GITHUB_META_URL`
- Environment variables referenced in UPPERCASE: `TZ`, `PYTHON_VERSION`, `POLICY_FILE`

**Functions:**
- Snake_case for all function names: `run_docker_build()`, `validate_ipv4()`, `fetch_github_ips()`
- Verb-based naming for functions that perform actions: `load_policy()`, `flush_rules()`, `create_ipset()`
- Prefixes for related operations: `run_cmd()`, `run_cmd_unchecked()` for subprocess helpers
- Boolean functions start with `validate_` or are named as predicates: `validate_ipv4()`, `validate_cidr()`

**Variables:**
- Snake_case for all variable names: `build_args`, `host_ip`, `host_network`, `docker_dns`
- Temporary variables follow the same pattern: `kv` in comprehensions, `ips` for lists
- Loop variables are descriptive: `for key, value in build_args.items()` rather than abbreviated

**Types:**
- Use uppercase camelCase for class names: `FirewallError`
- Type annotations use modern Python: `dict[str, str]` (Python 3.9+) not `Dict[str, str]`
- Import typing from `typing` module: `List`, `Set`, `Optional` for type hints in function signatures

## Code Style

**Formatting:**
- No detected linter/formatter (no `.eslintrc`, `.prettierrc`, `ruff.toml`)
- Line length appears to be soft-wrapped around 88-100 characters
- Consistent 4-space indentation throughout Python files
- Blank lines separate logical sections within functions

**Linting:**
- No detected automatic linting configuration
- Manual style appears consistent with PEP 8

## Import Organization

**Order:**
1. Standard library imports first: `import os`, `import json`, `import sys`, `import subprocess`
2. Standard library typing/data imports: `from typing import List, Optional, Set`
3. Specialized standard library imports: `from ipaddress import ip_address, ip_network, collapse_addresses`
4. Third-party imports: None detected (only stdlib)
5. Local imports: `from pathlib import Path`

**Example from `init-firewall.py`:**
```python
import json
import os
import re
import socket
import subprocess
import sys
import urllib.request
from ipaddress import ip_address, ip_network, collapse_addresses
from typing import List, Optional, Set
```

**Path Aliases:**
- No path aliases detected; imports use full paths
- Relative imports not used in this codebase

## Error Handling

**Patterns:**
- Custom exception class: `FirewallError(Exception)` defined at module level in `init-firewall.py`
- Specific exception catching: `except json.JSONDecodeError as e:`, `except socket.gaierror as e:`
- Broad exception catching with re-raise for specialized handling: `except Exception as e: raise FirewallError(...)`
- Errors are wrapped in custom exceptions with descriptive messages: `raise FirewallError(f"Policy file not found: {path}")`
- Functions return exit codes: `main()` returns `0` on success, `1` on failure
- Subprocess errors captured and wrapped: `subprocess.run()` with `capture_output=True, text=True`

**Example patterns:**
```python
# Custom exception for domain-specific errors
class FirewallError(Exception):
    """Custom exception for firewall configuration errors."""
    pass

# Specific error handling with re-raise
try:
    policy = json.load(f)
except json.JSONDecodeError as e:
    raise FirewallError(f"Invalid JSON in policy file: {e}")

# Ignoring expected duplicate errors
try:
    run_cmd(["ipset", "add", IPSET_NAME, ip_or_cidr])
except FirewallError as e:
    msg = f"{e}".lower()
    if "already" in msg and "added" in msg:
        return  # silently ignore duplicates
    raise
```

## Logging

**Framework:** `print()` to stdout for normal messages, `print(..., file=sys.stderr)` for errors

**Patterns:**
- Status messages: `print(f"Building {tag}...")`
- Detailed progress: `print(f"  {key}={value}")` with indentation
- Informational output: `print("Firewall configuration complete")`
- Error output to stderr: `print(f"ERROR: {e}", file=sys.stderr)`
- No structured logging or log levels detected

**Logging examples from `init-firewall.py`:**
```python
print(f"Using policy file: {path}")
print("Fetching GitHub IP ranges...")
print("Processing GitHub IPs...")
print(f"  Adding GitHub range {cidr}")
print("Firewall configuration complete")
print(f"ERROR: {e}", file=sys.stderr)
print(f"FATAL: Unexpected error: {e}", file=sys.stderr)
```

## Comments

**When to Comment:**
- Module-level docstrings describe script purpose: `"""Agent Sandbox Firewall Initialization\n\nReads policy.json and configures...`
- Function docstrings document public functions: One-line descriptions for simple utilities
- Inline comments explain non-obvious logic or intent: "Skip IPv6", "ipset usually says it's already added", "silently ignore duplicates"
- TODO/FIXME not used (none detected in codebase)

**JSDoc/TSDoc:**
- Not applicable; uses Python docstrings instead
- Docstrings are single-line for simple functions, multi-line for complex operations
- Format: Triple-quoted strings immediately after `def` line

**Example:**
```python
def run_cmd(
    args: List[str], check: bool = True, capture: bool = False
) -> Optional[str]:
    """Execute a command with error handling."""
```

```python
def fetch_github_ips() -> List[str]:
    """Fetch GitHub IP ranges from api.github.com/meta."""
    # ... implementation
    # Skip IPv6
    if ":" in cidr:
        continue
```

## Function Design

**Size:**
- Functions range from 3-15 lines typically
- Longer functions (30+ lines) handle complex orchestration: `main()`, `apply_firewall_rules()` are slightly longer but still readable
- Single-responsibility: Each function handles one concern (validate, load, fetch, process, etc.)

**Parameters:**
- Functions accept 1-3 parameters typically
- Type hints always included: `def run_cmd(args: List[str], check: bool = True, capture: bool = False) -> Optional[str]:`
- Default values used sparingly: `check=True`, `capture=False`

**Return Values:**
- Always include return type annotation: `-> None`, `-> str`, `-> List[str]`, `-> int`
- Return early from functions when appropriate: `return` statements for expected conditions
- None return type used for side-effect functions: `flush_rules() -> None`
- Consistent return types: Functions either succeed and return a value, or raise an exception (no `None` for failure)

**Example:**
```python
def load_policy(path: str) -> dict:
    """Load and validate policy JSON file."""
    if not os.path.isfile(path):
        raise FirewallError(f"Policy file not found: {path}")

    with open(path, "r") as f:
        try:
            policy = json.load(f)
        except json.JSONDecodeError as e:
            raise FirewallError(f"Invalid JSON in policy file: {e}")

    # Validation follows...
    return policy
```

## Module Design

**Exports:**
- `if __name__ == "__main__":` pattern used for all executable scripts
- No `__all__` list detected; all non-private functions are importable
- Private functions not prefixed with `_` (no private convention enforced)

**Constants at module level:**
- Configuration constants defined at top: `DEFAULT_POLICY_FILE`, `IPSET_NAME`, `GITHUB_META_URL`
- Environment variable defaults: `TZ`, `PYTHON_VERSION`, `CLAUDE_CODE_VERSION`
- Constants can be overridden via environment: `os.environ.get("KEY", "default_value")`

**Example module structure from `images/build.py`:**
```python
#!/usr/bin/env python3
import os
import subprocess
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent

# Defaults (env overrides allowed)
TZ = os.environ.get("TZ", "America/Los_Angeles")
PYTHON_VERSION = os.environ.get("PYTHON_VERSION", "3.13.11")

def run_docker_build(...) -> None:
    ...

def build_base() -> None:
    ...

if __name__ == "__main__":
    main()
```

## Shell Script Conventions

**Bash scripts located in:** `images/base/entrypoint.sh`

**Patterns:**
- Shebang: `#!/bin/bash`
- Error handling: `set -e` at top of script (exit on any error)
- Optional debug mode: `set -ex` available but commented out
- Comments explain non-obvious steps: "Initialize firewall if not already done"
- Conditional checks guard idempotent operations: `if ! ipset list allowed-domains >/dev/null 2>&1; then`
- Error messages boxed with ASCII art: `echo "==========..."`
- Variables in UPPERCASE: `HOST_UID`, `HOST_GID`, `APP_USER`, `APP_GROUP`
- Command substitution in quotes: `$(stat -c '%u' "$TARGET_DIR")`

**Example pattern from entrypoint.sh:**
```bash
set -e

# Initialize firewall if not already done
if ! ipset list allowed-domains >/dev/null 2>&1; then
    echo "Initializing firewall..."
    if ! /usr/local/bin/init-firewall.py; then
        echo "=========================================="
        echo "FATAL: Firewall initialization failed!"
        exit 1
    fi
else
    echo "Firewall already initialized."
fi
```

---

*Convention analysis: 2026-03-23*
