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
7. IAM Hera consent page reads `traits.roles` from the Kratos identity and calls `AcceptConsentRequest` with `session.id_token.roles`, injecting the `roles` claim into the ID token
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

### IAM Hera Consent Page — Roles Injection

The `roles` claim is injected into IAM Hydra ID tokens during the consent flow. The IAM Hera
consent page (`hera/src/app/consent/page.tsx`) reads `traits.roles` from the Kratos identity and
passes it to IAM Hydra when accepting the consent request:

```ts
// hera/src/app/consent/page.tsx
import { getConsentRequest, acceptConsentRequest } from "@/lib/hydra";

const consentRequest = await getConsentRequest(challenge);

// Extract roles from context — set by IAM login action (login/actions.ts)
const contextRoles = consentRequest.context?.roles;
const idTokenRoles: string[] = Array.isArray(contextRoles)
  ? (contextRoles as string[]).filter((r: unknown): r is string => typeof r === "string")
  : [];

// Accept consent and inject roles into the ID token session claim
await acceptConsentRequest(challenge, {
  grant_scope: consentRequest.requested_scope,
  grant_access_token_audience: consentRequest.requested_access_token_audience,
  session: {
    id_token: {
      email: consentRequest.context?.email || "",
      sub: consentRequest.subject,
      roles: idTokenRoles,
    },
  },
});
```

The implementation uses `acceptConsentRequest` from `@/lib/hydra` — not the Ory SDK's
`hydraAdmin.acceptOAuth2ConsentRequest` method. The helper wraps the Hydra admin API call
with the correct request shape for this codebase.

The roles extraction is null-safe: identities without a `roles` trait in their Kratos context
receive an empty array. The `.filter()` call also strips any non-string values from the array.
Both paths — skip-consent (remembered) and first-time consent — inject `roles` from the
current login context, not from the stored consent grant. This means role changes take effect
at the DBA's next login, not after the consent grant expires.

> **Note for future IAM Hydra client developers**: All OAuth2 clients using the IAM Hera
> consent flow receive a `roles` array claim in their ID tokens. See the
> [Consent Session Injection ADR](#consent-session-injection-adr) section below and the
> [New IAM Hydra client encounters unexpected `roles` claim](#new-iam-hydra-client-encounters-unexpected-roles-claim)
> edge case.

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

### Consent-Based Injection Scope

Because `roles` is injected during the consent flow in IAM Hera, the claim is only present in
ID tokens issued through the IAM Hera consent page. This is scoped to OAuth2 clients that use
IAM Hydra with the IAM Hera login/consent UI (currently: Athena IAM, pgAdmin).

Any new IAM Hydra OAuth2 client that shares the same consent flow will also receive the `roles`
claim in its ID tokens. Clients that perform strict claims validation on the ID token must account
for the `roles` array claim or configure their parser to ignore unknown claims.

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

> **Required setup step — do not skip.** A DBA with a correctly assigned `dba` role in IAM
> Kratos will still be denied by pgAdmin if this step is not completed. The error message is
> indistinguishable from a role-gate denial. This step is also a prerequisite for Local QA
> test cases V1 and F5.

1. Log in to pgAdmin as a pgAdmin administrator (the default admin account is configured in
   the dev compose file; production requires an existing pgAdmin admin session)
2. Navigate to User Management (top menu: click your username in the top right, then
   "User Management")
3. Click "Add User"
4. Enter the DBA's email address (must match the IAM Kratos identity's email exactly)
5. Set the appropriate pgAdmin role: "Administrator" for lead DBAs, "User" for standard DBAs
6. Save

This step is mandatory — `OAUTH2_AUTO_CREATE_USER = False` means pgAdmin never auto-creates
accounts. A valid IAM SSO session is necessary but not sufficient for access. The pgAdmin user
record must exist before the DBA's first login attempt.

### Step 4 — Verify access

The DBA should navigate to pgAdmin (via VPN or internal network) and click "Login with Olympus".
Confirm the DBA reaches the pgAdmin dashboard with database access before handing over.

---

## DBA Account Registry

The current set of pre-provisioned pgAdmin accounts is tracked in
[pgadmin-dba-accounts.md](./pgadmin-dba-accounts.md). This registry is the SOC2 CC6.3 evidence
artifact for active DBA access. Update it when provisioning (add entry) and when offboarding
(remove entry after step 3 of the offboarding runbook completes).

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

The IAM Hera consent page uses `identity.traits.roles ?? []`, returning an empty array for
all identities without the trait. The pgAdmin hook `'dba' in (roles or [])` evaluates to
`False`. Access is denied. No error is thrown during token issuance.

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

OAuth2 clients that share the IAM Hera consent flow receive a `roles` array claim in their ID
tokens. New OAuth2 clients must not fail on unrecognized claims in the ID token. If a client
performs strict claims validation, add `roles` to its accepted claim list or configure it to
ignore unknown claims.

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
- The `roles` claim is injected via the IAM Hera consent page (`AcceptConsentRequest` with
  `session.id_token.roles`) — scoped to OAuth2 clients using the IAM Hera consent flow

---

## Consent Session Injection ADR

**Decision**: Roles are injected into IAM Hydra ID tokens via the IAM Hera consent session
(`session.id_token.roles` in `acceptConsentRequest`), not via a per-client Jsonnet claims mapper.

**Context**: Hydra v26.2.0 does not support per-client claims mappers configured via the Hydra
admin API. The `oidc.claims_mapper.filepath` configuration property exists in the Hydra YAML but
applies globally to all OAuth2 clients — it cannot be scoped to a single client such as pgAdmin.
A global Jsonnet mapper would inject the `roles` claim into ID tokens issued for every IAM Hydra
client (Athena IAM, pgAdmin, and any future clients), with no ability to restrict injection to
the pgAdmin client only.

The consent session path was chosen instead because it achieves per-token injection with no
Hydra configuration changes, leverages the existing `hera/src/app/consent/page.tsx` code path
that already executes for every login, and preserves the ability to extend claims injection
independently per client in the future.

**Scope and global impact**: The consent session injection is not truly per-client — it is
per-consent-flow. Any IAM Hydra OAuth2 client that uses the IAM Hera login and consent UI will
receive a `roles` claim in its ID tokens if the authenticated user has `traits.roles` set in
their IAM Kratos identity. Currently that means Athena IAM and pgAdmin. Future clients added to
IAM Hydra with the IAM Hera consent flow will also receive the `roles` claim.

**Implication for future IAM Hydra client developers**: When integrating a new OAuth2 client
with IAM Hydra and the IAM Hera consent flow:

- Expect a `roles` array claim in the ID token for users who have `traits.roles` set in IAM Kratos
- Expect an empty array (`[]`) for users without the `roles` trait
- Do not configure your client's claims parser to fail on unexpected claims — use permissive
  parsing or explicitly add `roles` to your accepted claims list
- If your client does not need the `roles` claim, ignore it — it does not affect authentication
  or authorization unless your client explicitly reads it
- If your client needs to gate access on a role, follow the pgAdmin pattern:
  `OAUTH2_ADDITIONAL_CLAIMS_VALIDATION` (or equivalent) checking for the required role value in
  the `roles` array

Machine-to-machine flows (client credentials grant) that bypass the consent UI do not receive
the `roles` claim — it is only present in user-facing authorization code flows that pass through
the IAM Hera consent page.

**Revisit trigger**: When Hydra is upgraded beyond v26.2.0, evaluate whether per-client claims
mappers are supported. If so, the consent session injection can be replaced with a per-client
mapper scoped to pgAdmin only, removing the global injection from all future client tokens.
