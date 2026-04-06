# Runbook: pgAdmin DBA Offboarding

**Platform**: Olympus identity platform
**Component**: pgAdmin (database administration)
**Security ref**: platform#21 — OWASP A01:2021 Broken Access Control
**Date**: 2026-04-05

---

## Background

pgAdmin has access to all five Olympus PostgreSQL databases:
- `ciam_kratos` — CIAM identity credentials and sessions
- `ciam_hydra` — CIAM OAuth2 client secrets and consent grants
- `iam_kratos` — IAM identity credentials and sessions
- `iam_hydra` — IAM OAuth2 client secrets and consent grants
- `olympus` — application settings, AES-256-GCM encrypted secrets

Because of this blast radius, DBA access is a high-consequence privilege. When a DBA leaves the organisation, changes roles, or their access is revoked for any reason, this runbook must be followed completely and in order.

---

## Two-Layer Access Control (Post platform#21)

pgAdmin enforces two independent access control layers:

1. **Pre-provisioning gate** (`OAUTH2_AUTO_CREATE_USER = False`): only IAM identities with an existing pgAdmin user record may log in. New accounts are never silently created.
2. **Role claim gate** (`OAUTH2_ADDITIONAL_CLAIMS_VALIDATION`): the IAM Hydra ID token must contain a `roles` claim that includes `"dba"`. This claim is injected via the IAM Hera consent session — the consent page (`hera/src/app/consent/page.tsx`) reads `traits.roles` from the IAM Kratos identity context and passes it to IAM Hydra as `session.id_token.roles` when calling `acceptConsentRequest`. If the claim is absent, null, or does not contain `"dba"`, login is denied regardless of pgAdmin user record status. Note: Hydra v26.2.0 does not support per-client Jsonnet claims mappers — consent session injection is the implemented mechanism.

Offboarding must address both layers.

---

## Session Cookie Lifetime

pgAdmin's session cookie lifetime uses the default pgAdmin4 value: **1 day (86 400 seconds)**.

This setting is NOT overridden in `platform/dev/pgadmin/config_local.py` or `platform/prod/pgadmin/config_local.py`.

**Consequence**: an active pgAdmin session persists for up to 24 hours after role removal. Steps 1 and 2 below take immediate effect at the next login attempt, but they do NOT terminate sessions that are already in progress. Step 4 (manual session revocation) is mandatory to close the active session gap.

---

## Offboarding Procedure

Execute these steps in order. All four steps are mandatory.

### Step 1 — Remove `dba` role from IAM Kratos identity

**Effect**: immediate — next login attempt by this identity will be denied by the role claim validation hook.

Access the IAM Athena admin panel and remove `"dba"` from the identity's `roles` trait array. Alternatively, use the IAM Kratos admin API:

```bash
# 1a. Look up the identity ID by email
IDENTITY_ID=$(curl -sf "${IAM_KRATOS_ADMIN_URL}/admin/identities?credentials_identifier=<dba-email>" \
  | python3 -c "import sys,json; data=json.load(sys.stdin); print(data[0]['id'])")

# 1b. Get current traits
CURRENT_TRAITS=$(curl -sf "${IAM_KRATOS_ADMIN_URL}/admin/identities/${IDENTITY_ID}" \
  | python3 -c "import sys,json; data=json.load(sys.stdin); print(json.dumps(data['traits']))")

# 1c. Patch to remove 'dba' from roles (PATCH removes array item)
curl -sf -X PATCH "${IAM_KRATOS_ADMIN_URL}/admin/identities/${IDENTITY_ID}" \
  -H "Content-Type: application/json" \
  -d '[{"op":"replace","path":"/traits/roles","value":[]}]'
```

**Verification**: the identity's `roles` trait must be `[]` or absent. Any subsequent login attempt will be denied by the role gate.

---

### Step 2 — Disable or delete the IAM Kratos identity

**Effect**: immediate — IAM SSO cannot be initiated by this identity. The login flow fails before reaching pgAdmin.

Disable (preserves audit history):
```bash
curl -sf -X PATCH "${IAM_KRATOS_ADMIN_URL}/admin/identities/${IDENTITY_ID}" \
  -H "Content-Type: application/json" \
  -d '[{"op":"replace","path":"/state","value":"inactive"}]'
```

Delete (complete removal — irreversible):
```bash
curl -sf -X DELETE "${IAM_KRATOS_ADMIN_URL}/admin/identities/${IDENTITY_ID}"
```

Choose disable unless the identity is being permanently removed from the system. Coordinate with the platform lead before deleting.

---

### Step 3 — Delete pgAdmin user record

**Effect**: hygiene — removes stale record from pgAdmin's internal user database. The record no longer appears in audit exports or the pgAdmin user list.

1. Log in to pgAdmin as a pgAdmin administrator
2. Navigate to: User Management (top menu)
3. Find the departing DBA's email
4. Click Delete and confirm

Alternatively, use pgAdmin's internal SQLite database or the pgAdmin admin API if available.

---

### Step 4 — Revoke active pgAdmin sessions (mandatory — V1)

**Effect**: immediate termination of any in-progress pgAdmin sessions. This closes the 24-hour active session gap created by the pgAdmin session cookie lifetime.

Steps 1 and 2 prevent the identity from initiating a new pgAdmin session, but any session cookie issued before role removal remains valid until expiry (up to 24 hours). Manual session revocation is required to eliminate this window.

To revoke active sessions:

1. Log in to pgAdmin as a pgAdmin administrator
2. Navigate to: User Management (top menu)
3. Locate the departing DBA's email
4. Click the active sessions indicator or use the revoke option
   - In pgAdmin4, clicking "Revoke" or "Log out user" from the User Management panel invalidates the session server-side

If pgAdmin does not expose a UI-level session revocation control for the specific user, the fallback is to restart the pgAdmin container. This terminates ALL active sessions (not just the departing DBA's). Coordinate with other active DBAs before restarting.

```bash
# Production — restart pgAdmin container (terminates all sessions)
# Only use this if per-user session revocation is unavailable
# Coordinate with active DBAs first
podman compose -f /path/to/compose.prod.yml restart pgadmin
```

**Known V1 gap**: Automated session revocation (triggered by IAM Kratos identity deactivation via webhook to pgAdmin's session store) is a V2 follow-up story. V1 requires manual execution of this step.

---

## Completion Checklist

| Step | Action | Verified |
|------|--------|---------|
| 1 | `dba` removed from IAM Kratos identity `roles` trait | [ ] |
| 2 | IAM Kratos identity disabled or deleted | [ ] |
| 3 | pgAdmin user record deleted | [ ] |
| 4 | Active pgAdmin sessions revoked | [ ] |

All four steps must be checked before the offboarding is considered complete.

---

## DBA Provisioning (Onboarding)

To provision a new DBA:

1. Ensure the IAM Kratos identity exists (or create one via IAM Athena)
2. Add `"dba"` to the identity's `roles` array trait via IAM Athena or the Kratos admin API
3. Create a pgAdmin user record with the DBA's email via pgAdmin User Management (pre-provisioning is required — `OAUTH2_AUTO_CREATE_USER = False`)
4. Instruct the DBA to navigate to pgAdmin (internal network / VPN only) and click "Login with Olympus"

**Network requirement**: pgAdmin is accessible only via VPN, bastion host, or internal network in production. DBAs must connect via the approved access path.

---

## Related Files

| File | Purpose |
|------|---------|
| `platform/prod/pgadmin/config_local.py` | pgAdmin OAuth2 config — `OAUTH2_AUTO_CREATE_USER = False`, `OAUTH2_ADDITIONAL_CLAIMS_VALIDATION` |
| `hera/src/app/consent/page.tsx` | IAM Hera consent page — injects `roles` claim into IAM Hydra ID tokens via `session.id_token.roles` in `acceptConsentRequest` |
| `hera/src/app/login/actions.ts` | IAM Hera login action — extracts `traits.roles` from IAM Kratos identity and passes it as login context |
| `platform/prod/iam-kratos/admin-identity.schema.json` | IAM identity schema — `roles` array trait |
| `platform/prod/Caddyfile` | Reverse proxy — network restriction documentation |
