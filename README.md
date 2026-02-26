# Platform

Infrastructure and orchestration for the [OlympusOSS Identity Platform](https://github.com/OlympusOSS).

Docker Compose configs, Ory configs, identity schemas, seed scripts, and CI/CD workflows.

---

## Quick Start

```bash
cd dev
docker compose up -d
```

Wait for the seed to complete:

```bash
docker compose logs -f athena-seed-dev
```

Once you see **"Seed complete!"**, the platform is ready.

### Access Points

| App | URL | Description |
|-----|-----|-------------|
| Demo | http://localhost:2000 | OAuth2 test client |
| CIAM Athena | http://localhost:3003 | Customer identity admin |
| IAM Athena | http://localhost:4003 | Employee identity admin |
| pgAdmin | http://localhost:4000 | Database management |
| Mailslurper | http://localhost:4436 | Test email inbox |

### Test Credentials

| Email | Password | Domain |
|-------|----------|--------|
| `admin@athena.dev` | `admin123!` | IAM (admin) |
| `viewer@athena.dev` | `admin123!` | IAM (viewer) |
| `bobby.nannier@gmail.com` | `admin123!` | CIAM (customer) |
| `bobby@nannier.com` | `admin123!` | CIAM (customer) |

---

## What's In This Repo

### `dev/` — Development Environment

Docker Compose with 15 services, all on a single `intranet` network:

| Service | Port | Purpose |
|---------|------|---------|
| PostgreSQL | 5432 | Shared database (4 logical databases) |
| CIAM Kratos | 3100/3101 | Customer identity API |
| CIAM Hydra | 3102/3103 | Customer OAuth2 server |
| CIAM Hera | 3001 | Customer login/consent UI |
| CIAM Athena | 3003 | Customer admin panel |
| IAM Kratos | 4100/4101 | Employee identity API |
| IAM Hydra | 4102/4103 | Employee OAuth2 server |
| IAM Hera | 4001 | Employee login/consent UI |
| IAM Athena | 4003 | Employee admin panel |
| Demo | 2000 | OAuth2 test client |
| pgAdmin | 4000 | Database UI (OAuth2 SSO via IAM) |
| Mailslurper | 4436 | Test email service |

### `prod/` — Production Environment

Same services with:
- Environment variable substitution (`.env` file)
- Health checks on all services
- Optional profiles (`demo`, `seed`)
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
- **`.github/dependabot.yml`** — Automated dependency updates for Docker images and GitHub Actions

---

## Live Reload (Development)

App repos are sibling directories mounted as volumes for hot reload. Copy the override template:

```bash
cp docker-compose.override.example.yml docker-compose.override.yml
```

This mounts `../../athena/`, `../../hera/`, and `../../demo/` into their containers.

---

## Common Commands

```bash
# Start everything
docker compose up -d

# Rebuild from scratch (wipes data)
docker compose down -v && docker compose up -d --build

# View logs for a service
docker compose logs -f ciam-athena

# Stop everything
docker compose down

# Stop and wipe all data
docker compose down -v --remove-orphans
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

## License

MIT
