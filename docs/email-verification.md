# Email Verification Enforcement in CIAM Kratos

**Ticket**: platform#24
**Last updated**: 2026-04-06

## Overview

CIAM Kratos enforces mandatory email verification before any account can be used to log in. This document explains how the enforcement works, which config keys control it, and what behavior to expect for both password-based and OIDC social login registrations.

## How It Works

### The Enforcement Mechanism

Two Kratos configuration keys are relevant to email verification. They are not interchangeable:

| Config Key | Purpose | Security Role |
|-----------|---------|--------------|
| `selfservice.flows.login.after.hooks: [require_verified_address]` | **Enforcement**: Kratos intercepts every completed login attempt and blocks users whose email has not been verified | This is the security control. Removing this hook allows unverified users to log in. |
| `selfservice.flows.verification.use: code` | **Method**: Controls how the verification flow works — code-based OTP vs. magic link | This is a UX setting. Changing it does not affect whether verification is required. |

**Common misconfiguration**: Engineers debugging verification issues sometimes edit `flows.verification.use` expecting it to change whether verification is enforced. It does not. The enforcement gate is `flows.login.after.hooks: [require_verified_address]`.

### Password Registration Flow

1. User submits registration form on CIAM Hera
2. Kratos creates the identity with email unverified
3. Kratos sends a verification email (courier, SMTP via MailSlurper in dev)
4. User attempts to log in before clicking the link
5. Login flow completes AAL1 check
6. `require_verified_address` hook fires — Kratos redirects to the verification UI (`/verification`)
7. User clicks the email link; Kratos marks email as verified
8. User can complete login successfully

The hook fires at step 6 regardless of how the login was initiated. Direct calls to the Kratos self-service API do not bypass it — the hook is server-side in Kratos.

### Registration Hook is Intentionally Empty

The `selfservice.flows.registration.after.password.hooks` list is empty in both dev and prod. This is intentional: new registrations do not auto-verify. Any future change that adds a hook to this list that auto-marks the email as verified would bypass the enforcement mechanism. The CI check (see below) asserts this list remains empty.

### Current Config State (Audited 2026-04-05)

| Check | Dev (`dev/ciam-kratos/kratos.yml`) | Prod (`prod/ciam-kratos/kratos.yml`) |
|-------|------------------------------------|------------------------------------|
| `flows.login.after.hooks` contains `require_verified_address` | PASS | PASS |
| `flows.registration.after.password.hooks` is empty | PASS | PASS |
| `flows.verification.enabled` is `true` | PASS | PASS |
| `flows.verification.use` is `code` | PASS | PASS |

Both configs are identical on these checks. This audit result is enforced persistently by the CI check in `platform/scripts/verify-email-enforcement.sh`.

## OIDC Social Login and Email Verification

When a user registers via an OIDC provider (e.g. Google), the provider's ID token typically includes `email_verified: true`. Kratos does **not** automatically trust this claim.

### Current Behavior (Option B — Always Require Kratos Verification)

1. User initiates OIDC registration flow
2. Provider returns ID token with `email_verified: true`
3. Kratos creates the identity with the provider-supplied email address
4. Kratos marks the email as **unverified** in its internal state — the provider claim is not trusted
5. `require_verified_address` hook fires on the user's first login attempt
6. Kratos sends a verification email to the provider-supplied address
7. User must click the verification link before login succeeds

This means OIDC users must verify their email via Kratos even if their Google or GitHub account email is already confirmed. This is the more conservative behavior: it does not trust potentially stale or spoofed provider-side claims.

The trade-off is a worse first-login UX for social users. This is an accepted trade-off while no OIDC provider is configured.

### Why This Decision Was Made Explicit

See [`docs/oidc-email-verified-trust-decision.md`](./oidc-email-verified-trust-decision.md) for the full architectural decision record. The short summary: Option B (always require Kratos verification) is the **current deliberate choice**, not a default that was overlooked.

**When the OIDC feature story is implemented**, the Architecture Brief for that story must explicitly resolve the Option A vs Option B choice before the brief is approved. Option B is not necessarily permanent — it is the correct default until OIDC is added and the trust decision is made per-provider.

## CI Enforcement

The script `platform/scripts/verify-email-enforcement.sh` runs on every push to `main` and on every PR that touches `platform/**/ciam-kratos/kratos.yml`. It asserts:

1. `flows.login.after.hooks` contains `require_verified_address` in both dev and prod configs
2. `flows.registration.after.password.hooks` is empty in both dev and prod configs
3. `flows.verification.enabled` is `true` in both configs

The script uses Python's `yaml.safe_load` for structural assertion. It produces actionable failure output naming the specific check and YAML path that failed:

```
FAIL [dev]: flows.login.after.hooks does not contain 'require_verified_address'
  Found: ['session']
  Expected: list containing 'require_verified_address'
  File: platform/dev/ciam-kratos/kratos.yml
```

### Acceptable Dev/Prod Divergences

The following differences between `dev/ciam-kratos/kratos.yml` and `prod/ciam-kratos/kratos.yml` are expected and do not cause CI failures:

| Setting | Dev | Prod | Reason |
|---------|-----|------|--------|
| `log.level` | `debug` | `info` | Expected |
| `log.leak_sensitive_values` | `true` | `false` | Expected, intentional |
| `hashers.bcrypt.cost` | `8` | `12` | Performance trade-off for dev speed |
| `dsn` | SQLite file path | DSN via env var | Different DB backends |
| `cors.allowed_origins` | Hardcoded localhost | Env var | Expected |

Any divergence in the `flows` section that is **not** in the above list causes CI to fail.

## API / Technical Details

No new API endpoints. The verification behavior is entirely Kratos-native and requires no custom application code. The `require_verified_address` hook is built into Kratos.

## Edge Cases

### User Attempts Login Before Verifying

Kratos redirects to the verification UI (`/verification?flow=<id>`). The user is not logged in. The `require_verified_address` hook fires before any session token is issued.

### Verification Email Delivery Failure

If the SMTP courier fails to deliver the verification email (misconfigured MailSlurper in dev, SMTP server outage in prod), the user receives no email and cannot verify. The identity exists in Kratos but is unusable. The operator must:
1. Check the Kratos courier logs for delivery failures
2. Resolve the SMTP configuration issue
3. The user can request a new verification email via the Kratos self-service API

### Resending the Verification Email

Kratos allows re-sending via the self-service verification flow initiation endpoint. The Hera UI must present this option to users who did not receive the original email.

### Direct API Bypass Attempt

A malicious actor calling the Kratos self-service registration API directly and then attempting login is blocked by the `require_verified_address` hook. The hook runs server-side in Kratos — it is not a UI check. There is no path to bypass it without modifying the Kratos configuration.

## Security Considerations

- The enforcement mechanism is the login hook, not the verification method. Never remove `require_verified_address` from `flows.login.after.hooks` to "fix" a user experience issue — it removes the security control.
- The CI check is the persistent guard against future config drift. Removing or disabling the CI check script re-opens the enforcement gap silently. Changes to `platform/scripts/verify-email-enforcement.sh` should require a security review (CODEOWNERS rule — tracked as a P2 improvement).
- The OIDC trust path decision (Option A vs Option B) must be explicitly resolved before any OIDC provider is configured. See `docs/oidc-email-verified-trust-decision.md`.

## References

- `platform/docs/oidc-email-verified-trust-decision.md` — full architectural decision record for OIDC email trust
- `platform/scripts/verify-email-enforcement.sh` — CI enforcement script
- platform#24 — origin ticket for this audit
