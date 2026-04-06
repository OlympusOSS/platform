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

---

## Security Operations

### Credential Rotation

| Credential | Runbook |
|-----------|---------|
| `CIAM_RELOAD_API_KEY` (sidecar auth key) | [docs/reload-api-key-rotation.md](./docs/reload-api-key-rotation.md) |

All production credential rotations must go through GitHub Actions (deploy.yml). Direct SSH
or manual server access for credential rotation is prohibited by the platform deployment policy.

---

## License

MIT
