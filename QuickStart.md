# QuickStart Guide

## Production Deployment

Deploy the platform to a DigitalOcean Droplet with the **Olympus CLI**.

### Prerequisites

- [Node.js 20+](https://nodejs.org/)
- [GitHub CLI](https://cli.github.com/) — run `gh auth login` first

Optional (the CLI will tell you if needed):
- [doctl](https://docs.digitalocean.com/reference/doctl/) — only if creating a new Droplet

### Run the Olympus CLI

```bash
cd octl && bun install && bun link
octl
```

The CLI walks you through each step interactively. You'll need:

| What | Where to get it |
|------|-----------------|
| Your domain name | e.g., `example.com` |
| A passphrase | Used to derive all secrets deterministically |
| Resend API key | [resend.com/api-keys](https://resend.com/api-keys) |
| Hostinger API token | [hpanel.hostinger.com](https://hpanel.hostinger.com) (optional — can set DNS manually) |
| GitHub PAT | [github.com/settings/tokens](https://github.com/settings/tokens) — scope: `read:packages` |
| DigitalOcean API token | [cloud.digitalocean.com/account/api](https://cloud.digitalocean.com/account/api/tokens) (only if creating a new Droplet) |

You can select which steps to run — useful for re-running a single step (e.g., updating DNS after a Droplet IP change).

> For manual setup or reference, see [Secrets.md](./Secrets.md).

---

## Local Development

Get the OlympusOSS Identity Platform running locally in under 5 minutes.

> **macOS Instructions** — All commands below are for macOS using Homebrew.

---

### Prerequisites

### 1. Install Homebrew

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

### 2. Install Git

```bash
brew install git
```

### 3. Install Bun

```bash
brew install oven-sh/bun/bun
```

> **Note:** Podman, podman-compose, and kubectl are auto-installed by `octl dev` via Homebrew. No manual installation needed.

---

## Quick Start

### 1. Clone the repository

```bash
git clone git@github.com:bnannier/OlympusOSS.git
cd OlympusOSS
```

### 2. Install the CLI

```bash
cd octl && bun install && bun link
```

### 3. Start the platform

```bash
octl dev
```

The CLI installs Podman and podman-compose (if needed), initializes the Podman machine, builds images, starts all services in the correct order, runs migrations, seeds test data, and verifies health. The first run takes a few minutes.

---

## Access Points

| Application     | URL                   | Description                                  |
|-----------------|-----------------------|----------------------------------------------|
| **Site**        | http://localhost:2000 | Brochure site & OAuth2 playground            |
| **CIAM Athena** | http://localhost:3003 | Admin panel for customer identity management |
| **IAM Athena**  | http://localhost:4003 | Admin panel for employee identity management |
| **PgAdmin**     | http://localhost:4000 | Database management interface                |
| **Mailslurper** | http://localhost:4436 | Test email inbox                             |

---

## Test Credentials

### IAM (Employee) Users

| Email               | Password    | Role                                |
|---------------------|-------------|-------------------------------------|
| `admin@demo.user`   | `admin123!` | Admin — full access to all features |
| `viewer@demo.user`  | `admin123!` | Viewer — read-only access           |

Use these to log into **CIAM Athena** (http://localhost:3003) and **IAM Athena** (http://localhost:4003).

### CIAM (Customer) Users

| Email                     | Password    | Customer ID |
|---------------------------|-------------|-------------|
| `bobby.nannier@gmail.com` | `admin123!` | CUST-001    |
| `bobby@nannier.com`       | `admin123!` | CUST-002    |

These are customer identities managed through CIAM Athena. They cannot log into the admin panels.

### PgAdmin

| Email              | Password    |
|--------------------|-------------|
| `admin@demo.user` | `admin123!` |

---

## What Gets Deployed

### Customer Identity (CIAM) — ports 3xxx

| Port | Service              | Purpose                        |
|------|----------------------|--------------------------------|
| 3001 | CIAM Hera            | Customer login, consent & logout UI |
| 3003 | CIAM Athena          | Customer admin panel           |
| 3100 | CIAM Kratos (public) | Customer identity API          |
| 3101 | CIAM Kratos (admin)  | Customer identity admin API    |
| 3102 | CIAM Hydra (public)  | Customer OAuth2/OIDC endpoints |
| 3103 | CIAM Hydra (admin)   | Customer OAuth2 admin API      |

### Employee Identity (IAM) — ports 4xxx

| Port | Service             | Purpose                        |
|------|---------------------|--------------------------------|
| 4001 | IAM Hera            | Employee login, consent & logout UI |
| 4003 | IAM Athena          | Employee admin panel           |
| 4100 | IAM Kratos (public) | Employee identity API          |
| 4101 | IAM Kratos (admin)  | Employee identity admin API    |
| 4102 | IAM Hydra (public)  | Employee OAuth2/OIDC endpoints |
| 4103 | IAM Hydra (admin)   | Employee OAuth2 admin API      |

### Shared Services

| Port | Service     | Purpose             |
|------|-------------|---------------------|
| 2000 | Site        | Brochure site & OAuth2 playground |
| 4000 | PgAdmin     | Database management |
| 4436 | Mailslurper | Test email service  |
| 5432 | PostgreSQL  | Database            |

---

## Common Commands

All commands should be run from the `dev/` directory.

```bash
# Restart all containers
podman compose -f compose.dev.yml restart

# Rebuild from scratch (wipes all data)
podman compose -f compose.dev.yml down -v && podman compose -f compose.dev.yml up -d --build

# View logs for a specific service
podman compose -f compose.dev.yml logs -f <service-name>

# Check seed status
podman compose -f compose.dev.yml logs athena-seed-dev

# Stop everything
podman compose -f compose.dev.yml down

# Stop everything and wipe all data
podman compose -f compose.dev.yml down -v --remove-orphans
```

---

## Troubleshooting

**Container keeps crashing:**
```bash
podman compose -f compose.dev.yml restart <service-name>
```

**Seed didn't run or failed:**
```bash
podman compose -f compose.dev.yml restart athena-seed-dev
podman compose -f compose.dev.yml logs -f athena-seed-dev
```

**Login not working after fresh deploy:**

Wait 30 seconds for the seed script to finish creating test users. Check with:
```bash
podman compose -f compose.dev.yml logs athena-seed-dev
```

**Clean slate — start completely fresh:**
```bash
podman compose -f compose.dev.yml down -v --remove-orphans
octl dev
```

**Port already in use:**
```bash
# Find what's using the port (e.g., 3003)
lsof -i :3003
# Kill the process
kill -9 <PID>
```

