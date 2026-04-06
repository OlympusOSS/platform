# Platform

Infrastructure and orchestration for the [OlympusOSS Identity Platform](https://github.com/OlympusOSS).

Podman Compose configs, Ory configs, identity schemas, seed scripts, and CI/CD workflows.

---

## Quick Start

```bash
octl dev
```

The CLI installs Podman (if needed), starts all containers in the correct order, and seeds test data.

Alternatively, start manually:

```bash
cd dev
podman compose -f compose.dev.yml up -d
podman compose -f compose.dev.yml logs -f athena-seed-dev
```

Once you see **"Seed complete!"**, the platform is ready.

### Access Points

| App | URL | Description |
|-----|-----|-------------|
| Site | http://localhost:2000 | Brochure site & OAuth2 playground |
| CIAM Athena | http://localhost:3001 | Customer identity admin |
| IAM Athena | http://localhost:4001 | Employee identity admin |
| pgAdmin | http://localhost:5433 | Database management |
| Mailslurper | http://localhost:5434 | Test email inbox |

### Test Credentials

| Email | Password | Domain |
|-------|----------|--------|
| `admin@demo.user` | `admin123!` | IAM (admin) |
| `viewer@demo.user` | `admin123!` | IAM (viewer) |
| `bobby.nannier@gmail.com` | `admin123!` | CIAM (customer) |
| `bobby@nannier.com` | `admin123!` | CIAM (customer) |

---

## What's In This Repo

### `dev/` — Development Environment

Podman Compose with 15 services, all on a single `intranet` network:

| Service | Port | Purpose |
|---------|------|---------|
| PostgreSQL | 5432 | Shared database (4 logical databases) |
| CIAM Hera | 3000 | Customer login/consent UI |
| CIAM Athena | 3001 | Customer admin panel |
| CIAM Kratos | 3100/3101 | Customer identity API |
| CIAM Hydra | 3102/3103 | Customer OAuth2 server |
| IAM Hera | 4000 | Employee login/consent UI |
| IAM Athena | 4001 | Employee admin panel |
| IAM Kratos | 4100/4101 | Employee identity API |
| IAM Hydra | 4102/4103 | Employee OAuth2 server |
| Site | 2000 | Brochure site & OAuth2 playground |
| pgAdmin | 5433 | Database UI (OAuth2 SSO via IAM) |
| Mailslurper | 5434 | Test email service |

### `prod/` — Production Environment

Same services with:
- Environment variable substitution (`.env` file)
- Health checks on all services
- Optional profiles (`migration`, `seed`)
- No hardcoded secrets

### Ory Configs

| Directory | Contents |
|-----------|----------|
| `*/ciam-kratos/` | Kratos config + identity schemas (default, customer, organizational) |
| `*/ciam-hydra/` | Hydra config (OAuth2/OIDC settings) |
| `*/iam-kratos/` | Kratos config + admin identity schema |
| `*/iam-hydra/` | Hydra config (OAuth2/OIDC settings) |

### Identity Schemas

- **Customer** (`customer.schema.json`) — Email, name, customer ID, phone, address, preferences, loyalty tier
- **Organizational** (`company-identity.schema.json`) — Company/business identities
- **Default** (`identity.schema.json`) — Generic person schema
- **Admin** (`admin-identity.schema.json`) — Email, name, role (admin/viewer)

### Seed Scripts

- **`dev/iam-seed-dev.sh`** — Creates test identities and OAuth2 clients for local development
- **`prod/seed-prod.sh`** — Creates admin identity and OAuth2 clients from environment variables (idempotent)

### CI/CD

- **`.github/workflows/deploy.yml`** — Manual deployment to a DigitalOcean Droplet via SSH
  - Syncs configs, generates `.env`, authenticates to GHCR, pulls images, starts services, seeds data
- **`.github/dependabot.yml`** — Automated dependency updates for container images and GitHub Actions

---

## Live Reload (Development)

App repos are sibling directories mounted as volumes for hot reload. Copy the override template:

```bash
cp compose.override.example.yml compose.override.yml
```

This mounts `../../athena/`, `../../hera/`, and `../../site/` into their containers.

---

## Common Commands

```bash
# Start everything (recommended)
octl dev

# Or start manually
podman compose -f compose.dev.yml up -d

# Rebuild from scratch (wipes data)
podman compose -f compose.dev.yml down -v && podman compose -f compose.dev.yml up -d --build

# View logs for a service
podman compose -f compose.dev.yml logs -f ciam-athena

# Stop everything
podman compose -f compose.dev.yml down

# Stop and wipe all data
podman compose -f compose.dev.yml down -v --remove-orphans
```

---

## Database

Single PostgreSQL instance with 4 logical databases:

| Database | Domain | Used By |
|----------|--------|---------|
| `ciam_kratos` | Customer | CIAM Kratos |
| `ciam_hydra` | Customer | CIAM Hydra |
| `iam_kratos` | Employee | IAM Kratos |
| `iam_hydra` | Employee | IAM Hydra |

Initialized by `init-db.sql` on first startup.

---

## Production Deployment

See [Secrets.md](./Secrets.md) for manual setup, or use the [octl CLI](https://github.com/OlympusOSS/octl) for automated deployment.

### Pre-deployment Secrets Checklist

Before deploying to production, verify that all nine required secrets are set in GitHub Actions Secrets. The version-controlled audit document lists every secret, its purpose, generation command, and the consequence if it is missing or empty.

**[docs/secrets-audit.md](./docs/secrets-audit.md)** — pre-deployment checklist and SOC2 CC6.1 evidence artifact.

Key rules:
- All nine secrets must be set before running `deploy.yml` — missing secrets cause container startup failures, not silent misconfiguration
- Ory Kratos and Hydra refuse to start with empty secret values (empirically verified — see the audit document)
- The SDK validates `ENCRYPTION_KEY` at module load — a missing key causes the Next.js container to crash before serving any requests
- Do not rotate pairwise salts (`CIAM_HYDRA_PAIRWISE_SALT`, `IAM_HYDRA_PAIRWISE_SALT`) without reading the rotation procedure first — rotation changes OIDC `sub` claims for all users across all OAuth2 clients

---

## Security Operations

### Security Headers

The production Caddy reverse proxy applies structural security headers (HSTS, X-Frame-Options,
X-Content-Type-Options, Referrer-Policy, Permissions-Policy) via two Caddyfile snippets. Hera
and Athena apply Content-Security-Policy via per-request nonce-based Next.js middleware. Each
header is owned by exactly one layer.

**Breaking change**: `frame-ancestors 'none'` in the CSP means Hera and Athena cannot be embedded
in iframes. Any integration that relied on iframe embedding of the login, consent, or admin pages
must move to a redirect-based OAuth2 flow.

See [docs/security-headers.md](./docs/security-headers.md) for the full reference including vhost
assignment table, nonce propagation pattern, operator runbook for Caddyfile changes, and CSP
troubleshooting.

### Database SSL

All five PostgreSQL connections use `sslmode=require` in production (implemented in platform#19).
`sslmode=require` encrypts connections but does not validate the server certificate; `verify-full`
is tracked in platform#53.

**Pre-deployment checklist item**: before any deployment, verify the `PG_SSLMODE` GitHub Variable
is either absent or set to `require`. If `PG_SSLMODE=disable` is still set, it silently overrides
the `deploy.yml` default and all connections remain plaintext — there is no error or warning.

See [docs/database-ssl.md](./docs/database-ssl.md) for the full reference including pre-deployment
checklist, certificate management, SOC2 CC6.1 evidence queries, and troubleshooting for the three
common SSL deployment failures.

### pgAdmin Access Control

pgAdmin is restricted to pre-provisioned DBAs with the `dba` role in IAM Kratos. Access is
enforced by three independent layers: network restriction (port 5433 not publicly accessible),
pre-provisioning gate (`OAUTH2_AUTO_CREATE_USER = False`), and role claim validation
(`OAUTH2_ADDITIONAL_CLAIMS_VALIDATION`).

**Global claims mapper note**: due to a Hydra v26.2.0 limitation, the IAM Hydra claims mapper is
configured globally (`oidc.claims_mapper.filepath` in `hydra.yml`). All IAM Hydra ID tokens include
a `roles` array claim. Any new IAM Hydra OAuth2 client integration must account for this claim.

**Active session gap**: removing the `dba` role from an IAM identity prevents new logins but does
not terminate active pgAdmin sessions (session lifetime: 1 day). For time-sensitive DBA removals,
execute session revocation (step 4 of the offboarding runbook) immediately.

See [docs/pgadmin-access.md](./docs/pgadmin-access.md) for the DBA provisioning runbook,
Jsonnet claims mapper configuration, and the Hydra v26.2.0 global mapper ADR.
See [docs/runbook-pgadmin-dba-offboarding.md](./docs/runbook-pgadmin-dba-offboarding.md) for the
complete four-step offboarding procedure.

### Rate Limiting

The production login endpoint has two independent rate limiting layers — Caddy (per-IP) and SDK (per-account lockout). See [docs/rate-limiting.md](./docs/rate-limiting.md) for the full reference including error response shapes, configuration keys, and integration examples.

### Credential Rotation

| Credential | Runbook |
|-----------|---------|
| All production secrets (Kratos, Hydra, SDK) | [docs/secrets-audit.md](./docs/secrets-audit.md) — Section 8 |
| `CIAM_RELOAD_API_KEY` (sidecar auth key) | [docs/reload-api-key-rotation.md](./docs/reload-api-key-rotation.md) |

All production credential rotations must go through GitHub Actions (deploy.yml). Direct SSH
or manual server access for credential rotation is prohibited by the platform deployment policy.

### Security Decisions

Architectural security decisions are recorded at the point they are made so future engineers do not have to rediscover the rationale.

| Decision | Document |
|----------|---------|
| Email verification enforcement — which config key enforces it (hook vs. method) | [docs/email-verification.md](./docs/email-verification.md) |
| OIDC social login — whether provider `email_verified: true` is trusted by Kratos | [docs/oidc-email-verified-trust-decision.md](./docs/oidc-email-verified-trust-decision.md) |

The OIDC trust decision must be revisited explicitly in the Architecture Brief for any story that adds an OIDC provider to the CIAM Kratos configuration. The decision document is a prerequisite for that Brief to be approved.

---

## License

MIT
