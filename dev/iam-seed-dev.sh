#!/bin/sh
set -e

KRATOS_ADMIN_URL="${KRATOS_ADMIN_URL:-http://iam-kratos:7001}"
CIAM_HYDRA_ADMIN_URL="${CIAM_HYDRA_ADMIN_URL:-http://ciam-hydra:5003}"
IAM_HYDRA_ADMIN_URL="${IAM_HYDRA_ADMIN_URL:-http://iam-hydra:7003}"

echo "Waiting for IAM Kratos to be ready..."
for i in $(seq 1 30); do
  if curl -sf "${KRATOS_ADMIN_URL}/health/ready" > /dev/null 2>&1; then
    echo "IAM Kratos is ready!"
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

echo ""
echo "Creating seed identities..."

# Create admin user: bobby@nannier.com
curl -sf -X POST "${KRATOS_ADMIN_URL}/admin/identities" \
  -H "Content-Type: application/json" \
  -d '{
    "schema_id": "admin",
    "traits": {
      "email": "bobby@nannier.com",
      "name": { "first": "Bobby", "last": "Nannier" },
      "role": "admin"
    },
    "credentials": {
      "password": {
        "config": {
          "password": "admin123!"
        }
      }
    },
    "state": "active"
  }' > /dev/null 2>&1 && echo "  Created: bobby@nannier.com (role: admin)" || echo "  bobby@nannier.com already exists or failed"

# Create viewer user: viewer@athena.dev
curl -sf -X POST "${KRATOS_ADMIN_URL}/admin/identities" \
  -H "Content-Type: application/json" \
  -d '{
    "schema_id": "admin",
    "traits": {
      "email": "viewer@athena.dev",
      "name": { "first": "Demo", "last": "Viewer" },
      "role": "viewer"
    },
    "credentials": {
      "password": {
        "config": {
          "password": "admin123!"
        }
      }
    },
    "state": "active"
  }' > /dev/null 2>&1 && echo "  Created: viewer@athena.dev (role: viewer)" || echo "  viewer@athena.dev already exists or failed"

echo ""
echo "Creating OAuth2 clients for Demo app..."

# Create CIAM OAuth2 client for Demo app
curl -sf -X POST "${CIAM_HYDRA_ADMIN_URL}/admin/clients" \
  -H "Content-Type: application/json" \
  -d '{
    "client_id": "demo-ciam-client",
    "client_name": "Demo App (CIAM)",
    "client_secret": "demo-ciam-secret",
    "grant_types": ["authorization_code", "refresh_token"],
    "response_types": ["code"],
    "redirect_uris": ["http://localhost:2000/callback/ciam"],
    "post_logout_redirect_uris": ["http://localhost:2000"],
    "scope": "openid profile email",
    "token_endpoint_auth_method": "client_secret_basic"
  }' > /dev/null 2>&1 && echo "  Created: demo-ciam-client (CIAM Hydra)" || echo "  demo-ciam-client already exists or failed"

# Create IAM OAuth2 client for Demo app
curl -sf -X POST "${IAM_HYDRA_ADMIN_URL}/admin/clients" \
  -H "Content-Type: application/json" \
  -d '{
    "client_id": "demo-iam-client",
    "client_name": "Demo App (IAM)",
    "client_secret": "demo-iam-secret",
    "grant_types": ["authorization_code", "refresh_token"],
    "response_types": ["code"],
    "redirect_uris": ["http://localhost:2000/callback/iam"],
    "post_logout_redirect_uris": ["http://localhost:2000"],
    "scope": "openid profile email",
    "token_endpoint_auth_method": "client_secret_basic"
  }' > /dev/null 2>&1 && echo "  Created: demo-iam-client (IAM Hydra)" || echo "  demo-iam-client already exists or failed"

echo ""
echo "Seed complete!"
