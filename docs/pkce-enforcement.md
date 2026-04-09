# PKCE Enforcement on CIAM Hydra OAuth2 Clients

## Overview

All public CIAM Hydra OAuth2 clients have `require_pkce: true` set. This makes PKCE (Proof Key for Code Exchange) mandatory at the server level — Hydra rejects any authorization request that does not include a `code_challenge`. Without this, a client could send an authorization request with no `code_challenge` and Hydra would accept it, bypassing the PKCE protection that Hera generates.

This was implemented in platform#66 as a follow-on to hera#32 (PKCE S256 in Hera) to close the server-side enforcement gap.

**Deployment dependency**: This setting must be active within 24 hours of hera#32 being production-verified. Deploying `require_pkce: true` before Hera sends `code_challenge` causes a complete CIAM login outage. See [Migration Guide](#migration-guide) below.

---

## How It Works

Ory Hydra checks the `require_pkce` flag on each registered OAuth2 client when an authorization request arrives. If the flag is `true` and the request does not include `code_challenge`, Hydra returns a 400 error and the flow stops.

```
Authorization request → Hydra
        │
        ├─ require_pkce: false  → continue (code_challenge optional)
        │
        └─ require_pkce: true
                │
                ├─ code_challenge present → continue → PKCE verified at token exchange
                │
                └─ code_challenge absent  → 400 Bad Request
```

This enforcement is independent of Hera's PKCE generation. Both layers are required:
- **Hera** generates the `code_verifier` and `code_challenge` on every authorization initiation (hera#32)
- **Hydra** rejects requests that arrive without `code_challenge` (platform#66)

If only Hera enforces PKCE but Hydra does not, a client that bypasses Hera (e.g., a direct HTTP client constructing its own authorization URL) can omit `code_challenge` and the flow completes.

---

## Technical Details

### Hydra Client Field

| Field | Type | Value | Applied to |
|-------|------|-------|------------|
| `require_pkce` | boolean | `true` | All public CIAM Hydra clients (`token_endpoint_auth_method: none`) |

The field is set via the Hydra admin API:

```bash
# Read current client config (GET — do not lose other fields)
curl -s http://localhost:3103/admin/clients/hera-ciam-client | jq .

# Update require_pkce on existing client (GET-then-PUT — see migration guide)
CURRENT=$(curl -s http://localhost:3103/admin/clients/hera-ciam-client)
UPDATED=$(echo "$CURRENT" | jq '.require_pkce = true')
curl -sf -X PUT http://localhost:3103/admin/clients/hera-ciam-client \
  -H "Content-Type: application/json" \
  -d "$UPDATED"
```

**Critical**: Hydra's `PUT /admin/clients/{id}` replaces the entire client object. Always GET the current config first and update it — never send a partial body. Sending `{"require_pkce": true}` alone will strip all other client fields (redirect URIs, grant types, scopes).

**Port reference**:
- `3103` — CIAM Hydra admin (not internet-accessible; accessible only from the host via SSH tunnel)
- `3102` — CIAM Hydra public OAuth2 endpoint

### Dev Seed Script

In `dev/ciam-seed-dev.sh`, CIAM Hydra clients are registered at dev environment startup. The `hera-ciam-client` is registered with `require_pkce: true`. The `site-ciam-client` has a temporary PKCE exemption while site#20 is pending:

```bash
# TEMPORARY EXEMPTION: site-ciam-client does NOT have require_pkce: true.
# This client does not yet send code_challenge — see site#20 for the fix.
# Do NOT copy this client config as a reference pattern.
```

Do not remove this comment. When site#20 ships, the exemption comment must be removed and `require_pkce: true` must be added to the `site-ciam-client` registration.

### Affected Clients

| Client ID | `require_pkce` | Notes |
|-----------|----------------|-------|
| `hera-ciam-client` | `true` | Public client — PKCE enforced |
| `site-ciam-client` | `false` (temporary) | PKCE exemption pending site#20 |

---

## Examples

### Verify PKCE enforcement is active

```bash
# Confirm require_pkce is set on hera-ciam-client
curl -s http://localhost:3103/admin/clients/hera-ciam-client | jq '.require_pkce'
# Expected: true

# List all CIAM clients and their PKCE status
curl -s http://localhost:3103/admin/clients \
  | jq '.[] | {id: .client_id, require_pkce: .require_pkce}'
```

### Test PKCE enforcement rejects missing code_challenge

The following request omits `code_challenge` and must be rejected:

```bash
curl -v "http://localhost:3102/oauth2/auth?\
client_id=hera-ciam-client\
&response_type=code\
&redirect_uri=http://localhost:3000/callback\
&scope=openid+email\
&state=test123"
```

Expected Hydra response (approximation — verify against DX-66-2 live verification):

```json
{
  "error": "invalid_request",
  "error_description": "Clients must include a code_challenge when performing the authorize code flow, but it is missing. Ensure that the request includes a code_challenge parameter."
}
```

HTTP status: `400 Bad Request`. The redirect does not occur.

**Note**: The exact `error_description` text above is based on known Hydra behavior. DX-66-2 must verify the exact error body against the running instance. When DX-66-2 live verification is complete, this doc MUST be updated to reflect the verified error body. Update it before the ticket is marked Done.

### Verify a successful PKCE flow

```bash
# Generate a PKCE verifier and challenge
CODE_VERIFIER=$(openssl rand -base64 64 | tr -d '=+/' | head -c 43)
CODE_CHALLENGE=$(echo -n "$CODE_VERIFIER" | openssl dgst -sha256 -binary | openssl base64 | tr '+/' '-_' | tr -d '=')

# This request should redirect to the login page (not return an error)
curl -v "http://localhost:3102/oauth2/auth?\
client_id=hera-ciam-client\
&response_type=code\
&redirect_uri=http://localhost:3000/callback\
&scope=openid+email\
&state=test123\
&code_challenge=${CODE_CHALLENGE}\
&code_challenge_method=S256"
# Expected: 302 redirect to Hera login page
```

---

## Migration Guide

This is a breaking change for any integration that sends authorization requests without `code_challenge`. Follow this sequence to avoid a CIAM login outage.

### Deployment Order (Non-Negotiable)

1. **hera#32 must be production-verified first.** Confirm Hera is sending `code_challenge` and `code_challenge_method=S256` on every authorization request.
2. **Deploy platform#66 within 24 hours of hera#32 verification.** If a 24-hour window cannot be met, escalate to the Security Architect — do not silently delay.

If platform#66 is deployed before hera#32, every CIAM login attempt returns a 400 error until hera#32 is deployed.

### Step-by-Step

**Step 1 — Verify Hera sends code_challenge**

```bash
# Check a recent CIAM authorization request in Hydra access logs
# or initiate a login flow and inspect the redirect URL
curl -v http://localhost:3102/oauth2/auth?client_id=hera-ciam-client&...
# Confirm: code_challenge and code_challenge_method=S256 are present in the redirect
```

**Step 2 — Enumerate all CIAM clients**

```bash
curl -s http://localhost:3103/admin/clients \
  | jq '.[] | {id: .client_id, grant_types: .grant_types, pkce: .require_pkce}'
```

Confirm no unknown `authorization_code` clients exist. Document each client's current `require_pkce` value before making any changes.

**Step 3 — Apply require_pkce to public clients**

For each public client (`token_endpoint_auth_method: none`) with `grant_types` including `authorization_code`:

```bash
# GET current config
CURRENT=$(curl -s http://localhost:3103/admin/clients/hera-ciam-client)
# Apply require_pkce: true and PUT back
echo "$CURRENT" | jq '.require_pkce = true' | \
  curl -sf -X PUT http://localhost:3103/admin/clients/hera-ciam-client \
    -H "Content-Type: application/json" -d @-
```

**Step 4 — Verify enforcement**

Run the test in [Test PKCE enforcement rejects missing code_challenge](#test-pkce-enforcement-rejects-missing-code_challenge) above. The no-`code_challenge` request must return 400.

**Step 5 — Verify normal flow completes**

Complete a real CIAM login in the browser. Confirm no regression to the authenticated flow.

---

## Edge Cases

### Legacy client created before PKCE enforcement

A client created before `require_pkce: true` was standard may have the field absent (defaulting to `false`). Run the client enumeration command in Step 2 to identify any such clients. Update each one using the GET-then-PUT pattern.

If a legacy client legitimately cannot support PKCE (e.g., a server-side confidential client using `client_credentials`), `require_pkce` is not applicable — `client_credentials` does not use the authorization code flow. Leave it `false` and document the reason inline.

### site-ciam-client temporary exemption

The `site-ciam-client` currently has `require_pkce: false` pending site#20. Users who log in via the Site OAuth2 playground are not covered by PKCE enforcement until site#20 ships. This is tracked and time-bounded — do not treat the exemption as a permanent state.

### Hydra field name varies by version

If a Hydra upgrade changes the field name, `require_pkce` may not take effect. Verify the field name on the deployed instance:

```bash
curl -s http://localhost:3103/admin/clients/hera-ciam-client \
  | jq 'keys | map(select(test("pkce"; "i")))'
# Expected: ["require_pkce"]
```

If the key name differs, stop and escalate — do not proceed with the script using an unverified field name.

---

## Security Considerations

- **PKCE prevents authorization code interception attacks**: without PKCE, an attacker who intercepts the authorization code (e.g., via a redirect URI mismatch or open redirect) can exchange it for tokens. PKCE binds the code to the original requester's `code_verifier`, making intercepted codes useless.
- **Server-side enforcement is required in addition to client-side**: Hera generating PKCE is not sufficient if the server does not mandate it. A custom client could bypass Hera entirely.
- **24-hour deployment window is a hard security constraint**: deploying hera#32 without platform#66 leaves a window where a client can omit `code_challenge` and the authorization succeeds. The window must be 24 hours or less per SR-66-1.
- **Do not apply require_pkce to client_credentials clients**: the `client_credentials` grant type does not involve an authorization code flow. Setting `require_pkce: true` on a confidential machine-to-machine client has no effect but could cause confusion.

---

*Last updated: 2026-04-08 (Technical Writer — platform#66)*
