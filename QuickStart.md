# QuickStart Guide

Get the OlympusOSS Identity Platform running locally in under 5 minutes.

> **macOS Instructions** — All commands below are for macOS using Homebrew.

---

## Prerequisites

### 1. Install Homebrew

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

### 2. Install Git

```bash
brew install git
```

### 3. Install Docker Desktop

```bash
brew install --cask docker
```

After installation, open **Docker Desktop** from Applications and ensure it is running. Allocate at least **4 GB of RAM** in Docker Desktop settings (Settings > Resources) — the platform runs 15 containers simultaneously.

### 4. Install Bun (optional)

Only needed if you plan to develop outside of Docker.

```bash
brew install oven-sh/bun/bun
```

---

## Quick Start

### 1. Clone the repository

```bash
git clone git@github.com:bnannier/OlympusOSS.git
cd OlympusOSS
```

### 2. Start the platform

```bash
cd dev && docker compose up -d
```

This pulls all images, builds the application containers, runs database migrations, starts all services, and seeds test data. The first run takes a few minutes.

### 3. Wait for the seed to complete

```bash
docker compose logs -f athena-seed-dev
```

Wait until you see **"Seed complete!"**, then press `Ctrl+C`.

---

## Access Points

| Application     | URL                   | Description                                  |
|-----------------|-----------------------|----------------------------------------------|
| **Demo App**    | http://localhost:2000 | OAuth2 test client for both domains          |
| **CIAM Athena** | http://localhost:3003 | Admin panel for customer identity management |
| **IAM Athena**  | http://localhost:4003 | Admin panel for employee identity management |
| **PgAdmin**     | http://localhost:4000 | Database management interface                |
| **Mailslurper** | http://localhost:4436 | Test email inbox                             |

---

## Test Credentials

### IAM (Employee) Users

| Email               | Password    | Role                                |
|---------------------|-------------|-------------------------------------|
| `admin@athena.dev`  | `admin123!` | Admin — full access to all features |
| `viewer@athena.dev` | `admin123!` | Viewer — read-only access           |

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
| `admin@athena.dev` | `admin123!` |

---

## What Gets Deployed

### Customer Identity (CIAM) — ports 3xxx

| Port | Service              | Purpose                        |
|------|----------------------|--------------------------------|
| 3001 | CIAM Hera            | Customer authentication UI     |
| 3002 | CIAM Medusa          | Customer OAuth2 consent UI     |
| 3003 | CIAM Athena          | Customer admin panel           |
| 3100 | CIAM Kratos (public) | Customer identity API          |
| 3101 | CIAM Kratos (admin)  | Customer identity admin API    |
| 3102 | CIAM Hydra (public)  | Customer OAuth2/OIDC endpoints |
| 3103 | CIAM Hydra (admin)   | Customer OAuth2 admin API      |

### Employee Identity (IAM) — ports 4xxx

| Port | Service             | Purpose                        |
|------|---------------------|--------------------------------|
| 4001 | IAM Hera            | Employee authentication UI     |
| 4002 | IAM Medusa          | Employee OAuth2 consent UI     |
| 4003 | IAM Athena          | Employee admin panel           |
| 4100 | IAM Kratos (public) | Employee identity API          |
| 4101 | IAM Kratos (admin)  | Employee identity admin API    |
| 4102 | IAM Hydra (public)  | Employee OAuth2/OIDC endpoints |
| 4103 | IAM Hydra (admin)   | Employee OAuth2 admin API      |

### Shared Services

| Port | Service     | Purpose             |
|------|-------------|---------------------|
| 2000 | Demo App    | OAuth2 test client  |
| 4000 | PgAdmin     | Database management |
| 4436 | Mailslurper | Test email service  |
| 5432 | PostgreSQL  | Database            |

---

## Common Commands

All commands should be run from the `dev/` directory.

```bash
# Restart all containers
docker compose restart

# Rebuild from scratch (wipes all data)
docker compose down -v && docker compose up -d --build

# View logs for a specific service
docker compose logs -f <service-name>

# Check seed status
docker compose logs athena-seed-dev

# Stop everything
docker compose down

# Stop everything and wipe all data
docker compose down -v --remove-orphans
```

---

## Troubleshooting

**Container keeps crashing:**
```bash
docker compose restart <service-name>
```

**Seed didn't run or failed:**
```bash
docker compose restart athena-seed-dev
docker compose logs -f athena-seed-dev
```

**Login not working after fresh deploy:**

Wait 30 seconds for the seed script to finish creating test users. Check with:
```bash
docker compose logs athena-seed-dev
```

**Clean slate — start completely fresh:**
```bash
docker compose down -v --remove-orphans
docker compose up -d
```

**Port already in use:**
```bash
# Find what's using the port (e.g., 3003)
lsof -i :3003
# Kill the process
kill -9 <PID>
```
