# Platform Network Topology and Port Exposure

## Overview

The Olympus platform runs as a Podman Compose stack on a single host. All inter-service communication happens within the private `intranet` Compose network. Only specific ports are bound to the host interface — everything else is internal-only.

Controlling which ports are host-bound is a security requirement. Caddy is the single public ingress point. Bypassing Caddy (by reaching a service directly on a host-bound port) circumvents rate limiting (platform#22) and exposes services to direct internet access if the host firewall is permissive.

This document was last updated in platform#55, which verified and documented the Hera port binding constraints.

---

## Host-Bound Ports (Production)

These ports are published to the host interface in `compose.prod.yml`:

| Port | Service | Purpose | Interface |
|------|---------|---------|-----------|
| 80 | Caddy | HTTP (redirects to HTTPS) | 0.0.0.0 |
| 443 | Caddy | HTTPS ingress — the only public entry point | 0.0.0.0 |
| 3100 | CIAM Kratos public | Dev/admin tooling access | 0.0.0.0 (consider restricting to 127.0.0.1 in prod) |
| 3101 | CIAM Kratos admin | Dev/admin tooling | 0.0.0.0 — **must be blocked at the host firewall; not internet-accessible** |
| 3103 | CIAM Hydra admin | Dev/admin tooling | 0.0.0.0 — **must be blocked at the host firewall; not internet-accessible** |
| 4100 | IAM Kratos public | Dev/admin tooling | 0.0.0.0 |
| 4101 | IAM Kratos admin | Dev/admin tooling | 0.0.0.0 — **must be blocked at the host firewall; not internet-accessible** |
| 4103 | IAM Hydra admin | Dev/admin tooling | 0.0.0.0 — **must be blocked at the host firewall; not internet-accessible** |
| 5432 | PostgreSQL | Database access | 0.0.0.0 — **must be blocked at the host firewall; not internet-accessible** |

**All other service ports are internal-only** — no `ports:` mapping in compose.

---

## Hera Port Constraint (Security Requirement)

**ciam-hera and iam-hera MUST NOT publish port 3000 (or 4000) to the host interface. Only Caddy's ingress ports (80/443) should be bound to the public interface for Hera traffic.**

This constraint is:
- Documented inline in `compose.prod.yml` (see comments on the ciam-hera and iam-hera service definitions)
- Required for Caddy rate limiting (platform#22) to function

### Why this matters

If Hera's port 3000 were host-bound, an attacker who discovers the port can:
1. Bypass all Caddy rate limiting — brute-force and credential stuffing protections are nullified
2. Reach Hera directly from the internet if the host firewall allows port 3000

Caddy is the only correct ingress path for Hera. Hera has no built-in rate limiting or DDoS protection independent of Caddy.

### Current verified state

Both `compose.dev.yml` and `compose.prod.yml` have been audited (platform#55):

- **ciam-hera**: no `ports:` mapping. Port 3000 is accessible only within the Podman bridge network.
- **iam-hera**: no `ports:` mapping. Port 4000 is accessible only within the Podman bridge network.
- **Caddy (dev)**: port 3000 on the host is bound to the Caddy container (line 92 of `compose.dev.yml`). Developers reaching `localhost:3000` are already going through Caddy. This is unchanged by platform#55 — developers have no direct Hera access to lose.

### Compose inline comments

The ciam-hera and iam-hera service definitions in `compose.prod.yml` include explicit security comments:

```yaml
ciam-hera:
  # SECURITY: Do NOT add a ports: binding here. ciam-hera must only be reachable
  # through the Caddy reverse proxy. Adding a ports: mapping bypasses Caddy rate
  # limiting (platform#22) and directly exposes ciam-hera to the host interface.
  ...

iam-hera:
  # SECURITY: Do NOT add a ports: binding here. iam-hera must only be reachable
  # through the Caddy reverse proxy. Adding a ports: mapping bypasses Caddy rate
  # limiting (platform#22) and directly exposes iam-hera to the host interface.
  ...
```

Do not remove these comments. They are the in-file operator signal that the missing `ports:` section is intentional, not an oversight.

---

## Traffic Flow: Hera via Caddy

```
Internet / browser
        │
        ▼
Caddy (host port 80/443)
        │
        ▼  reverse_proxy (internal Compose network)
ciam-hera:3000  (no host port — internal only)
        │
        ▼
Ory Kratos (internal)
```

Caddy's `reverse_proxy` directive routes traffic to `ciam-hera:3000` using the container's internal network address. From outside the Compose network, port 3000 on ciam-hera is unreachable.

---

## Verification

### Confirm no host-bound ports on Hera

```bash
# Inspect running containers for port bindings
podman port ciam-hera 2>/dev/null || echo "No host port binding — correct"
podman port iam-hera 2>/dev/null || echo "No host port binding — correct"
```

Neither command should return a port mapping. If either returns a line like `3000/tcp -> 0.0.0.0:3000`, stop and investigate — a `ports:` mapping has been added to the compose file.

### Confirm Caddy proxies Hera correctly

Before any compose changes that affect port bindings, verify Caddy is actively routing to Hera by checking for a Kratos-specific response element:

```bash
# CIAM Hera via Caddy — check for Kratos self-service login page content
curl -s http://localhost:3000/self-service/login/browser | grep -q 'csrf_token\|self-service/login' \
  && echo "PASS: Caddy routes to CIAM Hera" \
  || echo "FAIL: Caddy not routing to CIAM Hera"

# IAM Hera via Caddy
curl -s http://localhost:4000/self-service/login/browser | grep -q 'csrf_token\|self-service/login' \
  && echo "PASS: Caddy routes to IAM Hera" \
  || echo "FAIL: Caddy not routing to IAM Hera"
```

The grep pattern targets Kratos-specific elements (`csrf_token` or `self-service/login`) that are exclusive to a valid Kratos self-service login page — not present in error page layouts. A PASS result confirms Caddy's `reverse_proxy` is routing to the correct container.

---

## Developer Access to Hera (Dev Environment)

In `compose.dev.yml`, developers access `localhost:3000` via Caddy — not directly via ciam-hera. This is unchanged: the dev compose has never had a host-bound port on ciam-hera.

If you need direct access to the ciam-hera container for debugging (e.g., inspecting raw container responses without Caddy):

```bash
# ciam-hera runs a stripped Next.js image — curl is NOT available inside the container.
# Use Node.js (available in the Next.js image) to make an internal HTTP request:
podman exec ciam-hera node -e \
  "require('http').get('http://localhost:3000/self-service/login/browser', r => { let d=''; r.on('data',c=>d+=c); r.on('end',()=>console.log(d.slice(0,500))); })"

# Alternatively, run a temporary test container on the same Compose network:
podman run --rm --network=olympus_intranet curlimages/curl \
  curl -s http://ciam-hera:3000/self-service/login/browser | head -c 500
```

Do not add a `ports:` mapping to `compose.dev.yml` as a debugging workaround. If you make that change temporarily and forget to revert it, the security constraint is silently reinstated in the compose file and the next developer who pulls will have a host-bound Hera port.

---

## Edge Cases

### Firewall and port 3000/4000

If the production host firewall has no rule blocking ports 3000/4000, and a `ports:` mapping is accidentally added, Hera becomes directly internet-accessible. The absence of a `ports:` mapping in compose is the primary control — the firewall is a secondary defense, not a substitute.

Run a port scan against the production host to confirm ports 3000 and 4000 are not reachable from outside:

```bash
# From an external machine
nmap -p 3000,4000 <production-host-ip>
# Expected: both ports closed or filtered
```

### CI regression guard

A CI check (introduced in platform#55) scans `compose.prod.yml` and `compose.dev.yml` for any `ports:` mapping on ciam-hera (port 3000) or iam-hera (port 4000). If found, the CI step fails the PR. This prevents the constraint from being silently removed under debugging pressure.

**Workflow file**: `.github/workflows/ci.yml`, step name: `Check Hera port bindings`. If this step is renamed or the workflow file moves, update this reference.

---

## Security Considerations

- **Rate limiting depends on Caddy seeing real IPs**: Caddy's rate limiting (platform#22) is keyed on client IP. If a client bypasses Caddy and reaches Hera directly, their IP is never seen by the rate limiter and the brute-force window is unlimited.
- **No host-to-loopback rebind**: Rebinding ciam-hera to `127.0.0.1:3000` instead of removing the `ports:` mapping entirely does not fix the issue on a multi-tenant host — loopback is reachable from all processes on the host. Remove the `ports:` mapping entirely.
- **iam-hera is equally constrained**: The same port binding constraint applies to iam-hera (port 4000). A compromised IAM Hera allows direct access to the admin authentication flow.

---

*Last updated: 2026-04-08 (Technical Writer — platform#55)*
