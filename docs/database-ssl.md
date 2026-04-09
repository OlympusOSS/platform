# Database SSL

## Overview

All five Olympus PostgreSQL connections use `sslmode=require` in production, encrypting all data
in transit between application services and the database. This was implemented in platform#19 to
close a SOC2 CC6.1 gap — the prior default was `sslmode=disable`.

`sslmode=require` encrypts the connection but does not validate the server certificate. Certificate
validation (`sslmode=verify-full`) is tracked in a follow-on ticket (platform#53).

---

## How It Works

### SSL Mode Decision

| Mode | Encrypts connection | Validates server cert | MITM risk |
|------|--------------------|-----------------------|-----------|
| `disable` | No | No | Full — plaintext on wire |
| `require` | Yes | No (accepts any cert) | Low — attacker needs network position |
| `verify-full` | Yes | Yes (CA + hostname) | None |

For a containerized deployment where PostgreSQL and all clients run on the same private Podman
`intranet` network, `sslmode=require` eliminates plaintext-on-the-wire and satisfies SOC2 CC6.1.
`sslmode=verify-full` is the correct long-term target and is tracked separately (platform#53).

### Connection Strings

All five DSNs in `deploy.yml` use the variable pattern:

```
sslmode=${{ vars.PG_SSLMODE || 'require' }}
```

The `vars.PG_SSLMODE` GitHub Variable overrides the default. If this variable is set to `disable`,
it silently negates the SSL enforcement regardless of what is in `deploy.yml`. See the pre-deployment
checklist below.

### Server-Side SSL Configuration

The PostgreSQL container (`postgres:18-alpine`) is configured with SSL enabled in `compose.prod.yml`:

```yaml
postgres:
  command: >
    postgres
    -c ssl=on
    -c ssl_cert_file=/var/lib/postgresql/server.crt
    -c ssl_key_file=/var/lib/postgresql/server.key
  volumes:
    - type: bind
      source: ./postgres/server.crt
      target: /var/lib/postgresql/server.crt
      read_only: true
    - type: bind
      source: ./postgres/server.key
      target: /var/lib/postgresql/server.key
      read_only: true
```

`server.crt` is committed to the repository. `server.key` is provisioned at deployment time from
the `PG_SSL_KEY` GitHub Secret.

### Certificate Structure

A self-signed CA was generated and the server certificate was signed by that CA. This structure
reduces the migration cost for the future `verify-full` upgrade — when platform#53 is implemented,
only the CA certificate needs to be distributed to client containers; no new server certificate
generation is required.

Files in `platform/prod/postgres/`:
- `pg-ca.crt` — self-signed CA certificate (committed)
- `server.crt` — server certificate signed by `pg-ca.crt` (committed)
- `server.key` — server private key (gitignored, provisioned via `PG_SSL_KEY` secret)
- `pg-ca.key` — CA private key (gitignored)

Certificate expiry: see [database-ssl-verify-full.md](database-ssl-verify-full.md) for current cert validity details (updated in platform#53).

---

## API / Technical Details

### The Five Databases

| Database | Service | DSN parameter |
|----------|---------|---------------|
| `ciam_kratos` | CIAM Kratos | `PG_CIAM_KRATOS_DSN` |
| `ciam_hydra` | CIAM Hydra | `PG_CIAM_HYDRA_DSN` |
| `iam_kratos` | IAM Kratos | `PG_IAM_KRATOS_DSN` |
| `iam_hydra` | IAM Hydra | `PG_IAM_HYDRA_DSN` |
| `olympus` | SDK / Athena | `PG_OLYMPUS_DSN` |

### Key File Permissions

`postgres:18-alpine` requires the server key to have mode `600`. Mode `644` causes a startup
failure with:

```
FATAL:  private key file "/var/lib/postgresql/server.key" has group or world access
DETAIL:  File must have permissions u=rw (0600) or less if owned by the database user,
         or permissions u=rw,g=r (0640) or less if owned by root.
```

The `deploy.yml` write step sets `chmod 600` on the key file. No `chown` is required — empirically
verified with `postgres:18-alpine` (postgres 18.3): a root-owned, mode-600 key file is accepted.

### Deployment Sequencing

`server.key` must be written to disk **before** the PostgreSQL container starts. If the key is
absent when PostgreSQL attempts to load its SSL configuration, the container fails to start.

The deploy.yml step that writes `server.key` from `secrets.PG_SSL_KEY` appears explicitly before
the compose step that starts PostgreSQL. Do not reorder these steps.

### Dev Environment

The development environment (`compose.dev.yml`) uses `sslmode=disable`. SSL certificates are not
required for local development. Do not attempt to apply the production SSL certificate configuration
to your local dev environment.

---

## Pre-Deployment Checklist

Before triggering `deploy.yml` for any deployment where SSL changes are involved:

**1. Add the `PG_SSL_KEY` GitHub Secret** (if not already present):
- Go to: Settings > Secrets and variables > Actions > Secrets
- Add secret named `PG_SSL_KEY`
- Value: full contents of `platform/prod/postgres/server.key`

**2. Delete or update the `PG_SSLMODE` GitHub Variable**:
- Go to: Settings > Secrets and variables > Actions > Variables
- Either delete `PG_SSLMODE` entirely (the `require` default in `deploy.yml` takes effect)
- Or set `PG_SSLMODE` to `require` explicitly

**Warning — silent failure mode**: if `PG_SSLMODE=disable` is still set as a GitHub Variable when
you deploy, the variable value overrides the `|| 'require'` default in `deploy.yml`. All five
database connections continue using plaintext. There is no error or warning. The deployment
completes successfully but SSL is not active. Always verify this variable before deploying.

---

## Examples

### Verify SSL is active after deployment

Run after all services pass health checks (all service connections must be established first):

```bash
# Check server-side SSL is enabled
podman exec <postgres_container> psql -U $PG_USER \
  -c "SELECT name, setting FROM pg_settings WHERE name = 'ssl';"
# Expected: ssl | on

# Count active TLS connections
podman exec <postgres_container> psql -U $PG_USER \
  -c "SELECT count(*) AS ssl_connections FROM pg_stat_ssl WHERE ssl = true;"
# Expected: count > 0

# Confirm no plaintext connections remain
podman exec <postgres_container> psql -U $PG_USER \
  -c "SELECT count(*) AS plaintext FROM pg_stat_ssl WHERE ssl = false;"
# Expected: count = 0
```

The `pg_stat_ssl` query is a point-in-time check. Run it after all services pass health checks —
if run before services have connected, it returns zero even with a correct SSL configuration.

Post the text output of both queries to the deployment issue thread as the SOC2 CC6.1 evidence
artifact. Text output (not a screenshot) is the durable evidence format.

### Regenerate certificates (if rotation is needed)

```bash
# Step 1: Generate self-signed CA
openssl req -new -x509 -days 3650 -nodes \
  -subj "/CN=pg-ca" \
  -keyout platform/prod/postgres/pg-ca.key \
  -out platform/prod/postgres/pg-ca.crt

# Step 2: Generate server key
openssl genrsa -out platform/prod/postgres/server.key 2048

# Step 3: Generate server CSR
openssl req -new -key platform/prod/postgres/server.key \
  -subj "/CN=postgres" \
  -out platform/prod/postgres/server.csr

# Step 4: Sign server cert with CA
openssl x509 -req -days 3650 \
  -in platform/prod/postgres/server.csr \
  -CA platform/prod/postgres/pg-ca.crt \
  -CAkey platform/prod/postgres/pg-ca.key \
  -CAcreateserial \
  -out platform/prod/postgres/server.crt

chmod 600 platform/prod/postgres/server.key platform/prod/postgres/pg-ca.key
chmod 644 platform/prod/postgres/server.crt platform/prod/postgres/pg-ca.crt
```

After regeneration: update `PG_SSL_KEY` GitHub Secret with the new `server.key` contents, and
commit the updated `server.crt` and `pg-ca.crt`.

---

## Troubleshooting

### Services fail to start after deploying with SSL

**Symptom**: Kratos, Hydra, or Athena container exits with a database connection error immediately
after starting.

**Cause 1 — server.key written after PostgreSQL started**: the deploy.yml step that writes
`server.key` ran after the compose step that started PostgreSQL. PostgreSQL loaded with `ssl=on`
but the key file was absent, causing it to fail. Verify the step ordering in deploy.yml.

**Cause 2 — server.key has wrong permissions**: verify mode 600 with
`ls -la $DEPLOY_PATH/postgres/server.key`. Mode 644 causes PostgreSQL to refuse the key.

**Cause 3 — wrong DSN format**: some DSN formats embed the sslmode as a query parameter
(`...?sslmode=require`) while others expect it as a DSN keyword (`sslmode=require host=...`).
Check the connection string format used by each service. Kratos and Hydra use the URL query
parameter format.

### SOC2 query returns zero connections

**Symptom**: `SELECT count(*) FROM pg_stat_ssl WHERE ssl = true` returns 0 after deployment.

**Cause 1 — PG_SSLMODE variable override**: the `PG_SSLMODE` GitHub Variable is still set to
`disable` and overrides the `|| 'require'` default. Check GitHub Variables at Settings >
Secrets and variables > Actions > Variables.

**Cause 2 — query run before services connected**: the SSL query counts currently active
connections. If run before Kratos/Hydra/Athena have established their connection pools, the count
is zero even with a correct configuration. Re-run after all services report healthy.

### PostgreSQL fails to start entirely

**Symptom**: the PostgreSQL container exits immediately with an SSL-related error.

Check the container logs:

```bash
podman logs <postgres_container>
```

Common errors and causes:

- `private key file ... has group or world access` — `server.key` is mode 644 or 664; must be 600
- `SSL certificate file ... does not exist` — `server.crt` was not mounted; verify the volume
  binding in `compose.prod.yml` and that `server.crt` exists in the deploy path
- `could not load server certificate file` — certificate format issue; verify the cert with
  `openssl x509 -noout -text -in server.crt`

---

## Security Considerations

### What `sslmode=require` provides

- Encrypts all data between application services and PostgreSQL
- Prevents passive network interception of queries, credentials, and query results

### What `sslmode=require` does not provide

- Server certificate validation — a network-positioned attacker (e.g., a compromised co-tenant
  on a shared host) can present a forged certificate and intercept the encrypted connection
- `sslmode=verify-full` (platform#53) is required to close this MITM risk

### Residual risk with `sslmode=require`

On the current single-host Podman deployment where PostgreSQL and all clients are on the private
`intranet` network, the MITM risk from `require` mode is low. A network-positioned attacker would
need to compromise the host or Podman's network bridge to mount the attack. `verify-full` remains
the correct long-term target regardless.

### Private key security

`server.key` and `pg-ca.key` must never be committed to the repository. Both are gitignored. Verify
with `git check-ignore -v platform/prod/postgres/server.key` after any changes to `.gitignore`.

If either key is accidentally committed, treat it as a credential compromise: rotate immediately by
regenerating both keys and certificates, updating `PG_SSL_KEY` in GitHub Secrets, and redeploying.

### SOC2 CC6.1

SOC2 CC6.1 requires encryption of data in transit. The evidence artifacts for this control are:
- `deploy.yml` diff showing `sslmode=require` in all five DSNs
- `compose.prod.yml` diff showing `ssl=on` PostgreSQL command arguments
- `pg_stat_ssl` and `pg_settings` query output posted to the deployment issue thread, run after
  all services are confirmed healthy

### Upgrade: `sslmode=verify-full` (platform#53)

Platform#53 upgraded to `sslmode=verify-full` with CA certificate distribution. See
[database-ssl-verify-full.md](database-ssl-verify-full.md) for the full configuration,
CA certificate setup, key management, and troubleshooting guide.
