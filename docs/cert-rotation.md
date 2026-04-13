# PostgreSQL TLS Certificate Rotation Runbook

**Owner**: Platform Engineer (Release Manager coordinates deployment)
**Frequency**: Annual (server cert); every 5 years (CA cert)
**Ticket**: platform#53

---

## Certificate Inventory

| Certificate | File | Validity | Storage | Committed |
|-------------|------|----------|---------|-----------|
| CA cert | `prod/postgres/pg-ca.crt` | 5 years | Repo (public) | Yes |
| CA key | `prod/postgres/pg-ca.key` | N/A | GitHub Secret `PG_CA_KEY` | No |
| Server cert | `prod/postgres/server.crt` | 1 year | Repo (public) | Yes |
| Server key | `prod/postgres/server.key` | N/A | GitHub Secret `PG_SSL_KEY` | No |

## Annual Server Certificate Rotation

### Prerequisites

- Access to GitHub Secrets for `PG_CA_KEY`
- `openssl` installed locally
- Write access to the `platform` repository

### Step 1: Retrieve the CA Key

Download the CA private key from GitHub Secret `PG_CA_KEY` to a temporary file.

```bash
# Save PG_CA_KEY secret value to a temporary file
# (retrieve from GitHub Settings > Secrets and variables > Actions > Secrets)
cat > /tmp/pg-ca.key <<'EOF'
<paste PG_CA_KEY value here>
EOF
chmod 600 /tmp/pg-ca.key
```

### Step 2: Generate New Server Key and Certificate

```bash
cd platform/prod/postgres

# Generate new server private key
openssl req -new -nodes -keyout server.key -out server.csr -subj "/CN=postgres"

# Sign with CA (1 year = 365 days)
openssl x509 -req -in server.csr -CA pg-ca.crt -CAkey /tmp/pg-ca.key -CAcreateserial -out server.crt -days 365

# Clean up
rm -f server.csr pg-ca.srl
chmod 600 server.key
chmod 644 server.crt
```

### Step 3: Verify the New Certificate

```bash
# Verify CN=postgres
openssl x509 -in server.crt -noout -subject
# Expected: subject=CN=postgres

# Verify signed by CA
openssl verify -CAfile pg-ca.crt server.crt
# Expected: server.crt: OK

# Check expiry date
openssl x509 -in server.crt -noout -dates
# Expected: ~1 year from now
```

### Step 4: Update GitHub Secret

1. Go to GitHub > OlympusOSS/platform > Settings > Secrets and variables > Actions > Secrets
2. Update `PG_SSL_KEY` with the contents of the new `server.key`
3. Verify the secret was saved (no confirmation of value, but timestamp updates)

### Step 5: Commit and Deploy

```bash
# Commit the new public cert (server.key is in .gitignore)
git add prod/postgres/server.crt
git commit -m "chore(ssl): rotate server certificate (annual)"
git push origin main

# Trigger deployment
gh workflow run deploy.yml --repo OlympusOSS/platform
```

### Step 6: Verify Deployment

After deployment completes:

```bash
# SSH to production and verify SSL
ssh <deploy-target>
cd /opt/olympusoss/prod
PG_USER=$(grep '^PG_USER=' .env | cut -d= -f2)

# Check new cert is loaded
podman exec prod_postgres_1 psql -U $PG_USER -c \
  "SELECT name, setting FROM pg_settings WHERE name IN ('ssl', 'ssl_ca_file');"

# Verify active TLS connections
podman exec prod_postgres_1 psql -U $PG_USER -c \
  "SELECT count(*) AS ssl_connections FROM pg_stat_ssl WHERE ssl = true;"
```

### Step 7: Clean Up

```bash
# Destroy the temporary CA key
rm -f /tmp/pg-ca.key

# Verify server.key is NOT staged
git status
# server.key should NOT appear in tracked files
```

### Rollback

If the new certificate causes connection failures:

1. Revert the `server.crt` commit: `git revert HEAD && git push`
2. Restore the old `PG_SSL_KEY` secret in GitHub (if the key was also rotated)
3. Re-trigger deployment: `gh workflow run deploy.yml`
4. Verify all services reconnect successfully

---

## CA Certificate Rotation (Every 5 Years)

CA rotation is a more involved process because all client containers trust the CA cert.

### Step 1: Generate New CA

```bash
cd platform/prod/postgres

# Generate new CA key and cert (5 years)
openssl req -new -x509 -days 1825 -nodes -keyout pg-ca.key -out pg-ca.crt -subj "/CN=pg-ca"
chmod 600 pg-ca.key
chmod 644 pg-ca.crt
```

### Step 2: Sign New Server Cert with New CA

```bash
# Generate new server key and CSR
openssl req -new -nodes -keyout server.key -out server.csr -subj "/CN=postgres"

# Sign with new CA
openssl x509 -req -in server.csr -CA pg-ca.crt -CAkey pg-ca.key -CAcreateserial -out server.crt -days 365

# Clean up
rm -f server.csr pg-ca.srl
chmod 600 server.key pg-ca.key
chmod 644 server.crt pg-ca.crt
```

### Step 3: Update GitHub Secrets

1. Update `PG_CA_KEY` with the new `pg-ca.key` contents
2. Update `PG_SSL_KEY` with the new `server.key` contents

### Step 4: Commit, Deploy, Verify

```bash
# Commit both public certs
git add prod/postgres/pg-ca.crt prod/postgres/server.crt
git commit -m "chore(ssl): rotate CA certificate (5-year cycle)"
git push origin main

# Deploy and verify (same as annual rotation Steps 5-7)
```

### Step 5: Destroy Local CA Key

```bash
rm -f prod/postgres/pg-ca.key
# Verify it's gone
ls -la prod/postgres/
# Only pg-ca.crt and server.crt should remain
```

---

## Troubleshooting

### Common SSL Errors

| Error | Cause | Fix |
|-------|-------|-----|
| `certificate verify failed` | Server cert not signed by CA, or CA cert mismatch | Re-sign server cert with the correct CA key |
| `SSL error: sslv3 alert certificate unknown` | CA cert not mounted in client container | Check volume mount in compose.prod.yml |
| `could not load private SSL key` | server.key missing or wrong permissions | Write PG_SSL_KEY secret, chmod 600, chown 70:70 |
| `hostname "X" does not match` | CN in server cert does not match connection hostname | Server cert CN must be `postgres` (Compose service name) |
| `SSL connection is required` | Client not providing sslrootcert | Verify DSN includes `sslrootcert=/etc/ssl/certs/pg-ca.crt` |

### Verifying Certificate Chain Locally

```bash
# Check CA cert details
openssl x509 -in prod/postgres/pg-ca.crt -noout -subject -issuer -dates

# Check server cert details
openssl x509 -in prod/postgres/server.crt -noout -subject -issuer -dates

# Verify chain
openssl verify -CAfile prod/postgres/pg-ca.crt prod/postgres/server.crt
```

### pgAdmin Note

pgAdmin connects to PostgreSQL using the pgpass file and does not currently use `sslmode=verify-full`. pgAdmin's connection is internal (within the Compose network) and uses `sslmode=require` via its server configuration. This is acceptable because pgAdmin is an administrative tool accessed via OAuth2 SSO, not a service processing user data.

---

## Alerting

Certificate expiry is monitored by the `cert-expiry-check.yml` GitHub Actions workflow:

- **Server cert**: Alert at 90 days before expiry (monthly check)
- **CA cert**: Alert at 180 days before expiry (monthly check)
- Alerts create GitHub Issues with label `security` and `cert-expiry`
- See `.github/workflows/cert-expiry-check.yml` for details
