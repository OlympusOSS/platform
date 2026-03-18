#!/bin/sh
set -e

IAM_KRATOS_ADMIN_URL="${IAM_KRATOS_ADMIN_URL:-http://iam-kratos:7001}"
CIAM_KRATOS_ADMIN_URL="${CIAM_KRATOS_ADMIN_URL:-http://ciam-kratos:5001}"
CIAM_HYDRA_ADMIN_URL="${CIAM_HYDRA_ADMIN_URL:-http://ciam-hydra:5003}"
IAM_HYDRA_ADMIN_URL="${IAM_HYDRA_ADMIN_URL:-http://iam-hydra:7003}"

echo "Waiting for IAM Kratos to be ready..."
for i in $(seq 1 30); do
  if curl -sf "${IAM_KRATOS_ADMIN_URL}/health/ready" > /dev/null 2>&1; then
    echo "IAM Kratos is ready!"
    break
  fi
  echo "Waiting... ($i/30)"
  sleep 2
done

echo "Waiting for CIAM Kratos to be ready..."
for i in $(seq 1 30); do
  if curl -sf "${CIAM_KRATOS_ADMIN_URL}/health/ready" > /dev/null 2>&1; then
    echo "CIAM Kratos is ready!"
    break
  fi
  echo "Waiting... ($i/30)"
  sleep 2
done

echo "Waiting for CIAM Hydra to be ready..."
for i in $(seq 1 30); do
  if curl -sf "${CIAM_HYDRA_ADMIN_URL}/health/ready" > /dev/null 2>&1; then
    echo "CIAM Hydra is ready!"
    break
  fi
  echo "Waiting... ($i/30)"
  sleep 2
done

echo "Waiting for IAM Hydra to be ready..."
for i in $(seq 1 30); do
  if curl -sf "${IAM_HYDRA_ADMIN_URL}/health/ready" > /dev/null 2>&1; then
    echo "IAM Hydra is ready!"
    break
  fi
  echo "Waiting... ($i/30)"
  sleep 2
done

# ── Helper: upsert identity (create or update if exists) ──────────
# Usage: upsert_identity <KRATOS_URL> <EMAIL> <JSON_PAYLOAD> <LABEL>
#
# Tries POST first. If the identity already exists (409), looks it up
# by email and PUTs the updated traits + metadata_admin so the seed
# script is fully idempotent across restarts.
upsert_identity() {
  _url="$1"
  _email="$2"
  _payload="$3"
  _label="$4"

  # Try creating first
  _status=$(curl -s -o /dev/null -w "%{http_code}" -X POST "${_url}/admin/identities" \
    -H "Content-Type: application/json" \
    -d "${_payload}")

  if [ "$_status" = "201" ]; then
    echo "  Created: ${_label}"
    return 0
  fi

  # Identity likely exists — look it up by email and PUT to update
  _existing=$(curl -sf "${_url}/admin/identities?credentials_identifier=$(printf '%s' "${_email}" | sed 's/@/%40/g')" 2>/dev/null)
  # Extract the top-level identity ID (first "id" after the opening '[{')
  _id=$(echo "${_existing}" | grep -o '"id":"[^"]*"' | head -1 | sed 's/"id":"//;s/"//')

  if [ -z "$_id" ]; then
    echo "  WARN: ${_email} — could not create or find identity"
    return 1
  fi

  # PUT with full payload (Kratos admin API accepts credentials in PUT)
  _put_status=$(curl -s -o /dev/null -w "%{http_code}" -X PUT "${_url}/admin/identities/${_id}" \
    -H "Content-Type: application/json" \
    -d "${_payload}")

  if [ "$_put_status" = "200" ]; then
    echo "  Updated: ${_label}"
  else
    echo "  WARN: ${_email} — PUT returned ${_put_status}"
  fi

  # Mark email as verified (Kratos resets verification on credential changes)
  verify_email "${_url}" "${_email}"
}

# ── Helper: mark email as verified via PATCH ─────────────────────────
# Looks up identity by email and patches verifiable_addresses to verified.
verify_email() {
  _url="$1"
  _email="$2"

  _existing=$(curl -sf "${_url}/admin/identities?credentials_identifier=$(printf '%s' "${_email}" | sed 's/@/%40/g')" 2>/dev/null)
  _id=$(echo "${_existing}" | grep -o '"id":"[^"]*"' | head -1 | sed 's/"id":"//;s/"//')

  if [ -z "$_id" ]; then
    return 0
  fi

  # Get current verifiable addresses and mark as verified
  _va=$(curl -sf "${_url}/admin/identities/${_id}" 2>/dev/null | grep -o '"verifiable_addresses":\[[^]]*\]')

  # PATCH to set verified=true
  curl -sf -X PATCH "${_url}/admin/identities/${_id}" \
    -H "Content-Type: application/json" \
    -d "[{\"op\":\"replace\",\"path\":\"/verifiable_addresses/0/verified\",\"value\":true},{\"op\":\"replace\",\"path\":\"/verifiable_addresses/0/status\",\"value\":\"completed\"}]" > /dev/null 2>&1
}

echo ""
echo "=== IAM Identities (Employee/Admin) ==="

# Default dashboard layout — seeded into metadata_public for all IAM identities
# so Athena loads with a pre-configured dashboard on first login.
DEFAULT_LAYOUT='{"widgets":[{"h":3,"i":"stat-total-users","w":2,"x":0,"y":0},{"h":3,"i":"stat-active-sessions","w":2,"x":2,"y":0},{"h":3,"i":"stat-avg-session","w":2,"x":4,"y":0},{"h":3,"i":"stat-user-growth","w":2,"x":6,"y":0},{"h":3,"i":"chart-security-insights","w":4,"x":8,"y":0,"minH":3,"minW":2},{"h":4,"i":"chart-combined-activity","w":12,"x":0,"y":3,"minH":2,"minW":4},{"h":4,"i":"chart-users-by-schema","w":3,"x":0,"y":13,"minH":3,"minW":2},{"h":4,"i":"chart-verification-gauge","w":3,"x":9,"y":7,"minH":3,"minW":2},{"h":6,"i":"chart-peak-hours","w":6,"x":6,"y":11,"minH":3,"minW":3},{"h":6,"i":"chart-session-locations","w":6,"x":0,"y":7,"minH":4,"minW":4},{"h":4,"i":"chart-activity-feed","w":3,"x":6,"y":7,"minH":3,"minW":2},{"h":4,"i":"chart-oauth2-grant-types","w":3,"x":3,"y":13,"minH":3,"minW":2}],"hiddenWidgets":[]}'

# Create/update admin user: admin@demo.user
upsert_identity "${IAM_KRATOS_ADMIN_URL}" "admin@demo.user" \
  '{"schema_id":"admin","traits":{"email":"admin@demo.user","name":{"first":"Bobby","last":"Nannier"},"role":"admin"},"credentials":{"password":{"config":{"password":"admin123!"}}},"metadata_admin":{"demo":true,"password":"admin123!"},"metadata_public":{"dashboardLayout":'"${DEFAULT_LAYOUT}"'},"state":"active"}' \
  "admin@demo.user (role: admin, demo)"

# Create/update viewer user: viewer@demo.user
upsert_identity "${IAM_KRATOS_ADMIN_URL}" "viewer@demo.user" \
  '{"schema_id":"admin","traits":{"email":"viewer@demo.user","name":{"first":"Marine","last":"Nannier"},"role":"viewer"},"credentials":{"password":{"config":{"password":"admin123!"}}},"metadata_admin":{"demo":true,"password":"admin123!"},"metadata_public":{"dashboardLayout":'"${DEFAULT_LAYOUT}"'},"state":"active"}' \
  "viewer@demo.user (role: viewer, demo)"

echo ""
echo "=== CIAM Demo Identity ==="

# Create/update demo customer: demo@demo.user
upsert_identity "${CIAM_KRATOS_ADMIN_URL}" "demo@demo.user" \
  '{"schema_id":"customer","traits":{"email":"demo@demo.user","customer_id":"CUST-999","first_name":"Demo","last_name":"User","loyalty_tier":"gold","account_status":"active"},"credentials":{"password":{"config":{"password":"admin123!"}}},"metadata_admin":{"demo":true,"password":"admin123!"},"state":"active"}' \
  "demo@demo.user (customer, demo)"

echo ""
echo "=== CIAM Identities (Customers) ==="

# Create/update test customer: bobby.nannier@gmail.com
upsert_identity "${CIAM_KRATOS_ADMIN_URL}" "bobby.nannier@gmail.com" \
  '{"schema_id":"customer","traits":{"email":"bobby.nannier@gmail.com","customer_id":"CUST-001","first_name":"Bobby","last_name":"Nannier","loyalty_tier":"gold","account_status":"active"},"credentials":{"password":{"config":{"password":"admin123!"}}},"state":"active"}' \
  "bobby.nannier@gmail.com (customer: CUST-001)"

# Create/update test customer: bobby@nannier.com
upsert_identity "${CIAM_KRATOS_ADMIN_URL}" "bobby@nannier.com" \
  '{"schema_id":"customer","traits":{"email":"bobby@nannier.com","customer_id":"CUST-002","first_name":"Bobby","last_name":"Nannier","loyalty_tier":"silver","account_status":"active"},"credentials":{"password":{"config":{"password":"admin123!"}}},"state":"active"}' \
  "bobby@nannier.com (customer: CUST-002)"

echo ""
echo "Creating OAuth2 clients for admin panels..."

# Create OAuth2 client for CIAM Athena (admin panel for customer identities)
curl -sf -X POST "${IAM_HYDRA_ADMIN_URL}/admin/clients" \
  -H "Content-Type: application/json" \
  -d '{
    "client_id": "athena-ciam-client",
    "client_name": "Olympus CIAM Admin",
    "client_secret": "athena-ciam-secret",
    "grant_types": ["authorization_code", "refresh_token"],
    "response_types": ["code"],
    "redirect_uris": ["http://localhost:3003/api/auth/callback"],
    "post_logout_redirect_uris": ["http://localhost:3003/api/auth/login"],
    "scope": "openid profile email",
    "token_endpoint_auth_method": "client_secret_basic",
    "skip_consent": true
  }' > /dev/null 2>&1 && echo "  Created: athena-ciam-client (IAM Hydra)" || echo "  athena-ciam-client already exists or failed"

# Create OAuth2 client for IAM Athena (admin panel for employee identities)
curl -sf -X POST "${IAM_HYDRA_ADMIN_URL}/admin/clients" \
  -H "Content-Type: application/json" \
  -d '{
    "client_id": "athena-iam-client",
    "client_name": "Olympus IAM Admin",
    "client_secret": "athena-iam-secret",
    "grant_types": ["authorization_code", "refresh_token"],
    "response_types": ["code"],
    "redirect_uris": ["http://localhost:4003/api/auth/callback"],
    "post_logout_redirect_uris": ["http://localhost:4003/api/auth/login"],
    "scope": "openid profile email",
    "token_endpoint_auth_method": "client_secret_basic",
    "skip_consent": true
  }' > /dev/null 2>&1 && echo "  Created: athena-iam-client (IAM Hydra)" || echo "  athena-iam-client already exists or failed"

echo ""
echo "Creating OAuth2 client for pgAdmin..."

# Create OAuth2 client for pgAdmin (database management UI)
curl -sf -X POST "${IAM_HYDRA_ADMIN_URL}/admin/clients" \
  -H "Content-Type: application/json" \
  -d '{
    "client_id": "pgadmin",
    "client_name": "pgAdmin",
    "client_secret": "pgadmin-secret",
    "grant_types": ["authorization_code", "refresh_token"],
    "response_types": ["code"],
    "redirect_uris": ["http://localhost:4000/oauth2/authorize"],
    "scope": "openid email profile",
    "token_endpoint_auth_method": "client_secret_basic",
    "skip_consent": true
  }' > /dev/null 2>&1 && echo "  Created: pgadmin (IAM Hydra)" || echo "  pgadmin already exists or failed"

echo ""
echo "Creating OAuth2 clients for Site..."

# Create CIAM OAuth2 client for Site
curl -sf -X POST "${CIAM_HYDRA_ADMIN_URL}/admin/clients" \
  -H "Content-Type: application/json" \
  -d '{
    "client_id": "site-ciam-client",
    "client_name": "Olympus Site (CIAM)",
    "client_secret": "site-ciam-secret",
    "grant_types": ["authorization_code", "refresh_token"],
    "response_types": ["code"],
    "redirect_uris": ["http://localhost:2000/callback/ciam"],
    "post_logout_redirect_uris": ["http://localhost:2000"],
    "scope": "openid profile email",
    "token_endpoint_auth_method": "client_secret_basic"
  }' > /dev/null 2>&1 && echo "  Created: site-ciam-client (CIAM Hydra)" || echo "  site-ciam-client already exists or failed"

# Create IAM OAuth2 client for Site
curl -sf -X POST "${IAM_HYDRA_ADMIN_URL}/admin/clients" \
  -H "Content-Type: application/json" \
  -d '{
    "client_id": "site-iam-client",
    "client_name": "Olympus Site (IAM)",
    "client_secret": "site-iam-secret",
    "grant_types": ["authorization_code", "refresh_token"],
    "response_types": ["code"],
    "redirect_uris": ["http://localhost:2000/callback/iam"],
    "post_logout_redirect_uris": ["http://localhost:2000"],
    "scope": "openid profile email",
    "token_endpoint_auth_method": "client_secret_basic",
    "skip_consent": true
  }' > /dev/null 2>&1 && echo "  Created: site-iam-client (IAM Hydra)" || echo "  site-iam-client already exists or failed"

echo ""
echo "Seed complete!"
