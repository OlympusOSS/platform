# pgAdmin Access Control

## Overview

pgAdmin is the database administration tool for the Olympus platform. It has read/write access to
all five PostgreSQL databases — `ciam_kratos`, `ciam_hydra`, `iam_kratos`, `iam_hydra`, and
`olympus` — which collectively contain identity credentials, OAuth2 client secrets, session tokens,
and AES-256-GCM encrypted application settings. This blast radius makes pgAdmin the
highest-consequence access surface in the platform.

Access is controlled by three independent layers:
1. **Network restriction** — pgAdmin is not publicly accessible; access requires VPN or bastion
2. **Pre-provisioning gate** — only explicitly provisioned identities can log in (`OAUTH2_AUTO_CREATE_USER = False`)
3. **Role claim gate** — the IAM Hydra ID token must contain a `roles` claim including `"dba"`

All three layers are mandatory. Removing or bypassing any single layer still requires both remaining
layers to pass, but defense in depth requires all three.

This access model was implemented in platform#21. Prior to that fix, `OAUTH2_AUTO_CREATE_USER = True`
allowed any valid IAM identity to silently receive a pgAdmin account on first login.

---

## How It Works

### Authentication Flow (Post-Fix)

1. DBA navigates to pgAdmin — accessible only via VPN, bastion, or internal network
2. Clicks "Login with Olympus"
3. pgAdmin initiates OAuth2 authorization code flow with IAM Hydra
4. IAM Hydra redirects to IAM Hera login page
5. DBA authenticates with IAM Kratos credentials
6. IAM Hydra issues authorization code; pgAdmin exchanges for tokens
7. IAM Hydra injects `roles` claim into the ID token via the global Jsonnet claims mapper
8. pgAdmin evaluates `OAUTH2_ADDITIONAL_CLAIMS_VALIDATION`: `'dba' in (roles or [])`
9. If `dba` present in claim AND pgAdmin user record exists: access granted
10. If claim absent, or `dba` not in claim, or no pgAdmin user record: access denied

### Non-DBA Rejection Flow

1. IAM user completes IAM SSO successfully (valid credentials)
2. pgAdmin receives ID token — `roles` claim does not contain `"dba"` (or claim is absent)
3. `OAUTH2_ADDITIONAL_CLAIMS_VALIDATION` hook returns `False`
4. pgAdmin denies access — no account is created (`OAUTH2_AUTO_CREATE_USER = False`)

### pgAdmin Configuration

Both `platform/dev/pgadmin/config_local.py` and `platform/prod/pgadmin/config_local.py` contain:

```python
OAUTH2_AUTO_CREATE_USER = False

OAUTH2_ADDITIONAL_CLAIMS_VALIDATION = {
    'roles': lambda roles: 'dba' in (roles or [])
}

AUTHENTICATION_SOURCES = ['oauth2']  # no password login
```

`OAUTH2_AUTO_CREATE_USER = False` is the primary fix. The role validation hook is the second
enforcement layer. Both must be present.

### IAM Hydra Claims Mapper

The `roles` claim is injected into all IAM Hydra ID tokens by a global Jsonnet claims mapper.

**Mapper file**: `platform/prod/iam-hydra/pgadmin-claims-mapper.jsonnet`

```jsonnet
local claims = {
  iss: std.extVar('claims').iss,
  sub: std.extVar('claims').sub,
  email: std.extVar('claims').email,
  roles: std.get(std.extVar('session').identity.traits, 'roles', []),
};
claims
```

The `std.get(..., 'roles', [])` form is null-safe — it returns an empty array for all existing
IAM identities that have no `roles` trait. Do not use the direct access form
(`std.extVar('session').identity.traits.roles`) — it throws a Jsonnet evaluation error for
identities without the `roles` field.

**hydra.yml configuration**:

```yaml
oidc:
  claims_mapper:
    filepath: /etc/config/iam-hydra/pgadmin-claims-mapper.jsonnet
```

### IAM Kratos Identity Schema

The `roles` array trait was added to the IAM Kratos admin identity schema
(`platform/prod/iam-kratos/admin-identity.schema.json`):

```json
"roles": {
  "type": "array",
  "items": { "type": "string" },
  "description": "Access control roles for this identity"
}
```

The field is optional. Existing identities without the trait receive `roles: []` from the
null-safe mapper, which causes the pgAdmin hook to deny access (correct behavior for
non-DBA identities).

### pgAdmin OAuth2 Client Registration

The pgAdmin client in IAM Hydra uses:
- `grant_types`: `["authorization_code", "refresh_token"]`
- `scope`: `openid email profile` — no elevated scopes
- `redirect_uris`: exact production URL only — no wildcards
- `skip_consent`: `true` (pgAdmin is an internal tool, no user-facing consent required)
- Claims mapper: configured globally in `hydra.yml` (see ADR note below)

### ADR: Global Claims Mapper Limitation

**Hydra v26.2.0 does not support per-client Jsonnet claims mappers via the API**. Per-client
mapper fields in client registrations are silently ignored. The mapper is configured globally in
`iam-hydra/hydra.yml` via `oidc.claims_mapper.filepath`.

**Consequence**: the `roles` claim is injected into **all** IAM Hydra ID tokens — not only the
pgAdmin client's tokens. This is safe for the current set of IAM Hydra clients, as no other
registered client validates or depends on ID token claims. However, any new IAM Hydra client
integration must be written with the awareness that all ID tokens include a `roles` array claim.

**Impact for future integrations**: if you register a new OAuth2 client with IAM Hydra and perform
strict claims validation on the ID token, account for the `roles` claim. A client that rejects
unrecognized claims will fail to parse tokens from this Hydra instance. This is a known platform
constraint until Hydra adds per-client mapper support in a future version.

### Network Restriction

pgAdmin must not be publicly accessible from the internet in production. This is mandatory — there
is no documentation alternative.

Required network posture:
- pgAdmin port 5433 must be firewalled to authorized source IPs (VPN CIDR, bastion host IP) only
- The Caddy reverse proxy must not route public traffic to pgAdmin
- Never bind pgAdmin to `0.0.0.0:5433` in production (dev binds to `127.0.0.1:5433`)

Evidence required at each production deployment: security group rules or firewall configuration
confirming port 5433 is not reachable from the public internet.

---

## DBA Provisioning Runbook

To grant a new DBA access to pgAdmin:

### Step 1 — Create or verify the IAM identity

The DBA must have an active IAM Kratos identity. Verify via IAM Athena admin panel or:

```bash
curl -sf "${IAM_KRATOS_ADMIN_URL}/admin/identities?credentials_identifier=<dba-email>"
```

If the identity does not exist, create it via IAM Athena.

### Step 2 — Assign the `dba` role

Add `"dba"` to the identity's `roles` array trait via IAM Athena or the Kratos admin API:

```bash
# Get identity ID
IDENTITY_ID=$(curl -sf "${IAM_KRATOS_ADMIN_URL}/admin/identities?credentials_identifier=<dba-email>" \
  | python3 -c "import sys,json; d=json.load(sys.stdin); print(d[0]['id'])")

# Assign dba role
curl -sf -X PATCH "${IAM_KRATOS_ADMIN_URL}/admin/identities/${IDENTITY_ID}" \
  -H "Content-Type: application/json" \
  -d '[{"op":"replace","path":"/traits/roles","value":["dba"]}]'
```

If the identity already has other roles, include them in the value array alongside `"dba"`.

### Step 3 — Pre-provision the pgAdmin user record

1. Log in to pgAdmin as a pgAdmin administrator
2. Navigate to User Management (top menu)
3. Create a new user with the DBA's email address
4. Set the appropriate role (Admin or User) within pgAdmin

This step is mandatory — `OAUTH2_AUTO_CREATE_USER = False` means pgAdmin never auto-creates
accounts. A valid IAM SSO session is necessary but not sufficient for access. The pgAdmin user
record must exist before the DBA's first login.

### Step 4 — Verify access

The DBA should navigate to pgAdmin (via VPN or internal network) and click "Login with Olympus".
Confirm the DBA reaches the pgAdmin dashboard with database access before handing over.

---

## DBA Offboarding Runbook

See [runbook-pgadmin-dba-offboarding.md](./runbook-pgadmin-dba-offboarding.md) for the complete
procedure.

### Active Session Gap — Read This First

pgAdmin's session cookie lifetime is **1 day (86 400 seconds)**. An active pgAdmin session
persists for up to 24 hours after role removal. Steps 1 and 2 of the offboarding procedure take
effect at the next login attempt but do **not** terminate in-progress sessions.

For any time-sensitive DBA removal — employee termination, security incident, suspected compromise
— execute step 4 (manual session revocation) immediately after step 1. Do not treat it as a
cleanup task.

### Offboarding Summary (Full procedure in linked runbook)

| Step | Action | Immediate effect |
|------|--------|-----------------|
| 1 | Remove `dba` from IAM Kratos identity `roles` trait | Next login denied by role gate |
| 2 | Disable or delete IAM Kratos identity | No new IAM SSO sessions possible |
| 3 | Delete pgAdmin user record | Hygiene — removes stale audit entry |
| 4 | Revoke active pgAdmin sessions | **Closes the 24-hour active session window** |

All four steps are mandatory.

---

## Edge Cases

### Identity without `roles` trait attempts login

The null-safe Jsonnet mapper returns `roles: []` for all identities without the trait. The
pgAdmin hook `'dba' in (roles or [])` evaluates to `False`. Access is denied. No error is
thrown during token issuance.

### DBA role removed — session still active

Role removal from the IAM Kratos identity takes effect at the DBA's next login attempt. The
existing pgAdmin session remains valid until it expires (up to 24 hours) or until manual revocation
(offboarding step 4). There is no automated real-time session invalidation — this is a known V1 gap.
Automated revocation via IAM Kratos webhook is tracked as a V2 follow-up.

### pgAdmin user record exists, IAM identity deleted

If a DBA's IAM identity is deleted but their pgAdmin user record remains, the stale record appears
in pgAdmin's user list but cannot be used. Without a valid IAM identity, the IAM SSO flow fails
before reaching pgAdmin. The stale record is harmless but should be cleaned up (offboarding step 3).

### New IAM Hydra client encounters unexpected `roles` claim

Due to the global Jsonnet mapper limitation, all IAM Hydra ID tokens include a `roles` array claim.
New OAuth2 clients must not fail on unrecognized claims in the ID token. If a client performs strict
claims validation, add `roles` to its accepted claim list or configure it to ignore unknown claims.

---

## Security Considerations

### The three layers are independent but complementary

- Network restriction prevents unauthenticated access attempts from reaching pgAdmin at all
- Pre-provisioning (`OAUTH2_AUTO_CREATE_USER = False`) prevents any non-provisioned IAM identity
  from gaining access even if they reach pgAdmin and complete IAM SSO
- The role claim gate (`OAUTH2_ADDITIONAL_CLAIMS_VALIDATION`) provides an additional check: a
  pre-provisioned DBA whose `dba` role has been removed is denied at login time without requiring
  pgAdmin user record deletion

Removing any one layer leaves the other two as the only protection. All three must be present.

### pgAdmin scope in IAM Hydra

The pgAdmin OAuth2 client is registered with `scope: openid email profile`. It has no access to
Olympus resource server scopes (`identities:read`, `sessions:read`, Athena API scopes). Granting
additional scopes to the pgAdmin client would increase the blast radius of a compromised DBA
credential beyond direct database access.

### Error messages for non-DBA users

When a valid IAM user without the `dba` role attempts to log into pgAdmin, they receive a generic
authentication failure from pgAdmin. The error does not describe the specific reason (missing role,
not pre-provisioned). This is intentional — the error message does not reveal the access model to
unauthorized users.

Operators fielding access requests from IAM users who cannot log into pgAdmin should check:
1. Does the identity have `"dba"` in its `roles` array trait in IAM Kratos?
2. Does a pgAdmin user record exist for that email in pgAdmin User Management?
Both conditions must be true for access to be granted.

### Compliance

- The three-layer control maps to SOC2 CC6.1 (logical access control) and CC6.3 (access removal)
- The offboarding runbook (`runbook-pgadmin-dba-offboarding.md`) is the SOC2 CC6.3 evidence
  artifact for DBA access removal procedures
- pgAdmin login events are logged by pgAdmin to its container logs; ensure container logs are
  collected by the platform log pipeline for audit purposes
- The `roles` claim in all IAM Hydra ID tokens is a deliberate architectural decision documented
  here due to Hydra v26.2.0 per-client mapper limitations; future Hydra versions may support
  per-client mappers, enabling a more targeted implementation
