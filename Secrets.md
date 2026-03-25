# Secrets & Deployment Setup Guide

Everything is configured through external dashboards and GitHub. The deploy workflow handles directory creation, config syncing, `.env` generation, GHCR authentication, service startup, and seeding automatically. All steps are idempotent — running the workflow multiple times is safe.

**Prerequisites:** A VPS (Hostinger KVM or DigitalOcean Droplet) with Podman and Podman Compose installed, accessible via SSH.

> **Prefer automation?** Run `cd octl && bun install && bun link && octl` — see [QuickStart Guide](./QuickStart.md#production-deployment).

---

## 1. Resend Setup

Resend handles transactional email (verification, password reset). No other prerequisites needed.

1. Create a Resend account at https://resend.com
2. Add your domain under **Domains → Add Domain**
3. Note the DNS records Resend provides — you'll add them in Hostinger (step 2)
4. Generate an API key under **API Keys** (starts with `re_`) — save it for step 3

---

## 2. Hostinger DNS Setup

Configure DNS in Hostinger: **Domains → your domain → DNS / Nameservers → DNS Records**

### A Records (point subdomains to server IP)

| Type | Name | Value | TTL |
|------|------|-------|-----|
| A | `login.ciam` | `SERVER_IP` | 3600 |
| A | `login.iam` | `SERVER_IP` | 3600 |
| A | `oauth.ciam` | `SERVER_IP` | 3600 |
| A | `oauth.iam` | `SERVER_IP` | 3600 |
| A | `admin.ciam` | `SERVER_IP` | 3600 |
| A | `admin.iam` | `SERVER_IP` | 3600 |
| A | `olympus` | `SERVER_IP` | 3600 |
| A | `pgadmin` | `SERVER_IP` | 3600 |

Replace `SERVER_IP` with your VPS public IP address.

### Resend Email DNS Records (from step 1)

Add the DNS records Resend provided when you added your domain:

| Type | Name | Value | Purpose |
|------|------|-------|---------|
| MX | Your domain | `feedback-smtp.us-east-1.amazonses.com` | Resend mail routing |
| TXT | Your domain | `v=spf1 include:amazonses.com ~all` | SPF — authorizes Resend to send |
| CNAME | `resend._domainkey` | *(provided by Resend)* | DKIM — email signing |
| TXT | `_dmarc` | `v=DMARC1; p=none;` | DMARC policy |

> The exact DKIM CNAME value is generated when you add the domain in Resend. Copy it from the Resend dashboard.

After adding the records:
1. Wait for DNS propagation (can take up to 48h, usually minutes)
2. Click **Verify** in the Resend dashboard

---

## 3. GitHub Environment

Create an environment in your repo: **Settings → Environments → New environment**

- `production`

> A `staging` environment can be added later — create it in GitHub, add its own secrets/variables, and uncomment the staging option in `.github/workflows/deploy.yml`.

---

## 4. Repository Secrets

Set these under **Settings → Secrets and variables → Actions → Repository secrets** (not environment-scoped):

| Secret | Description | How to generate |
|--------|-------------|-----------------|
| `NPM_TOKEN` | Publish Olympus CLI to npm | Create at [npmjs.com/settings/tokens](https://www.npmjs.com/settings/~/tokens) — type: Automation |

---

## 5. Organization Secrets

Set these as **org-level secrets** (visible to all repos): **Settings → Secrets and variables → Actions → Organization secrets**

> `octl prod deploy` automates this — derives all secrets from a single passphrase via PBKDF2.

### Infrastructure

| Secret | Description | How to generate |
|--------|-------------|-----------------|
| `DEPLOY_SSH_KEY` | Private SSH key for server | `ssh-keygen -t ed25519 -C "github-deploy"` — add public key to server's `~/.ssh/authorized_keys` |
| `GHCR_PAT` | GitHub PAT for pulling images | Create at github.com/settings/tokens — scope: `read:packages` |

### PostgreSQL

| Secret | Description | How to generate |
|--------|-------------|-----------------|
| `PG_DSN_BASE` | Base PostgreSQL connection string. User and password are parsed from this to configure the postgres container and pgAdmin. | Self-hosted: `postgres://olympus:<password>@postgres:5432` — External (e.g., RDS, Cloud SQL): `postgres://user:pass@host:5432` |

### Application Settings

| Secret | How to generate | Notes |
|--------|-----------------|-------|
| `ENCRYPTION_KEY` | `openssl rand -hex 16` | AES-256-GCM key for SDK settings vault — exactly 32 hex chars |

### Ory Kratos

| Secret | How to generate | Notes |
|--------|-----------------|-------|
| `CIAM_KRATOS_SECRET_COOKIE` | `openssl rand -hex 32` | Signs session cookies |
| `CIAM_KRATOS_SECRET_CIPHER` | `openssl rand -hex 16` | Must be exactly 32 chars — encrypts data at rest |
| `IAM_KRATOS_SECRET_COOKIE` | `openssl rand -hex 32` | Signs session cookies |
| `IAM_KRATOS_SECRET_CIPHER` | `openssl rand -hex 16` | Must be exactly 32 chars — encrypts data at rest |

### Ory Hydra

| Secret | How to generate | Notes |
|--------|-----------------|-------|
| `CIAM_HYDRA_SECRET_SYSTEM` | `openssl rand -hex 32` | Signs OAuth2 tokens |
| `CIAM_HYDRA_PAIRWISE_SALT` | `openssl rand -hex 32` | OIDC pairwise subject salt — never rotate |
| `IAM_HYDRA_SECRET_SYSTEM` | `openssl rand -hex 32` | Signs OAuth2 tokens |
| `IAM_HYDRA_PAIRWISE_SALT` | `openssl rand -hex 32` | OIDC pairwise subject salt — never rotate |

### SMTP

| Secret | Description | Example |
|--------|-------------|---------|
| `SMTP_CONNECTION_URI` | Full SMTP connection URI (provider-agnostic) | `smtps://resend:re_xxx@smtp.resend.com:465/` |

### OAuth2 Client Secrets

| Secret | How to generate |
|--------|-----------------|
| `ATHENA_CIAM_OAUTH_CLIENT_SECRET` | `openssl rand -hex 32` |
| `ATHENA_IAM_OAUTH_CLIENT_SECRET` | `openssl rand -hex 32` |
| `SITE_CIAM_CLIENT_SECRET` | `openssl rand -hex 32` |
| `SITE_IAM_CLIENT_SECRET` | `openssl rand -hex 32` |
| `PGADMIN_OAUTH_CLIENT_SECRET` | `openssl rand -hex 32` |

### Admin

| Secret | Description |
|--------|-------------|
| `ADMIN_PASSWORD` | Initial admin user password |

---

## 6. Organization Variables

Set these as **org-level variables**: **Settings → Secrets and variables → Actions → Organization variables**

All service URLs (Hera, Hydra, Athena, Site, pgAdmin) are **derived from `DOMAIN`** in the deploy workflow — no need to set them individually.

| Variable | Description | Example | Default |
|----------|-------------|---------|---------|
| `DOMAIN` | Base domain — all service URLs derived from this | `example.com` | — |
| `DEPLOY_SERVER_IP` | VPS public IP address | `187.124.155.219` | — |
| `DEPLOY_PATH` | Remote deploy directory | `/opt/olympusoss/prod` | `/opt/olympusoss/prod` |
| `DEPLOY_SSH_PORT` | SSH port on the server | `22` | `22` |
| `GHCR_USERNAME` | GitHub username for GHCR pulls | `bnannier` | — |
| `PG_SSLMODE` | `disable` for self-hosted container, `require` for external providers | `disable` | `disable` |

---

## 7. Deploy

Once steps 1–6 are complete:

1. Go to **Actions → Deploy → Run workflow**
2. Select `production` environment
3. Click **Run workflow**

The workflow will automatically:
- Create the deploy directory on the Droplet
- Sync all configs (compose files, Ory configs, seed script)
- Generate `.env` from your GitHub secrets and variables
- Authenticate Podman with GHCR
- Pull and start all services
- Run the seed script (creates admin identity + OAuth2 clients if they don't already exist)
- Report health status

---

## 8. Secret Rotation

| Secret | Impact | Procedure |
|--------|--------|-----------|
| Kratos cookie secrets | Invalidates all sessions | Update secret in GitHub, re-run Deploy |
| Kratos cipher secrets | **Cannot rotate** without data migration | Requires Kratos migration tooling |
| Hydra system secrets | Invalidates all tokens | Update secret in GitHub, re-run Deploy |
| Hydra pairwise salt | **Breaks OIDC subject IDs** | Should never be rotated |
| OAuth2 client secrets | Breaks auth flows until restarted | Update secret in GitHub, re-run Deploy |
| PostgreSQL password | Breaks all DB connections | Update secret in GitHub, re-run Deploy |
