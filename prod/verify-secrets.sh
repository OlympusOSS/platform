#!/usr/bin/env bash
# verify-secrets.sh — Pre-deploy verification for production secrets (platform#9).
#
# PURPOSE: Validates that all required secret environment variables in the
# production .env file resolve to non-empty values BEFORE the seed step runs.
# This is a CI-time complement to the runtime check-secrets.sh shim.
#
# SECURITY CONTEXT (Security Review — APPROVED WITH CONDITIONS):
#   Condition 1: Must be integrated into deploy.yml as a pre-seed step
#   Condition 2: Must validate env vars resolve to non-empty values, not just
#                that variable names appear in compose.prod.yml
#
# DUAL-LAYER PROTECTION MODEL:
#   Layer 1 (CI-time):  This script — catches empty secrets before containers start
#   Layer 2 (runtime):  check-secrets.sh — catches empty secrets at container startup
#
# USAGE (deploy.yml):
#   ssh $SSH_TARGET "cd $DEPLOY_PATH && bash verify-secrets.sh"
#
# The script reads the .env file from the current directory and checks all
# critical secret variables. It does NOT echo secret values — only reports
# presence/absence.

set -euo pipefail

ENV_FILE="${1:-.env}"

if [ ! -f "${ENV_FILE}" ]; then
    echo "FATAL: .env file not found at ${ENV_FILE}"
    echo "deploy.yml must generate .env before running verify-secrets.sh."
    exit 1
fi

# Source the .env file to get variable values
set -a
# shellcheck disable=SC1090
source "${ENV_FILE}"
set +a

PASS=0
FAIL=0

check_secret() {
    local var_name="$1"
    local description="$2"
    local value
    eval value="\${${var_name}:-}"
    if [ -n "${value}" ]; then
        echo "  PASS: ${var_name} — ${description}"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: ${var_name} is empty or unset — ${description}"
        FAIL=$((FAIL + 1))
    fi
}

echo ""
echo "=== Production Secrets Verification (platform#9) ==="
echo "Checking .env: ${ENV_FILE}"
echo ""

echo "--- Ory Kratos Secrets ---"
check_secret "CIAM_KRATOS_SECRET_COOKIE"  "CIAM Kratos session integrity"
check_secret "CIAM_KRATOS_SECRET_CIPHER"  "CIAM Kratos at-rest encryption"
check_secret "IAM_KRATOS_SECRET_COOKIE"   "IAM Kratos session integrity"
check_secret "IAM_KRATOS_SECRET_CIPHER"   "IAM Kratos at-rest encryption"

echo ""
echo "--- Ory Hydra Secrets ---"
check_secret "CIAM_HYDRA_SECRET_SYSTEM"   "CIAM Hydra token signing"
check_secret "CIAM_HYDRA_PAIRWISE_SALT"   "CIAM Hydra OIDC pairwise subject"
check_secret "IAM_HYDRA_SECRET_SYSTEM"    "IAM Hydra token signing"
check_secret "IAM_HYDRA_PAIRWISE_SALT"    "IAM Hydra OIDC pairwise subject"

echo ""
echo "--- SDK Encryption ---"
check_secret "ENCRYPTION_KEY"             "AES-256-GCM encryption for SDK settings"

echo ""
echo "--- Database ---"
check_secret "PG_USER"                    "PostgreSQL superuser"
check_secret "PG_PASSWORD"                "PostgreSQL password"

echo ""
echo "========================================"
echo "Results: ${PASS} passed, ${FAIL} failed"
echo "========================================"

if [ "${FAIL}" -gt 0 ]; then
    echo ""
    echo "FATAL: One or more production secrets are empty or unset."
    echo ""
    echo "Empty secrets cause silent failures in production:"
    echo "  - Empty Kratos cookie/cipher → Kratos refuses to start"
    echo "  - Empty Hydra system secret → Hydra refuses to start"
    echo "  - Empty ENCRYPTION_KEY → SDK throws on first encrypt/decrypt call"
    echo ""
    echo "Check that all required secrets are set in GitHub Settings >"
    echo "Secrets and variables > Actions > Secrets."
    echo ""
    echo "See platform/docs/secrets-audit.md for the full secret inventory"
    echo "and generation commands."
    exit 1
fi

echo ""
echo "All production secrets verified. Safe to proceed with seed."
exit 0
