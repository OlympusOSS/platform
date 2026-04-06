#!/bin/sh
set -e

HYDRA_ADMIN_URL="${HYDRA_ADMIN_URL:-http://iam-hydra:7003}"

echo "Waiting for Hydra to be ready..."
for i in $(seq 1 30); do
  if curl -sf "${HYDRA_ADMIN_URL}/health/ready" > /dev/null 2>&1; then
    echo "Hydra is ready!"
    break
  fi
  echo "Waiting... ($i/30)"
  sleep 2
done

# Check if pgadmin client already exists
EXISTING=$(curl -sf "${HYDRA_ADMIN_URL}/admin/clients/pgadmin" 2>/dev/null || echo "")
if echo "$EXISTING" | grep -q '"client_id":"pgadmin"'; then
  echo "pgadmin OAuth2 client already exists, skipping creation."
  exit 0
fi

echo "Creating pgadmin OAuth2 client..."
# platform#21: The 'roles' claim is injected into all IAM Hydra ID tokens via the
# global oidc.claims_mapper in iam-hydra/hydra.yml (pgadmin-claims-mapper.jsonnet).
# pgAdmin's OAUTH2_ADDITIONAL_CLAIMS_VALIDATION hook enforces 'dba' role membership
# as a second access control layer (in addition to OAUTH2_AUTO_CREATE_USER = False).
curl -sf -X POST "${HYDRA_ADMIN_URL}/admin/clients" \
  -H "Content-Type: application/json" \
  -d '{
    "client_id": "pgadmin",
    "client_secret": "pgadmin-secret",
    "client_name": "pgAdmin",
    "grant_types": ["authorization_code", "refresh_token"],
    "response_types": ["code"],
    "scope": "openid email profile",
    "redirect_uris": ["http://localhost:5433/oauth2/authorize"],
    "token_endpoint_auth_method": "client_secret_basic",
    "skip_consent": true
  }'

echo ""
echo "pgadmin OAuth2 client created successfully!"
