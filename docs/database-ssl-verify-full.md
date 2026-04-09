# PostgreSQL sslmode=verify-full with CA Certificate

## Overview

All eight Olympus service containers connect to PostgreSQL using `sslmode=verify-full`. This validates the server's TLS certificate against a self-signed CA on every connection, eliminating the MITM risk that `sslmode=require` leaves open.

This is a follow-on to platform#19 (`sslmode=require`) and was implemented in platform#53.

**Hard dependency**: platform#19 (`sslmode=require`) must be complete and production-verified before this configuration applies. `sslmode=verify-full` with an absent or misconfigured CA certificate causes all eight client containers to refuse database connections at startup.

**pgAdmin is out of scope**: pgAdmin TLS configuration uses a different DSN format and is tracked separately in DX-53-5. Do not apply this runbook to pgAdmin.

---

## How It Works

`sslmode=verify-full` (libpq) performs two checks on each connection:

1. The server's certificate is signed by a trusted CA (the `pg-ca.crt` distributed to each container)
2. The certificate's CN or SAN matches the hostname in the DSN (`postgres` — the Compose service name)

Both checks must pass. A self-signed server certificate without the CA in the trust path fails check 1. A certificate where CN does not match the DSN hostname fails check 2.

The server certificate in this deployment has `CN=postgres`, which matches the DSN host `postgres` (the Podman Compose service name). All eight containers connect using `host=postgres` in their DSN.

---

## Technical Details

### Certificate Structure

| File | Location | Committed? | Purpose |
|------|----------|-----------|---------|
| `pg-ca.crt` | `platform/prod/postgres/pg-ca.crt` | Yes (not a secret) | Self-signed CA certificate — distributed to all 8 client containers |
| `server.crt` | `platform/prod/postgres/server.crt` | Yes (not a secret) | Server certificate signed by `pg-ca.crt`, `CN=postgres` |
| `server.key` | `platform/prod/postgres/server.key` | No — gitignored, GitHub Secret `PG_SSL_KEY` | Server private key |
| `pg-ca.key` | Stored as GitHub Secret `PG_CA_KEY` | No — gitignored, never on disk after setup | CA private key — required for annual server cert rotation |

**Certificate validity**:
- CA certificate: 5 years (`-days 1825`)
- Server certificate: 1 year (`-days 365`) — annual rotation required

**CA key management**: The CA private key (`pg-ca.key`) is stored as GitHub Secret `PG_CA_KEY`. It must not be stored on disk between uses. The security justification for storing it in GitHub Secrets rather than destroying it: the server certificate requires annual rotation, which requires signing with the CA key. Destroying the CA key would require a full CA reissue at each rotation, which increases operational risk more than it reduces key exposure risk in a secrets vault.

### DSN Format

All eight client container DSNs use:

```
sslmode=verify-full&sslrootcert=/etc/ssl/certs/pg-ca.crt
```

The CA certificate is mounted in each container at `/etc/ssl/certs/pg-ca.crt` via a read-only bind mount.

### Client Containers

The following eight containers must have `pg-ca.crt` mounted and use `sslmode=verify-full`:

| Container | Database | Direct DB connection? |
|-----------|----------|----------------------|
| `ciam-kratos` | `ciam_kratos` | Yes — direct libpq connection |
| `ciam-hydra` | `ciam_hydra` | Yes — direct libpq connection |
| `iam-kratos` | `iam_kratos` | Yes — direct libpq connection |
| `iam-hydra` | `iam_hydra` | Yes — direct libpq connection |
| `ciam-hera` | — | No — Hera has no direct database connection. All database access goes through the SDK (`@olympusoss/sdk`) which connects to the `olympus` database. The SDK connection is what must have `pg-ca.crt` mounted and `sslmode=verify-full` in its DSN. |
| `iam-hera` | — | No — same as ciam-hera. No direct DB connection; all access is through the SDK. |
| `ciam-athena` | `olympus` (via SDK) | No — Athena's database access is through the SDK only. The SDK within the container holds the connection pool. |
| `iam-athena` | `olympus` (via SDK) | No — same as ciam-athena. |

**Note on Hera and Athena**: these containers require `pg-ca.crt` mounted and `sslmode=verify-full` in their `DATABASE_URL` because the SDK (running inside the container process) opens the connection to PostgreSQL. The container itself is the TLS client — the distinction is that the SDK library, not a Kratos/Hydra binary, initiates the connection.

### compose.prod.yml Volume Mount (per client container)

```yaml
volumes:
  - ../../platform/prod/postgres/pg-ca.crt:/etc/ssl/certs/pg-ca.crt:ro
```

The mount is read-only. The CA certificate is a public certificate and is committed to the repository — it is not a secret.

---

## CA Certificate Generation (One-Time Setup)

Run this once to generate the CA and server certificates. After generation, the CA key must be stored in GitHub Secrets and removed from disk.

```bash
# 1. Generate CA key and self-signed CA certificate (5-year validity)
openssl genrsa -out pg-ca.key 4096
openssl req -new -x509 -days 1825 -key pg-ca.key \
  -subj "/CN=Olympus-PG-CA" \
  -out platform/prod/postgres/pg-ca.crt

# 2. Generate server key and CSR
openssl genrsa -out platform/prod/postgres/server.key 2048
openssl req -new -key platform/prod/postgres/server.key \
  -subj "/CN=postgres" \
  -out server.csr

# 3. Sign server certificate with CA (1-year validity)
openssl x509 -req -days 365 \
  -in server.csr \
  -CA platform/prod/postgres/pg-ca.crt \
  -CAkey pg-ca.key \
  -CAcreateserial \
  -out platform/prod/postgres/server.crt

# 4. Set permissions
chmod 600 platform/prod/postgres/server.key pg-ca.key
chmod 644 platform/prod/postgres/server.crt platform/prod/postgres/pg-ca.crt

# 5. Store CA key in GitHub Secrets as PG_CA_KEY
# Settings > Secrets and variables > Actions > Secrets > New repository secret
# Name: PG_CA_KEY
# Value: contents of pg-ca.key

# 6. Remove CA key from disk (REQUIRED — do not skip)
rm pg-ca.key
rm server.csr

# 7. Commit pg-ca.crt and server.crt
git add platform/prod/postgres/pg-ca.crt platform/prod/postgres/server.crt
# server.key and pg-ca.key must NOT be staged — verify gitignore:
git check-ignore -v platform/prod/postgres/server.key  # should output a .gitignore rule
```

---

## Annual Server Certificate Rotation

The server certificate expires after 1 year. Rotate before expiry — the cert expiry date is tracked in a scheduled GitHub Actions workflow that opens an issue at the 60-day threshold.

```bash
# 1. Retrieve the CA key from GitHub Secrets
# Download PG_CA_KEY secret value and save locally as pg-ca.key (mode 600)
# Do NOT commit it

# 2. Generate new server key and CSR
openssl genrsa -out server.key.new 2048
openssl req -new -key server.key.new \
  -subj "/CN=postgres" \
  -out server.csr

# 3. Sign with CA (1 year)
openssl x509 -req -days 365 \
  -in server.csr \
  -CA platform/prod/postgres/pg-ca.crt \
  -CAkey pg-ca.key \
  -CAcreateserial \
  -out server.crt.new

# 4. Verify the new cert
openssl verify -CAfile platform/prod/postgres/pg-ca.crt server.crt.new
# Expected: server.crt.new: OK

# 5. Move into place
mv server.key.new platform/prod/postgres/server.key
mv server.crt.new platform/prod/postgres/server.crt
chmod 600 platform/prod/postgres/server.key

# 6. Update GitHub Secret PG_SSL_KEY with new server.key contents

# 7. Remove CA key from disk (REQUIRED)
rm pg-ca.key
rm server.csr

# 8. Commit the updated server.crt
git add platform/prod/postgres/server.crt

# 9. Deploy
```

---

## Examples

### Verify verify-full is active after deployment

```bash
# All connections must show ssl=true
# Note: clientdn reflects client certificate presence (mutual TLS), not sslmode.
# Use this query to confirm TLS is active; verify sslmode=verify-full per-container via DSN env vars.
podman exec <postgres_container> psql -U postgres \
  -c "SELECT pid, ssl, version FROM pg_stat_ssl WHERE ssl = true;"

# Confirm all 8 client containers have connections
podman exec <postgres_container> psql -U postgres \
  -c "SELECT count(*) AS ssl_connections FROM pg_stat_ssl WHERE ssl = true;"
# Expected: 8 or more (connection pool may have multiple connections per container)

# Confirm no plaintext connections
podman exec <postgres_container> psql -U postgres \
  -c "SELECT count(*) AS plaintext FROM pg_stat_ssl WHERE ssl = false;"
# Expected: 0
```

Post text output of these queries to the deployment issue thread as the SOC2 CC6.1 evidence artifact.

### Check certificate expiry

```bash
openssl x509 -noout -enddate -in platform/prod/postgres/server.crt
# Output: notAfter=Apr  8 12:00:00 2027 GMT
```

---

## Troubleshooting

### Container exits immediately with TLS error on startup

**Symptom**: A client container (ciam-kratos, ciam-hydra, etc.) exits within seconds of starting with a database connection error.

**Cause 1 — CA cert not mounted**: The `pg-ca.crt` volume mount is absent from the container's service definition in `compose.prod.yml`. Check that the bind mount exists and that the source file `platform/prod/postgres/pg-ca.crt` is present.

```bash
# Check the file exists in the deploy path
ls -la $DEPLOY_PATH/postgres/pg-ca.crt
```

**Cause 2 — Wrong DSN sslmode**: The DSN still uses `sslmode=require` or `sslmode=disable` instead of `sslmode=verify-full&sslrootcert=/etc/ssl/certs/pg-ca.crt`. Check each container's `DATABASE_URL` or Kratos/Hydra DSN env vars.

**Cause 3 — CA cert path mismatch**: The mount target in compose differs from the `sslrootcert` path in the DSN. Both must be `/etc/ssl/certs/pg-ca.crt`. Check:

```bash
# In the container, verify the file is present at the expected path
podman exec <container_name> ls -la /etc/ssl/certs/pg-ca.crt
```

### TLS handshake error: certificate verify failed

**Symptom**: Connection attempt returns `SSL error: certificate verify failed` or `FATAL: could not load certificate "/etc/ssl/certs/pg-ca.crt"`.

**Cause 1 — Mismatched CA**: The `pg-ca.crt` mounted in the container does not match the CA that signed `server.crt`. This happens if the CA was regenerated after the server cert was signed. Verify both files are from the same generation:

```bash
# CA cert subject key identifier
openssl x509 -noout -text -in platform/prod/postgres/pg-ca.crt | grep -A1 "Subject Key"

# Server cert authority key identifier (must match above)
openssl x509 -noout -text -in platform/prod/postgres/server.crt | grep -A1 "Authority Key"
```

**Cause 2 — CN mismatch**: `sslmode=verify-full` validates that the server cert CN matches the DSN hostname. If the DSN uses any hostname other than `postgres`, the connection will fail. All DSNs must use `host=postgres` (the Compose service name). Do not use `localhost`, `127.0.0.1`, or any other hostname.

### pg_stat_ssl shows fewer than 8 connections

**Symptom**: The count of `ssl=true` connections is less than 8 after all containers are healthy.

**Cause**: One or more containers has not yet established its connection pool, or is using `sslmode=require` instead of `sslmode=verify-full`. Run the enumeration query and check each connection's DSN — `sslmode=require` and `sslmode=verify-full` connections both show `ssl=true` in `pg_stat_ssl`. The `clientdn` column in `pg_stat_ssl` reflects whether the client presented a client certificate (mutual TLS); it does not indicate which sslmode the client used. You cannot distinguish `sslmode=require` from `sslmode=verify-full` using `pg_stat_ssl` alone — verify each container's `DATABASE_URL` or DSN env var directly.

Re-check all DSNs for any remaining `sslmode=require` entries.

### PostgreSQL container fails to start

**Symptom**: The `postgres` container exits immediately.

Check container logs:

```bash
podman logs <postgres_container>
```

Common causes:

| Log message | Cause | Fix |
|-------------|-------|-----|
| `private key file ... has group or world access` | `server.key` is not mode 600 | `chmod 600 server.key` in deploy.yml |
| `SSL certificate file ... does not exist` | `server.crt` not mounted | Verify volume bind in compose.prod.yml |
| `could not load server certificate file` | Certificate format invalid | `openssl x509 -noout -text -in server.crt` to inspect |

---

## Security Considerations

### CA key storage

The CA private key (`pg-ca.key`) is stored as GitHub Secret `PG_CA_KEY`. It must not be stored on disk outside of the rotation procedure window. During any rotation: download, use, delete immediately. Do not leave `pg-ca.key` on a developer workstation after use.

**Access scope for `PG_CA_KEY`**: GitHub Secrets at the repository level are accessible to any workflow running in the `OlympusOSS/platform` repository. In practice, this means any maintainer with `write` or `admin` access who can trigger or modify a workflow can use the secret. Access controls:
- Secret is scoped to the `platform` repository only — it is not an organisation-level secret
- Viewing the raw secret value requires `admin` access to the repository (GitHub setting: "Allow admins to bypass branch protections" does not grant secret read access; only repository owners or direct API calls with admin tokens can read secret values)
- Who has access: repository admins and any workflow step that explicitly references `${{ secrets.PG_CA_KEY }}`
- Audit trail: GitHub Actions logs record when the secret is injected into a step, but do not log the secret value itself
- Rotation of the secret (replacing `PG_CA_KEY` with a new CA key) requires repository admin access to GitHub Settings > Secrets and variables > Actions

### SOC2 CC6.1

`sslmode=verify-full` closes the MITM residual risk from `sslmode=require` and satisfies SOC2 CC6.1 for data in transit with certificate validation. Evidence artifacts:
- `compose.prod.yml` diff showing `pg-ca.crt` mount in all 8 client containers
- `deploy.yml` diff showing `sslmode=verify-full&sslrootcert=...` in all DSNs
- `pg_stat_ssl` query output (see Examples above) posted to deployment thread after all services are healthy

### Cert expiry alerting

A scheduled GitHub Actions workflow checks the server certificate `notAfter` field and opens an issue at the 60-day expiry threshold. Do not rely on manual calendar reminders — the alert is the rotation trigger.

### .gitignore is not a hard control

`pg-ca.key` and `server.key` are gitignored, but `.gitignore` can be bypassed with `git add -f`. A CI check scans staged files for `.key` extensions as a second line of defense. If the CI check fires, stop and remove the key from staging immediately.

---

*Last updated: 2026-04-08 (Technical Writer — platform#53)*
