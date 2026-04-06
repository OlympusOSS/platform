# CAPTCHA: Cloudflare Turnstile

## Overview

Olympus uses Cloudflare Turnstile as the CAPTCHA provider for CIAM and IAM authentication flows. Turnstile protects the login, registration, and account recovery endpoints from credential stuffing and brute-force attacks. CAPTCHA enforcement is implemented in the Hera application layer (before Kratos receives credentials) and is configurable at runtime via the SDK vault without requiring a redeployment.

---

## How It Works

### Token Validation Flow

```
1. Hera server: getCaptchaEnabled() reads vault key "captcha.enabled" (env var fallback: CAPTCHA_ENABLED)
2. Hera server: getCaptchaSiteKey() reads vault key "captcha.site_key" (env var fallback: CAPTCHA_SITE_KEY)
3. Hera renders <TurnstileWidget siteKey={siteKey} /> when CAPTCHA is enabled
4. Turnstile JS loads from challenges.cloudflare.com with a per-request CSP nonce
5. Cloudflare presents a managed challenge; on success calls onSuccess(token)
6. User submits form — token is included as "captcha_token" field
7. Hera server action:
   a. checkLockout(identifier)     ← runs first; locked accounts are rejected before CAPTCHA
   b. getCaptchaEnabled()
   c. verifyCaptcha(token):
      POST https://challenges.cloudflare.com/turnstile/v0/siteverify
      body: { secret: secretKey, response: token }
      success=true  → proceed to Kratos
      success=false → reject ("CAPTCHA verification failed. Please try again.")
      missing key / network error → return false (FAIL-CLOSED)
   d. submitLoginFlow() / submitRegistrationFlow() / submitRecoveryFlow()
```

**Lockout ordering**: Account lockout (`checkLockout`) runs before CAPTCHA. A locked account is rejected before consuming a Cloudflare token. The two controls are independent and sequential — CAPTCHA does not bypass lockout.

### Protected Flows

| Flow | CIAM | IAM |
|------|------|-----|
| Login | Yes | Yes |
| Registration | Yes | No (IAM registration is disabled) |
| Account recovery (email step) | Yes | Yes |

### CAPTCHA and HIBP Are Separate Controls

This ticket ships two independent security controls:

1. **CAPTCHA (Turnstile)** — application-layer gate in Hera; fail-closed
2. **HIBP breach detection** — native Kratos feature (`haveibeenpwned_enabled: true` in `kratos.yml`); fail-open

They address different threats. CAPTCHA prevents automated credential attacks. HIBP rejects passwords known to appear in breach datasets at registration and password reset.

---

## API / Technical Details

### Environment Variables

These variables are injected into `ciam-hera` and `iam-hera` containers. The compose file uses domain-specific GitHub Variables (`CIAM_*`, `IAM_*`) and maps them to the generic names the application reads.

| Variable (in container) | GitHub Variable | Domain | Description |
|------------------------|----------------|--------|-------------|
| `CAPTCHA_ENABLED` | `CIAM_CAPTCHA_ENABLED` | CIAM | `true` enables CAPTCHA on CIAM flows; defaults to `true` in production |
| `CAPTCHA_SITE_KEY` | `CIAM_CAPTCHA_SITE_KEY` | CIAM | Cloudflare Turnstile site key for the CIAM Hera domain |
| `CAPTCHA_SECRET_KEY` | `CIAM_CAPTCHA_SECRET_KEY` | CIAM | Turnstile secret key for CIAM server-side verification |
| `CAPTCHA_ENABLED` | `IAM_CAPTCHA_ENABLED` | IAM | `true` enables CAPTCHA on IAM flows; defaults to `true` in production |
| `CAPTCHA_SITE_KEY` | `IAM_CAPTCHA_SITE_KEY` | IAM | Cloudflare Turnstile site key for the IAM Hera domain |
| `CAPTCHA_SECRET_KEY` | `IAM_CAPTCHA_SECRET_KEY` | IAM | Turnstile secret key for IAM server-side verification |

**Production defaults**: Both `ciam-hera` and `iam-hera` use `${CIAM_CAPTCHA_ENABLED:-true}` / `${IAM_CAPTCHA_ENABLED:-true}` in `compose.prod.yml`. CAPTCHA is active unless the GitHub Variable is explicitly set to `false`.

**Dev compose**: Both containers have `CAPTCHA_ENABLED=false` hardcoded. Use test keys (see Local Development section) to test the CAPTCHA flow locally.

### SDK Vault Keys (Runtime Override)

The vault values take priority over environment variables. Changes propagate within 60 seconds (SDK TTL cache). No container restart is required.

| Key | Type | Description |
|-----|------|-------------|
| `captcha.enabled` | `"true"` / `"false"` | Runtime toggle — affects all CAPTCHA-protected flows |
| `captcha.site_key` | string | Vault value overrides `CAPTCHA_SITE_KEY` env var |
| `captcha.secret_key` | encrypted (AES-256-GCM) | Vault value overrides `CAPTCHA_SECRET_KEY` env var; managed via Athena settings UI |

To set or update these via the Athena settings UI: navigate to Settings > Security > CAPTCHA. The `captcha.secret_key` field is stored as an encrypted secret.

### HIBP Breach Detection Configuration

`haveibeenpwned_enabled` is a native Kratos configuration option. It has no environment variable override path — it must be edited directly in the Kratos YAML file.

| Config File | Setting | Location |
|-------------|---------|----------|
| `platform/prod/ciam-kratos/kratos.yml` | `haveibeenpwned_enabled: true` | `selfservice.methods.password.config` block |
| `platform/prod/iam-kratos/kratos.yml` | `haveibeenpwned_enabled: true` | `selfservice.methods.password.config` block |

After editing either Kratos YAML file, the Kratos container must restart to pick up the change. The production deployment pipeline (`deploy.yml`) handles this as part of its normal container start sequence.

HIBP requires outbound TCP/443 to `api.pwnedpasswords.com`. Verify this before enabling:

```bash
# Run from within the ciam-kratos container
curl -s https://api.pwnedpasswords.com/range/5BAA6 | head -5
# Expected: k-anonymity hash suffix lines (not an error or empty response)
```

---

## Examples

### Operator Setup: Cloudflare Turnstile

CIAM and IAM require separate Turnstile site registrations. Turnstile validates the origin domain, so a single registration cannot cover both.

**Step 1: Create two Turnstile sites in the Cloudflare dashboard**

1. Log in to the [Cloudflare dashboard](https://dash.cloudflare.com/) and navigate to Turnstile.
2. Create a site for your CIAM Hera public domain (e.g., `auth.example.com`).
   - Widget type: **Managed** (Cloudflare decides when to challenge)
   - Copy the **Site Key** and **Secret Key**
3. Create a second site for your IAM Hera domain (e.g., `auth-internal.example.com`).
   - Copy the **Site Key** and **Secret Key**

**Step 2: Set GitHub Variables before deploying**

Set these as GitHub Actions Variables (not Secrets — see note below) in the repository settings:

```
CIAM_CAPTCHA_SITE_KEY   = <site key from step 2>
IAM_CAPTCHA_SITE_KEY    = <site key from step 3>
```

Set these as GitHub Actions **Secrets**:

```
CIAM_CAPTCHA_SECRET_KEY = <secret key from step 2>
IAM_CAPTCHA_SECRET_KEY  = <secret key from step 3>
```

The secret keys must be stored as Secrets (not Variables) because they are used for server-side verification and must not appear in logs or environment listings.

**Step 3: Deploy**

Run `deploy.yml`. The pipeline injects these values into the container environment. CAPTCHA becomes active automatically because the compose default is `:-true`.

**Deployment ordering requirement**: All four Turnstile variables must be set before running `deploy.yml`. Deploying with `:-true` defaults but without valid keys causes `verifyCaptcha()` to return `false` (missing secret key) and blocks all logins on CAPTCHA-protected flows.

### Runtime Disable via Vault (No Redeploy)

To temporarily disable CAPTCHA without redeploying:

1. Open Athena for the target domain (CIAM or IAM).
2. Navigate to Settings > Security > CAPTCHA.
3. Set `captcha.enabled` to `false` and save.
4. The change takes effect within 60 seconds across all running Hera instances.

Disabling CAPTCHA via the vault requires documented justification. The Caddy per-IP rate limiter (platform#10) is the minimum compensating control that must be active before disabling CAPTCHA. Confirm `platform/prod/caddy/Caddyfile` is enforcing rate limits on the login routes before proceeding.

### Local Development

The Cloudflare always-pass test keys allow testing the full CAPTCHA flow locally without a real Cloudflare site registration:

```
Site Key:    1x00000000000000000000AA
Secret Key:  1x0000000000000000000000000000000AA
```

Set these in `compose.dev.yml` and set `CAPTCHA_ENABLED=true` for the container you want to test. The Turnstile widget renders and calls `onSuccess` immediately. Server-side verification against Cloudflare's siteverify API succeeds with the test secret key.

These keys are documented by Cloudflare: https://developers.cloudflare.com/turnstile/troubleshooting/testing/

---

## Edge Cases

### Mismatched Key: Site Key Set, Secret Key Empty

If `CAPTCHA_SITE_KEY` is configured (the widget renders and the user completes the challenge) but `CAPTCHA_SECRET_KEY` is absent or invalid, `verifyCaptcha()` returns `false` and all form submissions fail with "CAPTCHA verification failed. Please try again."

The user-facing message is identical to a failed challenge — there is no UI indication of a misconfiguration. To diagnose this, check the Hera server logs for: `CAPTCHA_SECRET_KEY is not configured (vault or env)`.

**Recovery**: Set the correct secret key in the vault via the Athena settings UI (takes effect within 60s) or set `CIAM_CAPTCHA_SECRET_KEY` / `IAM_CAPTCHA_SECRET_KEY` as GitHub Variables and redeploy.

### Cloudflare siteverify Unreachable

`verifyCaptcha()` fails closed on network errors. If `challenges.cloudflare.com/turnstile/v0/siteverify` is unreachable, all CAPTCHA-protected form submissions are rejected. Hera logs: `Turnstile verification error: <network error>`.

**Recovery**: Disable CAPTCHA via the vault (`captcha.enabled = false`) to restore logins. The change takes effect within 60 seconds. The Caddy rate limiter is then the active compensating control. Re-enable CAPTCHA once Cloudflare connectivity is restored.

### HIBP Service Unreachable

When `api.pwnedpasswords.com` is unreachable, Kratos fails open — the password is accepted. There is no error shown to the user and no operator signal beyond Kratos logs. This is the Ory-documented behavior for this feature.

Environments with strict egress filtering may silently break HIBP after enabling it. Verify egress (see the curl test above) before deploying `haveibeenpwned_enabled: true`.

### CAPTCHA Token Expiry

Turnstile tokens expire after a short period. If a user leaves the form open without submitting, the token expires and the `expired-callback` fires. The widget resets and the user must complete the challenge again before resubmitting. The server action returns "Please complete the CAPTCHA challenge." if no token is present.

### Demo Login Path

`demoLoginAction` bypasses CAPTCHA enforcement and lockout checks entirely. This path is gated by the `ALLOW_DEMO_ACCOUNTS` environment variable (`:-false` by default in production). Enabling `ALLOW_DEMO_ACCOUNTS` in production creates a no-CAPTCHA, no-lockout login path for any demo account — this must be treated as a security exception requiring documented justification.

---

## Security Considerations

### Fail-Closed Policy

`verifyCaptcha()` returns `false` on any failure: missing secret key, non-200 HTTP response from Cloudflare, network exception, or `data.success === false`. There is no fail-open code path. An operator error or infrastructure failure that breaks CAPTCHA will block logins rather than silently remove protection.

This means a Cloudflare siteverify outage blocks logins on all CAPTCHA-protected flows. The vault emergency disable (described above) is the recovery procedure.

### Turnstile Token Replay

Cloudflare enforces single-use tokens server-side. A token captured by a network observer cannot be replayed — Cloudflare rejects a second siteverify request with the same token. Do not log or store `captcha_token` values.

### CAPTCHA Does Not Replace Rate Limiting

CAPTCHA and rate limiting are independent controls. CAPTCHA (Turnstile) is an application-layer gate per form submission. Caddy per-IP rate limiting (platform#10) is a network-layer gate per HTTP request. Both must be active in production for adequate brute-force protection.

Disabling CAPTCHA without confirmed active Caddy rate limiting is a policy violation.

### Disabling CAPTCHA in Production

Disabling CAPTCHA on a CIAM or IAM flow requires:

1. Confirm the Caddy rate limiter is active on the target login route (check `platform/prod/caddy/Caddyfile`).
2. Document the justification for disabling.
3. Disable via vault only (`captcha.enabled = false`) — no permanent config change should be made without a corresponding issue tracking the justification.

### HIBP: No UI Warning Mode

`haveibeenpwned_enabled: true` in Kratos blocks the registration or password reset flow if the submitted password appears in any breach dataset. Kratos returns a localization-driven error message to the user. The specific message text is controlled by Kratos's built-in localization system — it is not configurable via Hera.

At the time of this writing, Hera does not implement a "warn but allow" mode for HIBP. The Kratos setting is binary: disabled or blocking.

### CSP Compliance

The `TurnstileWidget` component reads the per-request CSP nonce from the `<meta name="csp-nonce">` tag injected by `layout.tsx`. The dynamically created Turnstile `<script>` tag carries this nonce. Without it, the Turnstile script would be blocked by the `script-src 'nonce-{N}'` Content-Security-Policy applied by Hera's Next.js middleware. Do not modify the nonce propagation path in `turnstile-widget.tsx` without reviewing `platform/prod/caddy/Caddyfile` and `hera/src/middleware.ts`.
