# Testing Patterns

**Analysis Date:** 2026-03-23

## Test Framework

**Runner:**
- Not detected - No test framework configured
- No pytest.ini, tox.ini, setup.cfg, or pyproject.toml found
- No test files present in codebase

**Assertion Library:**
- Not applicable (no tests implemented)

**Run Commands:**
- No test commands configured
- Manual testing via shell execution and container runtime

## Test File Organization

**Location:**
- Not applicable - No tests found in codebase
- Suggested location for future tests: `tests/` directory at project root or alongside modules

**Naming:**
- No naming convention established (no tests present)
- Recommended pattern: `test_<module>.py` or `<module>_test.py`

**Structure:**
- Not established

## Current Testing Approach

**Manual Testing:**
The codebase relies on manual testing via:

1. **Firewall verification at startup:** `init-firewall.py` includes built-in verification in the `verify_firewall()` function
   - Location: `images/base/init-firewall.py` lines 364-405
   - Tests that `example.com` is blocked (negative test)
   - Tests that configured endpoints are reachable (positive test)
   - Runs automatically at container startup via `images/base/entrypoint.sh`

2. **Exit code verification:** Functions use exception raising and return codes
   - `main()` returns `0` on success, `1` on failure
   - Allows shell scripts to check `if ! /usr/local/bin/init-firewall.py; then`

**Example verification pattern from `init-firewall.py`:**
```python
def verify_firewall(policy: dict) -> None:
    """Verify firewall blocks example.com and allows configured endpoints."""
    print("Verifying firewall rules...")

    # Test blocked destination
    result = run_cmd_unchecked(["curl", "--connect-timeout", "5", VERIFY_BLOCKED_URL])
    if result.returncode == 0:
        raise FirewallError(
            f"Firewall verification failed - was able to reach {VERIFY_BLOCKED_URL}"
        )
    print(
        "Firewall verification passed - unable to reach https://example.com as expected"
    )

    # Test allowed destination
    if verify_url:
        result = run_cmd_unchecked(
            ["curl", "--connect-timeout", "5", "-m", "10", verify_url]
        )
        if result.returncode != 0:
            raise FirewallError(
                f"Firewall verification failed - unable to reach {verify_name}"
            )
```

## Test Structure (Current Manual Pattern)

**Error handling as test:**
Functions validate inputs and raise `FirewallError` on failure:

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

    if not isinstance(policy, dict):
        raise FirewallError("Policy must be a JSON object")

    services = policy.get("services", [])
    if not isinstance(services, list):
        raise FirewallError("'services' must be an array")

    domains = policy.get("domains", [])
    if not isinstance(domains, list):
        raise FirewallError("'domains' must be an array")

    return policy
```

**Validation functions tested implicitly:**
- `validate_ipv4()`: Called by `resolve_domain()` and validates each IP
- `validate_cidr()`: Called by `fetch_github_ips()` and validates CIDR ranges
- Both raise `FirewallError` on invalid input

## Recommended Test Structure for Future Tests

**Suggested approach using pytest:**

```python
# tests/test_init_firewall.py
import pytest
from pathlib import Path
from images.base.init_firewall import (
    FirewallError,
    validate_ipv4,
    validate_cidr,
    load_policy,
)

class TestValidation:
    def test_validate_ipv4_valid(self):
        assert validate_ipv4("192.168.1.1") is True
        assert validate_ipv4("8.8.8.8") is True

    def test_validate_ipv4_invalid(self):
        assert validate_ipv4("999.999.999.999") is False
        assert validate_ipv4("2001:db8::1") is False  # IPv6

    def test_validate_cidr_valid(self):
        assert validate_cidr("192.168.0.0/24") is True

    def test_validate_cidr_invalid(self):
        assert validate_cidr("999.0.0.0/24") is False
        assert validate_cidr("not-a-cidr") is False

class TestPolicyLoading:
    def test_load_policy_valid(self, tmp_path):
        policy_file = tmp_path / "policy.json"
        policy_file.write_text('{"services": ["github"], "domains": ["example.com"]}')

        policy = load_policy(str(policy_file))
        assert policy["services"] == ["github"]
        assert policy["domains"] == ["example.com"]

    def test_load_policy_file_not_found(self):
        with pytest.raises(FirewallError, match="Policy file not found"):
            load_policy("/nonexistent/path/policy.json")

    def test_load_policy_invalid_json(self, tmp_path):
        policy_file = tmp_path / "policy.json"
        policy_file.write_text("{ invalid json }")

        with pytest.raises(FirewallError, match="Invalid JSON"):
            load_policy(str(policy_file))

    def test_load_policy_invalid_structure(self, tmp_path):
        policy_file = tmp_path / "policy.json"
        policy_file.write_text('["not", "an", "object"]')

        with pytest.raises(FirewallError, match="must be a JSON object"):
            load_policy(str(policy_file))
```

## Mocking

**Framework:**
- Not implemented; no testing framework in place
- Recommended: `unittest.mock` (stdlib) or `pytest-mock`

**Patterns to use:**
For future tests of subprocess-heavy code, mock `subprocess.run()`:

```python
from unittest.mock import patch, MagicMock

@patch('images.base.init_firewall.subprocess.run')
def test_run_cmd_success(mock_run):
    mock_run.return_value = MagicMock(returncode=0, stdout="output")
    result = run_cmd(["echo", "test"], capture=True)
    assert result == "output"

@patch('images.base.init_firewall.subprocess.run')
def test_run_cmd_failure(mock_run):
    mock_run.return_value = MagicMock(returncode=1, stderr="error message")
    with pytest.raises(FirewallError):
        run_cmd(["failing-command"])
```

**What to Mock:**
- External subprocess calls: `subprocess.run()`, `subprocess.check_call()`
- Network calls: `urllib.request.urlopen()`
- DNS resolution: `socket.getaddrinfo()`

**What NOT to Mock:**
- Validation functions: Test them directly with various inputs
- Policy parsing: Test with actual JSON parsing
- Error classes: Test actual exception raising behavior

## Fixtures and Factories

**Test Data:**
Not implemented. Recommended fixtures for future tests:

```python
# tests/conftest.py
import pytest
from pathlib import Path

@pytest.fixture
def policy_file(tmp_path):
    """Create a valid policy JSON file for testing."""
    policy = {
        "services": ["github"],
        "domains": ["api.github.com", "example.com"]
    }
    policy_path = tmp_path / "policy.json"
    policy_path.write_text(json.dumps(policy))
    return str(policy_path)

@pytest.fixture
def invalid_policy_file(tmp_path):
    """Create an invalid policy JSON file for testing."""
    policy_path = tmp_path / "invalid.json"
    policy_path.write_text("{ bad json }")
    return str(policy_path)

@pytest.fixture
def mock_subprocess(monkeypatch):
    """Mock subprocess for testing without actual system calls."""
    def mock_run(args, **kwargs):
        return MagicMock(returncode=0, stdout="", stderr="")
    monkeypatch.setattr("subprocess.run", mock_run)
```

**Location:**
- Suggested: `tests/conftest.py` for shared fixtures
- Test-specific fixtures in `tests/test_<module>.py`

## Coverage

**Requirements:**
- Not enforced - No coverage tool configured
- Recommended: `pytest-cov` to track coverage

**View Coverage (recommended setup):**
```bash
pip install pytest pytest-cov
pytest --cov=images --cov-report=term-missing
```

## Test Types

**Unit Tests (Recommended):**
- Scope: Individual functions (validation, parsing, IP manipulation)
- Approach: Direct function calls with various inputs
- Location: `tests/test_init_firewall.py` for firewall logic, `tests/test_build.py` for build script
- Candidate functions to test:
  - `validate_ipv4()` - 5-7 test cases
  - `validate_cidr()` - 5-7 test cases
  - `load_policy()` - 4-5 test cases
  - `resolve_domain()` - 3-4 test cases (with DNS mocking)
  - `add_to_ipset()` - 2-3 test cases

**Integration Tests (Limited - Hard to Test):**
- Scope: Full firewall initialization flow with actual iptables (hard to test in CI)
- Approach: Would require Docker container with netadmin capabilities
- Recommended: Manual testing in container environment
- Could test in isolated container: Build test image, run `init-firewall.py`, verify with curl

**E2E Tests:**
- Framework: Manual shell-based testing via CI workflow
- Current verification: GitHub Actions in `.github/workflows/build-images.yml`
- Builds images on linux/amd64 and linux/arm64
- Smoke test: Container starts successfully and firewall initializes

**Example E2E workflow step (already in place):**
```yaml
- name: Build and push
  id: build
  uses: docker/build-push-action@v5
  with:
    context: ./images/base
    platforms: linux/amd64,linux/arm64
    push: true
```

## Common Patterns to Test

**Async Testing:**
- Not applicable - No async/await in codebase

**Error Testing:**
All functions raise `FirewallError` on invalid input:

```python
def test_validate_ipv4_rejects_ipv6(self):
    """Ensure validation rejects IPv6 addresses."""
    assert validate_ipv4("2001:db8::1") is False

def test_load_policy_missing_file(self):
    """Ensure missing policy file raises FirewallError."""
    with pytest.raises(FirewallError, match="Policy file not found"):
        load_policy("/nonexistent/policy.json")

def test_fetch_github_ips_handles_network_error(self):
    """Test graceful handling of network failures."""
    with patch('urllib.request.urlopen') as mock_urlopen:
        mock_urlopen.side_effect = urllib.error.URLError("Connection refused")
        with pytest.raises(FirewallError, match="Failed to fetch GitHub IP ranges"):
            fetch_github_ips()
```

## Testing Gaps

**Untested areas:**
- `fetch_github_ips()` - Requires network/mock setup, currently only tested manually
- `setup_host_network()` - Requires regex parsing and iptables knowledge
- `apply_firewall_rules()` - Complex iptables sequence, tested only in container
- `verify_firewall()` - Requires working firewall setup
- Shell script (`entrypoint.sh`) - No automated testing, relies on container runtime

**Risk:**
- Medium - Core firewall logic is tested at runtime but not in isolated unit tests
- Regression risk if `init-firewall.py` is refactored without unit tests

**Priority:**
- High - Add unit tests for validation functions and policy parsing
- Medium - Add integration tests for iptables rule generation
- Low - Shell script already verified at container startup

---

*Testing analysis: 2026-03-23*
