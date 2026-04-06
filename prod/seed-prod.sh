#!/bin/sh
set -e

# =============================================================================
# OlympusOSS Production Seed Script
# =============================================================================
# Creates the initial admin identity and OAuth2 clients.
# Run via: podman compose -f compose.prod.yml run --rm --no-deps seed
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

# Create or update an OAuth2 client in Hydra (true upsert).
# If the client already exists, PUT replaces it so secrets, redirect URIs,
# and other settings always match the current deployment.
#
# Parameters:
#   $1  hydra_url
#   $2  client_id
#   $3  client_name
#   $4  client_secret
#   $5  redirect_uri
#   $6  post_logout_uri
#   $7  skip_consent         (default: true)
#   $8  subject_type         (default: pairwise) — use "public" for Athena clients so the
#                             sub claim is the raw Kratos identity UUID instead of a
#                             pairwise HMAC. Required for /userinfo sub matching (athena#52).
#   $9  token_endpoint_auth  (default: client_secret_basic) — use "none" for Athena clients
#                             to enforce PKCE S256 on the authorization code flow per the
#                             Security Expert requirement (athena#52).
create_oauth2_client() {
  local hydra_url="$1"
  local client_id="$2"
  local client_name="$3"
  local client_secret="$4"
  local redirect_uri="$5"
  local post_logout_uri="$6"
  local skip_consent="${7:-true}"
  local subject_type="${8:-pairwise}"
  local auth_method="${9:-client_secret_basic}"

  local payload
  if [ "${auth_method}" = "none" ]; then
    # Public client (PKCE) — no client_secret
    payload="{
      \"client_id\": \"${client_id}\",
      \"client_name\": \"${client_name}\",
      \"grant_types\": [\"authorization_code\", \"refresh_token\"],
      \"response_types\": [\"code\"],
      \"redirect_uris\": [\"${redirect_uri}\"],
      \"post_logout_redirect_uris\": [\"${post_logout_uri}\"],
      \"scope\": \"openid profile email\",
      \"subject_type\": \"${subject_type}\",
      \"token_endpoint_auth_method\": \"none\",
      \"skip_consent\": ${skip_consent}
    }"
  else
    # Confidential client — includes client_secret
    payload="{
      \"client_id\": \"${client_id}\",
      \"client_name\": \"${client_name}\",
      \"client_secret\": \"${client_secret}\",
      \"grant_types\": [\"authorization_code\", \"refresh_token\"],
      \"response_types\": [\"code\"],
      \"redirect_uris\": [\"${redirect_uri}\"],
      \"post_logout_redirect_uris\": [\"${post_logout_uri}\"],
      \"scope\": \"openid profile email\",
      \"subject_type\": \"${subject_type}\",
      \"token_endpoint_auth_method\": \"${auth_method}\",
      \"skip_consent\": ${skip_consent}
    }"
  fi

  if oauth2_client_exists "${hydra_url}" "${client_id}"; then
    curl -sf -X PUT "${hydra_url}/admin/clients/${client_id}" \
      -H "Content-Type: application/json" \
      -d "${payload}" > /dev/null 2>&1 && echo "  Updated: ${client_id}" || { echo "  ERROR: failed to update ${client_id}"; exit 1; }
  else
    curl -sf -X POST "${hydra_url}/admin/clients" \
      -H "Content-Type: application/json" \
      -d "${payload}" > /dev/null 2>&1 && echo "  Created: ${client_id}" || { echo "  ERROR: failed to create ${client_id}"; exit 1; }
  fi
}

# -----------------------------------------------------------------------------
# Default dashboard layout — seeded into metadata_public for all IAM identities
# so Athena loads with a pre-configured dashboard on first login.
# -----------------------------------------------------------------------------

DEFAULT_LAYOUT='{"widgets":[{"h":3,"i":"stat-total-users","w":2,"x":0,"y":0},{"h":3,"i":"stat-active-sessions","w":2,"x":2,"y":0},{"h":3,"i":"stat-avg-session","w":2,"x":4,"y":0},{"h":3,"i":"stat-user-growth","w":2,"x":6,"y":0},{"h":3,"i":"chart-security-insights","w":4,"x":8,"y":0,"minH":3,"minW":2},{"h":4,"i":"chart-combined-activity","w":12,"x":0,"y":3,"minH":2,"minW":4},{"h":4,"i":"chart-users-by-schema","w":3,"x":0,"y":13,"minH":3,"minW":2},{"h":4,"i":"chart-verification-gauge","w":3,"x":9,"y":7,"minH":3,"minW":2},{"h":6,"i":"chart-peak-hours","w":6,"x":6,"y":11,"minH":3,"minW":3},{"h":6,"i":"chart-session-locations","w":6,"x":0,"y":7,"minH":4,"minW":4},{"h":4,"i":"chart-activity-feed","w":3,"x":6,"y":7,"minH":3,"minW":2},{"h":4,"i":"chart-oauth2-grant-types","w":3,"x":3,"y":13,"minH":3,"minW":2}],"hiddenWidgets":[]}'

# -----------------------------------------------------------------------------
# Create initial admin identity in IAM Kratos
# -----------------------------------------------------------------------------

echo ""
echo "=== IAM Identity (Initial Admin) ==="

EXISTING_ID=$(curl -sf "${IAM_KRATOS_ADMIN_URL}/admin/identities?credentials_identifier=${ADMIN_EMAIL}" 2>/dev/null \
  | sed -n 's/.*"id":"\([^"]*\)".*/\1/p' | head -1)

if [ -n "${EXISTING_ID}" ]; then
  echo "  Exists: ${ADMIN_EMAIL} (${EXISTING_ID}) — updating"
  UPDATE_RESP=$(curl -s -w "\n%{http_code}" -X PUT "${IAM_KRATOS_ADMIN_URL}/admin/identities/${EXISTING_ID}" \
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
      \"metadata_public\": {
        \"dashboardLayout\": ${DEFAULT_LAYOUT}
      },
      \"state\": \"active\"
    }" 2>&1)
  UPDATE_CODE=$(echo "${UPDATE_RESP}" | tail -1)
  if [ "${UPDATE_CODE}" = "200" ]; then
    echo "  Updated: ${ADMIN_EMAIL}"
  else
    UPDATE_BODY=$(echo "${UPDATE_RESP}" | sed '$d')
    echo "  WARN: failed to update ${ADMIN_EMAIL} (HTTP ${UPDATE_CODE}): ${UPDATE_BODY}"
  fi
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
      \"metadata_public\": {
        \"dashboardLayout\": ${DEFAULT_LAYOUT}
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
# subject_type=public: sub claim is the raw Kratos UUID, enabling /userinfo lookup (athena#52)
# token_endpoint_auth=none: public client (PKCE S256) per Security Expert requirement (athena#52)
create_oauth2_client \
  "${IAM_HYDRA_ADMIN_URL}" \
  "${ATHENA_CIAM_OAUTH_CLIENT_ID}" \
  "Olympus CIAM Admin" \
  "" \
  "${CIAM_ATHENA_PUBLIC_URL}/api/auth/callback" \
  "${CIAM_ATHENA_PUBLIC_URL}" \
  true \
  public \
  none

# IAM Athena — admin panel for employee identities (authenticates via IAM Hydra)
# subject_type=public: sub claim is the raw Kratos UUID, enabling /userinfo lookup (athena#52)
# token_endpoint_auth=none: public client (PKCE S256) per Security Expert requirement (athena#52)
create_oauth2_client \
  "${IAM_HYDRA_ADMIN_URL}" \
  "${ATHENA_IAM_OAUTH_CLIENT_ID}" \
  "Olympus IAM Admin" \
  "" \
  "${IAM_ATHENA_PUBLIC_URL}/api/auth/callback" \
  "${IAM_ATHENA_PUBLIC_URL}" \
  true \
  public \
  none

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

echo ""
echo "Seed complete!"
