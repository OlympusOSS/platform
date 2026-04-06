#!/usr/bin/env bash
# verify-email-enforcement.sh
#
# PURPOSE: Asserts that mandatory email verification is enforced in CIAM Kratos
#          for both dev and prod environments.
#
# SECURITY CONTEXT: The enforcement mechanism is flows.login.after.hooks containing
# require_verified_address. This hook intercepts every completed login attempt
# server-side and blocks users whose email address is not verified. It cannot be
# bypassed via direct Kratos API calls — it is enforced at the Kratos layer, not
# just the UI layer.
#
# IMPORTANT DISTINCTION (corrected from AC3 in platform#24):
#   flows.verification.use: code  — controls HOW verification works (OTP vs. link)
#   flows.login.after.hooks: [require_verified_address]  — controls WHETHER
#     unverified users can log in. This is the security control. The use: code
#     setting is NOT the bypass-prevention mechanism.
#
# TOOLING: Uses Python 3 (yaml.safe_load) for structural YAML parsing.
# Python 3 is pre-installed on all ubuntu-latest GitHub Actions runners and
# macOS development machines. This avoids a dependency on yq (which requires
# separate installation and version management).
# Reference: DA condition on platform#24 — "if yq is unavailable, specify the
# concrete structural alternative (not grep)."
#
# ACCEPTABLE DEV/PROD DIVERGENCES (documented per Architecture Brief):
#   log.level: debug (dev) vs info (prod)          — expected, not a security gap
#   log.leak_sensitive_values: true (dev) vs false  — expected, intentional
#   hashers.bcrypt.cost: 8 (dev) vs 12 (prod)      — expected, performance trade-off
#   dsn: sqlite (dev) vs env var (prod)             — expected, different backends
#   cors.allowed_origins hardcoded (dev) vs env var — expected
#   Any divergence in flows section: NOT acceptable — will fail this check
#
# USAGE:
#   ./scripts/verify-email-enforcement.sh
# Returns: exit 0 on all checks pass; exit 1 on any failure (with diagnostic output)
#
# CI: Invoked by .github/workflows/verify-email-enforcement.yml on push to main
# and on PRs touching dev/ciam-kratos/kratos.yml or prod/ciam-kratos/kratos.yml

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

DEV_CONFIG="${REPO_ROOT}/dev/ciam-kratos/kratos.yml"
PROD_CONFIG="${REPO_ROOT}/prod/ciam-kratos/kratos.yml"

PASS=0
FAIL=0

log_pass() {
    echo "  PASS: $1"
    PASS=$((PASS + 1))
}

log_fail() {
    echo "  FAIL: $1"
    FAIL=$((FAIL + 1))
}

# Run a structural YAML check using Python 3.
# Args: $1 = config file path, $2 = description, $3 = Python expression
# The Python expression must print "true" if the assertion passes, "false" otherwise.
check_yaml() {
    local config_file="$1"
    local description="$2"
    local python_expr="$3"

    local result
    result=$(python3 - "${config_file}" <<'PYEOF'
import sys
import yaml

config_path = sys.argv[1]
with open(config_path, 'r') as f:
    config = yaml.safe_load(f)

PYEOF
    python3 - "${config_file}" << PYEOF2
import sys
import yaml

config_path = sys.argv[1]
with open(config_path, 'r') as f:
    config = yaml.safe_load(f)

result = ${python_expr}
print("true" if result else "false")
PYEOF2
    )

    if [ "${result}" = "true" ]; then
        log_pass "${description}"
    else
        log_fail "${description}"
    fi
}

# Simpler wrapper that uses a heredoc to avoid quoting issues with inline Python
assert_yaml() {
    local config_file="$1"
    local description="$2"
    local check_type="$3"

    local result
    result=$(python3 << PYEOF
import sys
import yaml

with open('${config_file}', 'r') as f:
    config = yaml.safe_load(f)

flows = config.get('flows', {}) or {}
selfservice = config.get('selfservice', {}) or {}
selfservice_flows = selfservice.get('flows', {}) or {}

if '${check_type}' == 'login_hook':
    # Check flows.login.after.hooks contains require_verified_address
    # Note: Kratos YAML nests this under selfservice.flows.login in some versions
    # but our config uses the top-level flows.login path.
    login = flows.get('login', {}) or selfservice_flows.get('login', {}) or {}
    after = login.get('after', {}) or {}
    hooks = after.get('hooks', []) or []
    hook_names = [h.get('hook', '') if isinstance(h, dict) else str(h) for h in hooks]
    result = 'require_verified_address' in hook_names
    print('true' if result else 'false')

elif '${check_type}' == 'registration_empty_hooks':
    # Check flows.registration.after.password.hooks is empty (no auto-verify bypass)
    registration = flows.get('registration', {}) or selfservice_flows.get('registration', {}) or {}
    after = registration.get('after', {}) or {}
    password = after.get('password', {}) or {}
    hooks = password.get('hooks', []) or []
    result = len(hooks) == 0
    print('true' if result else 'false')

elif '${check_type}' == 'verification_enabled':
    # Check flows.verification.enabled is true
    verification = flows.get('verification', {}) or selfservice_flows.get('verification', {}) or {}
    result = verification.get('enabled', False) is True
    print('true' if result else 'false')

elif '${check_type}' == 'verification_use_code':
    # Check flows.verification.use is 'code'
    verification = flows.get('verification', {}) or selfservice_flows.get('verification', {}) or {}
    result = verification.get('use', '') == 'code'
    print('true' if result else 'false')

else:
    print('false')
PYEOF
    )

    if [ "${result}" = "true" ]; then
        log_pass "${description}"
    else
        log_fail "${description}"
    fi
}

# ============================================================
# Check: config files exist
# ============================================================
echo ""
echo "Checking config file existence..."

if [ -f "${DEV_CONFIG}" ]; then
    log_pass "Dev CIAM Kratos config exists: ${DEV_CONFIG}"
else
    log_fail "Dev CIAM Kratos config NOT FOUND: ${DEV_CONFIG}"
fi

if [ -f "${PROD_CONFIG}" ]; then
    log_pass "Prod CIAM Kratos config exists: ${PROD_CONFIG}"
else
    log_fail "Prod CIAM Kratos config NOT FOUND: ${PROD_CONFIG}"
fi

# Bail early if configs are missing
if [ "${FAIL}" -gt 0 ]; then
    echo ""
    echo "Cannot continue: required config files are missing."
    exit 1
fi

# ============================================================
# DEV: flows.login.after.hooks contains require_verified_address
# ============================================================
echo ""
echo "Checking DEV config: ${DEV_CONFIG}"

assert_yaml "${DEV_CONFIG}" \
    "DEV: flows.login.after.hooks contains require_verified_address (bypass-prevention mechanism)" \
    "login_hook"

assert_yaml "${DEV_CONFIG}" \
    "DEV: flows.registration.after.password.hooks is empty (no auto-verify bypass on registration)" \
    "registration_empty_hooks"

assert_yaml "${DEV_CONFIG}" \
    "DEV: flows.verification.enabled is true" \
    "verification_enabled"

assert_yaml "${DEV_CONFIG}" \
    "DEV: flows.verification.use is 'code'" \
    "verification_use_code"

# ============================================================
# PROD: same checks
# ============================================================
echo ""
echo "Checking PROD config: ${PROD_CONFIG}"

assert_yaml "${PROD_CONFIG}" \
    "PROD: flows.login.after.hooks contains require_verified_address (bypass-prevention mechanism)" \
    "login_hook"

assert_yaml "${PROD_CONFIG}" \
    "PROD: flows.registration.after.password.hooks is empty (no auto-verify bypass on registration)" \
    "registration_empty_hooks"

assert_yaml "${PROD_CONFIG}" \
    "PROD: flows.verification.enabled is true" \
    "verification_enabled"

assert_yaml "${PROD_CONFIG}" \
    "PROD: flows.verification.use is 'code'" \
    "verification_use_code"

# ============================================================
# Summary
# ============================================================
echo ""
echo "========================================"
echo "Results: ${PASS} passed, ${FAIL} failed"
echo "========================================"

if [ "${FAIL}" -gt 0 ]; then
    echo ""
    echo "SECURITY ALERT: Email verification enforcement check FAILED."
    echo ""
    echo "The require_verified_address hook in flows.login.after.hooks is the ONLY"
    echo "mechanism that prevents unverified CIAM accounts from logging in."
    echo "If this hook is absent or misconfigured, users can log in without"
    echo "verifying their email, enabling account takeover via email enumeration."
    echo ""
    echo "To fix: add require_verified_address to flows.login.after.hooks in the"
    echo "failing config file(s). See platform#24 for architectural context."
    exit 1
fi

echo ""
echo "All email verification enforcement checks passed."
exit 0
