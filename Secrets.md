# Secrets & Deployment Setup Guide

Everything is configured through external dashboards and GitHub. The deploy workflow handles directory creation, config syncing, `.env` generation, GHCR authentication, service startup, and seeding automatically. All steps are idempotent — running the workflow multiple times is safe.

**Prerequisites:** A DigitalOcean Droplet with Docker and Docker Compose installed, accessible via SSH.

> **Prefer automation?** Run `cd cli && npm install && npm run octl` — see [QuickStart Guide](./QuickStart.md#production-deployment).

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

### A Records (point subdomains to Droplet IP)

| Type | Name | Value | TTL |
|------|------|-------|-----|
| A | `login.ciam` | `DROPLET_IP` | 3600 |
| A | `login.iam` | `DROPLET_IP` | 3600 |
| A | `oauth.ciam` | `DROPLET_IP` | 3600 |
| A | `oauth.iam` | `DROPLET_IP` | 3600 |
| A | `admin.ciam` | `DROPLET_IP` | 3600 |
| A | `admin.iam` | `DROPLET_IP` | 3600 |
| A | `olympus` | `DROPLET_IP` | 3600 |

Replace `DROPLET_IP` with the Droplet's public IP address.

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

## 5. Environment Secrets

Set these under **Settings → Environments → production → Environment secrets**:

### Infrastructure

| Secret | Description | How to generate |
|--------|-------------|-----------------|
| `DEPLOY_SSH_KEY` | Private SSH key for Droplet | `ssh-keygen -t ed25519 -C "github-deploy"` — add public key to Droplet's `~/.ssh/authorized_keys` |
| `DEPLOY_USER` | SSH username | e.g., `deploy` or `root` |
| `DEPLOY_SERVER_IP` | Droplet public IP | From DigitalOcean dashboard |
| `GHCR_PAT` | GitHub PAT for pulling images | Create at github.com/settings/tokens — scope: `read:packages` |

### PostgreSQL

| Secret | How to generate |
|--------|-----------------|
| `POSTGRES_PASSWORD` | `openssl rand -hex 32` |

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

### SMTP (Resend)

| Secret | How to get |
|--------|------------|
| `RESEND_API_KEY` | From Resend dashboard (step 1) |

### OAuth2 Client Secrets

| Secret | How to generate |
|--------|-----------------|
| `ATHENA_CIAM_OAUTH_CLIENT_SECRET` | `openssl rand -hex 32` |
| `ATHENA_IAM_OAUTH_CLIENT_SECRET` | `openssl rand -hex 32` |
| `DEMO_CIAM_CLIENT_SECRET` | `openssl rand -hex 32` (optional — demo only) |
| `DEMO_IAM_CLIENT_SECRET` | `openssl rand -hex 32` (optional — demo only) |

### Admin

| Secret | Description |
|--------|-------------|
| `ADMIN_PASSWORD` | Initial admin user password |

---

## 6. Environment Variables

Set these under **Settings → Environments → production → Environment variables**:

### Infrastructure

| Variable | Example | Default |
|----------|---------|---------|
| `DEPLOY_PATH` | `/opt/olympusoss/prod` | `/opt/olympusoss/prod` |
| `DEPLOY_SSH_PORT` | `22` | `22` |
| `GHCR_USERNAME` | `bnannier` | — |

### Domain URLs

| Variable | Example |
|----------|---------|
| `CIAM_HERA_PUBLIC_URL` | `https://login.ciam.example.com` |
| `IAM_HERA_PUBLIC_URL` | `https://login.iam.example.com` |
| `CIAM_HYDRA_PUBLIC_URL` | `https://oauth.ciam.example.com` |
| `IAM_HYDRA_PUBLIC_URL` | `https://oauth.iam.example.com` |
| `CIAM_ATHENA_PUBLIC_URL` | `https://admin.ciam.example.com` |
| `IAM_ATHENA_PUBLIC_URL` | `https://admin.iam.example.com` |
| `DEMO_PUBLIC_URL` | `https://olympus.example.com` |

### Email

| Variable | Example |
|----------|---------|
| `SMTP_FROM_EMAIL` | `noreply@example.com` |

### OAuth2 Client IDs

| Variable | Default |
|----------|---------|
| `ATHENA_CIAM_OAUTH_CLIENT_ID` | `athena-ciam-client` |
| `ATHENA_IAM_OAUTH_CLIENT_ID` | `athena-iam-client` |
| `DEMO_CIAM_CLIENT_ID` | `demo-ciam-client` |
| `DEMO_IAM_CLIENT_ID` | `demo-iam-client` |

### Admin & Image Tags

| Variable | Default |
|----------|---------|
| `ADMIN_EMAIL` | `admin@example.com` |
| `HERA_IMAGE_TAG` | `latest` |
| `ATHENA_IMAGE_TAG` | `latest` |
| `DEMO_IMAGE_TAG` | `latest` |

---

## 7. Deploy

Once steps 1–6 are complete:

1. Go to **Actions → Deploy → Run workflow**
2. Select `production` environment
3. Click **Run workflow**

The workflow will automatically:
- Create the deploy directory on the Droplet
- Sync all configs (docker-compose, Ory configs, seed script)
- Generate `.env` from your GitHub secrets and variables
- Authenticate Docker with GHCR
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
