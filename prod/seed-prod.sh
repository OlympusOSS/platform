#!/bin/sh
set -e

# =============================================================================
# OlympusOSS Production Seed Script
# =============================================================================
# Creates the initial admin identity and OAuth2 clients.
# Run via: docker compose --profile seed run --rm seed
#
# All credentials are read from environment variables (no hardcoded secrets).
#
# Idempotent: each resource is checked before creation. If it already exists
# the script moves on to the next resource.
# =============================================================================

# Validate required environment variables
: "${IAM_KRATOS_ADMIN_URL:?Required: IAM_KRATOS_ADMIN_URL}"
: "${CIAM_HYDRA_ADMIN_URL:?Required: CIAM_HYDRA_ADMIN_URL}"
: "${IAM_HYDRA_ADMIN_URL:?Required: IAM_HYDRA_ADMIN_URL}"
: "${ADMIN_EMAIL:?Required: ADMIN_EMAIL}"
: "${ADMIN_PASSWORD:?Required: ADMIN_PASSWORD}"
: "${CIAM_ATHENA_PUBLIC_URL:?Required: CIAM_ATHENA_PUBLIC_URL}"
: "${IAM_ATHENA_PUBLIC_URL:?Required: IAM_ATHENA_PUBLIC_URL}"
: "${ATHENA_CIAM_OAUTH_CLIENT_ID:?Required: ATHENA_CIAM_OAUTH_CLIENT_ID}"
: "${ATHENA_CIAM_OAUTH_CLIENT_SECRET:?Required: ATHENA_CIAM_OAUTH_CLIENT_SECRET}"
: "${ATHENA_IAM_OAUTH_CLIENT_ID:?Required: ATHENA_IAM_OAUTH_CLIENT_ID}"
: "${ATHENA_IAM_OAUTH_CLIENT_SECRET:?Required: ATHENA_IAM_OAUTH_CLIENT_SECRET}"

# Optional (only needed if demo profile is used)
DEMO_PUBLIC_URL="${DEMO_PUBLIC_URL:-}"
DEMO_CIAM_CLIENT_ID="${DEMO_CIAM_CLIENT_ID:-}"
DEMO_CIAM_CLIENT_SECRET="${DEMO_CIAM_CLIENT_SECRET:-}"
DEMO_IAM_CLIENT_ID="${DEMO_IAM_CLIENT_ID:-}"
DEMO_IAM_CLIENT_SECRET="${DEMO_IAM_CLIENT_SECRET:-}"

# -----------------------------------------------------------------------------
# Wait for services
# -----------------------------------------------------------------------------

wait_for_service() {
  local name="$1"
  local url="$2"
  echo "Waiting for ${name}..."
  for i in $(seq 1 30); do
    if curl -sf "${url}/health/ready" > /dev/null 2>&1; then
      echo "  ${name} is ready!"
      return 0
    fi
    echo "  Waiting... ($i/30)"
    sleep 2
  done
  echo "  ERROR: ${name} did not become ready in time"
  exit 1
}

wait_for_service "IAM Kratos" "${IAM_KRATOS_ADMIN_URL}"
wait_for_service "IAM Hydra"  "${IAM_HYDRA_ADMIN_URL}"
wait_for_service "CIAM Hydra" "${CIAM_HYDRA_ADMIN_URL}"

# -----------------------------------------------------------------------------
# Helpers — check-then-create pattern
# -----------------------------------------------------------------------------

# Check if an identity with the given email already exists in Kratos.
# Kratos admin API: GET /admin/identities?credentials_identifier=<email>
identity_exists() {
  local kratos_url="$1"
  local email="$2"
  local result
  result=$(curl -sf "${kratos_url}/admin/identities?credentials_identifier=${email}" 2>/dev/null) || return 1
  # The endpoint returns a JSON array — non-empty means the identity exists
  if echo "${result}" | grep -q '"id"'; then
    return 0
  fi
  return 1
}

# Check if an OAuth2 client with the given client_id already exists in Hydra.
# Hydra admin API: GET /admin/clients/<client_id>
oauth2_client_exists() {
  local hydra_url="$1"
  local client_id="$2"
  curl -sf "${hydra_url}/admin/clients/${client_id}" > /dev/null 2>&1
}

# Create an OAuth2 client in Hydra (idempotent — skips if already exists).
create_oauth2_client() {
  local hydra_url="$1"
  local client_id="$2"
  local client_name="$3"
  local client_secret="$4"
  local redirect_uri="$5"
  local post_logout_uri="$6"
  local skip_consent="${7:-true}"

  if oauth2_client_exists "${hydra_url}" "${client_id}"; then
    echo "  Exists: ${client_id} — skipping"
    return 0
  fi

  curl -sf -X POST "${hydra_url}/admin/clients" \
    -H "Content-Type: application/json" \
    -d "{
      \"client_id\": \"${client_id}\",
      \"client_name\": \"${client_name}\",
      \"client_secret\": \"${client_secret}\",
      \"grant_types\": [\"authorization_code\", \"refresh_token\"],
      \"response_types\": [\"code\"],
      \"redirect_uris\": [\"${redirect_uri}\"],
      \"post_logout_redirect_uris\": [\"${post_logout_uri}\"],
      \"scope\": \"openid profile email\",
      \"token_endpoint_auth_method\": \"client_secret_basic\",
      \"skip_consent\": ${skip_consent}
    }" > /dev/null 2>&1 && echo "  Created: ${client_id}" || { echo "  ERROR: failed to create ${client_id}"; exit 1; }
}

# -----------------------------------------------------------------------------
# Create initial admin identity in IAM Kratos
# -----------------------------------------------------------------------------

echo ""
echo "=== IAM Identity (Initial Admin) ==="

if identity_exists "${IAM_KRATOS_ADMIN_URL}" "${ADMIN_EMAIL}"; then
  echo "  Exists: ${ADMIN_EMAIL} — skipping"
else
  curl -sf -X POST "${IAM_KRATOS_ADMIN_URL}/admin/identities" \
    -H "Content-Type: application/json" \
    -d "{
      \"schema_id\": \"admin\",
      \"traits\": {
        \"email\": \"${ADMIN_EMAIL}\",
        \"name\": { \"first\": \"Admin\", \"last\": \"User\" },
        \"role\": \"admin\"
      },
      \"credentials\": {
        \"password\": {
          \"config\": {
            \"password\": \"${ADMIN_PASSWORD}\"
          }
        }
      },
      \"state\": \"active\"
    }" > /dev/null 2>&1 && echo "  Created: ${ADMIN_EMAIL} (role: admin)" || { echo "  ERROR: failed to create identity ${ADMIN_EMAIL}"; exit 1; }
fi

# -----------------------------------------------------------------------------
# Create OAuth2 clients
# -----------------------------------------------------------------------------

echo ""
echo "=== OAuth2 Clients ==="

# CIAM Athena — admin panel for customer identities (authenticates via IAM Hydra)
create_oauth2_client \
  "${IAM_HYDRA_ADMIN_URL}" \
  "${ATHENA_CIAM_OAUTH_CLIENT_ID}" \
  "Olympus CIAM Admin" \
  "${ATHENA_CIAM_OAUTH_CLIENT_SECRET}" \
  "${CIAM_ATHENA_PUBLIC_URL}/api/auth/callback" \
  "${CIAM_ATHENA_PUBLIC_URL}" \
  true

# IAM Athena — admin panel for employee identities (authenticates via IAM Hydra)
create_oauth2_client \
  "${IAM_HYDRA_ADMIN_URL}" \
  "${ATHENA_IAM_OAUTH_CLIENT_ID}" \
  "Olympus IAM Admin" \
  "${ATHENA_IAM_OAUTH_CLIENT_SECRET}" \
  "${IAM_ATHENA_PUBLIC_URL}/api/auth/callback" \
  "${IAM_ATHENA_PUBLIC_URL}" \
  true

# -----------------------------------------------------------------------------
# Site OAuth2 clients
# -----------------------------------------------------------------------------

if [ -n "${SITE_PUBLIC_URL}" ] && [ -n "${SITE_CIAM_CLIENT_ID}" ]; then
  echo ""
  echo "=== Site OAuth2 Clients ==="

  # Site CIAM — authenticates via CIAM Hydra
  create_oauth2_client \
    "${CIAM_HYDRA_ADMIN_URL}" \
    "${SITE_CIAM_CLIENT_ID}" \
    "Olympus Site (CIAM)" \
    "${SITE_CIAM_CLIENT_SECRET}" \
    "${SITE_PUBLIC_URL}/callback/ciam" \
    "${SITE_PUBLIC_URL}" \
    false

  # Site IAM — authenticates via IAM Hydra
  create_oauth2_client \
    "${IAM_HYDRA_ADMIN_URL}" \
    "${SITE_IAM_CLIENT_ID}" \
    "Olympus Site (IAM)" \
    "${SITE_IAM_CLIENT_SECRET}" \
    "${SITE_PUBLIC_URL}/callback/iam" \
    "${SITE_PUBLIC_URL}" \
    true
fi

# -----------------------------------------------------------------------------
# pgAdmin OAuth2 client
# -----------------------------------------------------------------------------

if [ -n "${PGADMIN_PUBLIC_URL}" ] && [ -n "${PGADMIN_OAUTH_CLIENT_ID}" ]; then
  echo ""
  echo "=== pgAdmin OAuth2 Client ==="

  create_oauth2_client \
    "${IAM_HYDRA_ADMIN_URL}" \
    "${PGADMIN_OAUTH_CLIENT_ID}" \
    "pgAdmin" \
    "${PGADMIN_OAUTH_CLIENT_SECRET}" \
    "${PGADMIN_PUBLIC_URL}/oauth2/authorize" \
    "${PGADMIN_PUBLIC_URL}" \
    true
fi

# -----------------------------------------------------------------------------
# Demo app OAuth2 clients (optional)
# -----------------------------------------------------------------------------

if [ -n "${DEMO_PUBLIC_URL}" ] && [ -n "${DEMO_CIAM_CLIENT_ID}" ]; then
  echo ""
  echo "=== Demo App OAuth2 Clients ==="

  # Demo CIAM — authenticates via CIAM Hydra
  create_oauth2_client \
    "${CIAM_HYDRA_ADMIN_URL}" \
    "${DEMO_CIAM_CLIENT_ID}" \
    "Demo App (CIAM)" \
    "${DEMO_CIAM_CLIENT_SECRET}" \
    "${DEMO_PUBLIC_URL}/callback/ciam" \
    "${DEMO_PUBLIC_URL}" \
    false

  # Demo IAM — authenticates via IAM Hydra
  create_oauth2_client \
    "${IAM_HYDRA_ADMIN_URL}" \
    "${DEMO_IAM_CLIENT_ID}" \
    "Demo App (IAM)" \
    "${DEMO_IAM_CLIENT_SECRET}" \
    "${DEMO_PUBLIC_URL}/callback/iam" \
    "${DEMO_PUBLIC_URL}" \
    true
fi

echo ""
echo "Seed complete!"
