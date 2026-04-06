# Rate Limiting

## Overview

The Olympus CIAM login endpoint has two independent rate limiting layers that operate at different levels of the stack and produce distinct error responses. Integration consumers must handle both.

## How It Works

```
Internet → Caddy (per-IP layer) → Hera login flow → SDK lockout check → Kratos
```

Layer 1 (Caddy) fires first. If a request passes the IP rate limit, Layer 2 (SDK) checks the per-account lockout state before forwarding credentials to Kratos. The two layers are independent — hitting Layer 1 does not affect Layer 2 counters, and vice versa.

### Layer 1: Per-IP Throttling (Caddy)

| Property | Value |
|----------|-------|
| Scope | Per source IP address |
| Limit | 5 requests per 10 seconds |
| Response | HTTP 429 Too Many Requests |
| Reset | Sliding window — the counter resets after 10 seconds of no requests |
| Applied to | All requests to CIAM Hera login routes |

The Caddy rate limit is the network-layer backstop. It fires before any application code runs. There is no exponential backoff — the response is a flat 429 for every request that exceeds the limit.

**Consumer action**: Implement request queuing or exponential backoff on receipt of a 429. Do not retry immediately. A 429 from Caddy contains no `retry_after` field.

### Layer 2: Per-Account Lockout (SDK)

| Property | Value |
|----------|-------|
| Scope | Per account identifier (email or username, lowercased) |
| Default threshold | 5 failed login attempts |
| Default window | 600 seconds (10 minutes), sliding |
| Default lockout duration | 900 seconds (15 minutes) |
| Response (browser) | HTTP 200 with Hera lockout page |
| Response (API consumer) | See JSON error shape below |
| Configuration | SDK settings table (`security.brute_force.*` keys) |

The SDK lockout check runs inside the Hera login flow, before credentials are forwarded to Kratos. A locked account never contacts Kratos — the lockout is enforced at the application layer.

**Consumer action**: Surface the lockout message to the user. Do not retry automatically — the account remains locked until `lockout_duration_seconds` expires or an administrator unlocks it manually via the Athena admin panel.

---

## API / Technical Details

### Error Response Shapes

**Layer 1 — Caddy 429:**

```http
HTTP/1.1 429 Too Many Requests
Content-Type: text/plain

Too Many Requests
```

No `Retry-After` or `X-RateLimit-*` headers are returned. The response body is plain text. This is a known V1 limitation — the Caddy rate limit module does not emit structured headers or a JSON body in the current configuration. Standardizing the Caddy 429 response (adding `Retry-After` and `X-RateLimit-*` headers) is tracked as a follow-on infrastructure story (DX-P10-2).

**Layer 2 — SDK lockout (browser flow):**

```http
HTTP/1.1 200 OK
Content-Type: text/html

<!-- Hera lockout page with message: "Account temporarily locked. Try again in N minutes." -->
```

**Layer 2 — SDK lockout (API consumer, JSON):**

> **Note**: The structured JSON lockout response is planned for a follow-on story (DX-P10-3, tracked in hera#26). The V1 implementation returns HTML for all lockout responses regardless of the `Accept` header. Do not implement integrations against the JSON shape until hera#26 ships.

When the `Accept: application/json` header is present, Hera will return a structured error (planned, not yet implemented):

```json
{
  "error": "account_locked",
  "message": "Account temporarily locked due to too many failed attempts.",
  "retry_after": 847,
  "retry_at": "2026-04-06T14:23:00Z"
}
```

The `retry_after` field will be the number of seconds remaining until the lockout expires. The `retry_at` field will be the ISO 8601 timestamp at which the lockout expires.

### Configuration Keys (SDK Settings Table)

Lockout thresholds are configurable via the SDK settings table. Changes take effect within the 60-second cache TTL — no service restart required.

| Key | Type | Default | Min | Max | Description |
|-----|------|---------|-----|-----|-------------|
| `security.brute_force.max_attempts` | integer | `5` | `1` | `100` | Failed attempts before lockout |
| `security.brute_force.window_seconds` | integer | `600` | `60` | `86400` | Sliding window duration |
| `security.brute_force.lockout_duration_seconds` | integer | `900` | `60` | `86400` | How long lockout lasts |
| `security.brute_force.fail_open` | boolean | `true` | — | — | Behavior if the database is unavailable |

Set configuration values via the Athena admin settings panel or directly via the SDK:

```typescript
import { setSetting } from "@olympusoss/sdk";

// Tighten threshold to 3 attempts in 5 minutes, lockout for 30 minutes
await setSetting("security.brute_force.max_attempts", "3");
await setSetting("security.brute_force.window_seconds", "300");
await setSetting("security.brute_force.lockout_duration_seconds", "1800");
```

### Port Architecture

In production, Caddy is the only service that exposes host ports (80 and 443). All application services (Hera, Athena, Kratos, Hydra) are accessible only within the internal container network — they have no direct host port bindings. This constraint is documented inline in `platform/prod/compose.prod.yml` and enforced by deployment policy (see `CLAUDE.md`).

| Service | Accessible from | Not accessible from |
|---------|----------------|---------------------|
| Hera (login UI) | Caddy (internal) | Public internet directly |
| Athena (admin panel) | Caddy (internal) | Public internet directly |
| Kratos admin API | Internal network only | Caddy, public internet |
| Hydra admin API | Internal network only | Caddy, public internet |

---

## Examples

### Handling a 429 from Caddy

```typescript
async function loginWithRetry(email: string, password: string) {
  const response = await fetch("/self-service/login", {
    method: "POST",
    body: JSON.stringify({ identifier: email, password }),
  });

  if (response.status === 429) {
    // Caddy layer — back off before retrying
    await sleep(10_000); // Wait at least one Caddy window
    return loginWithRetry(email, password);
  }

  return response;
}
```

### Handling a lockout response (JSON API consumer — planned)

> **Note**: The JSON lockout response requires hera#26 (DX-P10-3). The V1 SDK lockout response is HTML-only. This example applies after hera#26 ships.

```typescript
const response = await fetch("/self-service/login", {
  method: "POST",
  headers: { "Accept": "application/json" },
  body: JSON.stringify({ identifier: email, password }),
});

const data = await response.json();

if (data.error === "account_locked") {
  showLockoutMessage(`Account locked. Try again in ${Math.ceil(data.retry_after / 60)} minutes.`);
  return;
}
```

### Distinguishing the two layers (planned — after hera#26)

> **Note**: Distinguishing Layer 1 (Caddy 429) from Layer 2 (SDK lockout) by `Accept: application/json` content negotiation requires hera#26. Until then, Layer 2 lockout responses are HTML pages and cannot be distinguished programmatically from a successful HTML flow.

```typescript
const response = await fetch("/self-service/login", {
  method: "POST",
  headers: { "Accept": "application/json" },
  body: JSON.stringify({ identifier: email, password }),
});

if (response.status === 429) {
  // Layer 1: Caddy per-IP limit — too many requests from this IP
  handleRateLimit();
} else if (response.ok) {
  const data = await response.json();
  if (data.error === "account_locked") {
    // Layer 2: SDK per-account lockout — this specific account is locked
    handleAccountLockout(data.retry_after);
  } else {
    handleLoginResult(data);
  }
}
```

---

## Edge Cases

### Database unavailable during lockout check

If the `olympus` PostgreSQL database is unavailable when Hera calls `checkLockout()`, the SDK logs the
failure at ERROR level and returns `{ locked: false }` — the login proceeds (fail-open). This is a
documented design decision: a database outage is already a P0 incident; blocking all logins on top of it
compounds the impact for marginal security benefit.

The log entry carries the tag `[security][brute_force][fail_open]` for monitoring alert wiring:

```
[ERROR][security][brute_force][fail_open] Database unavailable — lockout check bypassed. Login proceeding.
```

The Caddy layer remains active as a backstop during a database outage.

### Distributed credential stuffing (many IPs, many accounts)

The per-account lockout layer (Layer 2) is not effective against distributed attacks that spread attempts
across many accounts from many IP addresses. The per-IP Caddy layer (Layer 1) provides partial mitigation
for high-volume distributed attacks.

Per-IP rate limiting as a complement to per-account lockout is tracked as a follow-on security story.

### Low `max_attempts` off-by-one

At `max_attempts=1` or `max_attempts=2`, concurrent login requests processed simultaneously can cause
one extra attempt to pass before the lockout record is committed. This is a known V1 behavior of the
append-then-count pattern. At the default of `max_attempts=5`, the practical effect is negligible. Avoid
setting `max_attempts` below 3 in production.

---

## Security Considerations

- The lockout check runs before Kratos credential validation. A locked account never reaches Kratos, preventing timing-based username enumeration via response latency differences.
- The lockout response does not reveal whether the account exists or how many attempts remain. The message is generic regardless of lockout cause.
- IP addresses are recorded in `ciam_login_attempts` for administrative visibility. Hera reads the client IP from the trusted proxy header (`X-Real-IP` as set by Caddy) — not from `X-Forwarded-For`, which is spoofable by clients.
- All manual account unlocks by administrators are recorded in `ciam_security_audit` with the admin's identity ID, the target identifier, and a timestamp. Audit records are append-only and never deleted.
- The `security.brute_force.lockout_duration_seconds` setting enforces a minimum of 60 seconds — values below 60 are rejected with a warning and the default (900s) is used instead. This prevents misconfiguration where a 0-second lockout silently disables protection.
