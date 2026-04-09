# Security Headers

## Overview

Olympus applies HTTP security headers at two layers: Caddy (the reverse proxy) owns structural,
protocol-level headers; Next.js middleware owns Content-Security-Policy. Each header is owned by
exactly one layer. The same header must never appear in both.

The Next.js CSP layer is implemented and active in Hera and Athena. The Caddy layer
(HSTS, X-Frame-Options, X-Content-Type-Options, Referrer-Policy, Permissions-Policy) is
implemented and active — the prod Caddyfile contains a `(security_headers)` snippet applied
to all browser-facing vhosts. Both layers shipped as part of platform#18.

---

## How It Works

### Header Ownership — Authoritative Assignment

| Header | Owner | Set Where | Status |
|--------|-------|-----------|--------|
| `Strict-Transport-Security` | Caddy | Caddyfile `(security_headers)` snippet | **Implemented** |
| `X-Frame-Options` | Caddy | Caddyfile `(security_headers)` snippet | **Implemented** |
| `X-Content-Type-Options` | Caddy | Caddyfile `(security_headers)` snippet | **Implemented** |
| `Referrer-Policy` | Caddy | Caddyfile `(security_headers)` snippet | **Implemented** |
| `Permissions-Policy` | Caddy | Caddyfile `(security_headers)` snippet | **Implemented** |
| `Content-Security-Policy` | Next.js | `src/middleware.ts` in Hera and Athena | **Implemented** |

**Rule**: Next.js must not emit `X-Frame-Options`, `Strict-Transport-Security`,
`X-Content-Type-Options`, or `Referrer-Policy`. Caddy must not emit `Content-Security-Policy`.
Both constraints are active.

### Caddy Snippets

The prod Caddyfile defines two snippets to handle the UI vs. API vhost distinction:

**`(security_headers)`** — applied to all browser-facing vhosts:

```
(security_headers) {
    header {
        Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
        X-Frame-Options "DENY"
        X-Content-Type-Options "nosniff"
        Referrer-Policy "strict-origin-when-cross-origin"
        Permissions-Policy "geolocation=(), microphone=(), camera=()"
        -Server
    }
}
```

**`(api_security_headers)`** — applied to Hydra API vhosts (no `X-Frame-Options`; Hydra
serves API responses, not browser UIs):

```
(api_security_headers) {
    header {
        Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
        X-Content-Type-Options "nosniff"
        Referrer-Policy "strict-origin-when-cross-origin"
        -Server
    }
}
```

### Vhost Assignment

| Vhost | Snippet | `X-Frame-Options` | Notes |
|-------|---------|-------------------|-------|
| `CIAM_HERA_PUBLIC_URL` | `security_headers` | DENY | Login/consent UI — framing is a phishing vector |
| `IAM_HERA_PUBLIC_URL` | `security_headers` | DENY | Same rationale |
| `CIAM_ATHENA_PUBLIC_URL` | `security_headers` | DENY | Admin UI — must not be embeddable |
| `IAM_ATHENA_PUBLIC_URL` | `security_headers` | DENY | Same rationale |
| `SITE_PUBLIC_URL` | `security_headers` with `SAMEORIGIN` override | SAMEORIGIN | Marketing site may be embedded in previews |
| `CIAM_HYDRA_PUBLIC_URL` | `api_security_headers` | — | API host; framing header not applicable |
| `IAM_HYDRA_PUBLIC_URL` | `api_security_headers` | — | Same rationale |
| `PGADMIN_PUBLIC_URL` | `security_headers` | DENY | Caddy HSTS and framing policy apply at proxy layer |

### Next.js CSP — Nonce-Based

Hera and Athena each run a `middleware.ts` that:
1. Generates a cryptographic nonce per request (`crypto.getRandomValues`)
2. Injects the nonce into a `Content-Security-Policy` response header
3. Forwards the nonce to the layout via the `x-nonce` request header
4. The layout reads `x-nonce` and applies the nonce to all `<Script>` components and inline script blocks

**Hera CSP** (login/consent UI — includes Cloudflare Turnstile origins):

```
default-src 'self';
script-src 'self' 'nonce-{NONCE}' 'strict-dynamic' https://challenges.cloudflare.com;
style-src 'self' 'unsafe-inline';
frame-src https://challenges.cloudflare.com;
connect-src 'self' https://challenges.cloudflare.com;
img-src 'self' data:;
font-src 'self';
object-src 'none';
base-uri 'self';
form-action 'self';
frame-ancestors 'none';
```

`'strict-dynamic'` was added to `script-src` in hera#48 Phase 1. Under `'strict-dynamic'`,
modern browsers ignore `'self'` and origin allowlists in `script-src` — only nonce-bearing
scripts execute. The `'self'` and `https://challenges.cloudflare.com` entries remain as
legacy-browser fallbacks. See `hera/docs/csp-configuration.md` for the full nonce
propagation pattern and `'strict-dynamic'` behavioral notes.

**Athena CSP** (admin UI — no Turnstile):

```
default-src 'self';
script-src 'self' 'nonce-{NONCE}';
style-src 'self' 'unsafe-inline';
connect-src 'self';
img-src 'self' data:;
font-src 'self';
object-src 'none';
base-uri 'self';
form-action 'self';
frame-ancestors 'none';
```

### Framing Policy Ownership

`frame-ancestors 'none'` in the CSP is the **authoritative framing policy** for Hera and Athena.
It supersedes `X-Frame-Options` in all modern browsers. Once the Caddy layer ships,
`X-Frame-Options: DENY` in the Caddyfile will serve as the legacy-browser fallback only.

**Consequence for future changes**: if you need to modify the framing policy for Hera or Athena,
update `frame-ancestors` in `src/middleware.ts`. For the Site vhost (which has no CSP middleware),
`X-Frame-Options` in the Caddyfile will be the only framing control once that layer is implemented.

---

## API / Technical Details

### Nonce Propagation in Next.js

```typescript
// middleware.ts (Hera) — current state after hera#48 Phase 1
const nonceBytes = new Uint8Array(16);
crypto.getRandomValues(nonceBytes);
const nonce = btoa(String.fromCharCode(...nonceBytes));

const csp = [
  "default-src 'self'",
  `script-src 'self' 'nonce-${nonce}' 'strict-dynamic' https://challenges.cloudflare.com`,
  "style-src 'self' 'unsafe-inline'",
  "frame-src https://challenges.cloudflare.com",
  "connect-src 'self' https://challenges.cloudflare.com",
  "img-src 'self' data:",
  "font-src 'self'",
  "object-src 'none'",
  "base-uri 'self'",
  "form-action 'self'",
  "frame-ancestors 'none'",
].join('; ');

// Set CSP on response; forward nonce to layout
response.headers.set('Content-Security-Policy', csp);
request.headers.set('x-nonce', nonce);
```

```typescript
// layout.tsx — read nonce and apply to scripts
import { headers } from 'next/headers';

const nonce = (await headers()).get('x-nonce') ?? '';
// Pass nonce to <Script nonce={nonce}> and inline <script nonce={nonce}>
```

### Cloudflare Turnstile Compatibility

Turnstile loads a script from `https://challenges.cloudflare.com/turnstile/v0/api.js` and renders
in an iframe served from `https://challenges.cloudflare.com`. The Hera CSP includes:
- `script-src ... https://challenges.cloudflare.com` — allows the Turnstile script to load
- `frame-src https://challenges.cloudflare.com` — allows the Turnstile iframe to render
- `connect-src ... https://challenges.cloudflare.com` — allows Turnstile's verification fetch

Removing any of these entries breaks Turnstile. If Turnstile adds new subdomain origins, update
the Hera middleware CSP template accordingly.

### Caddyfile Validation

The CI step runs `caddy validate` before syncing the Caddyfile to production:

```bash
docker run --rm \
  -v $(pwd)/platform/prod/Caddyfile:/etc/caddy/Caddyfile \
  caddy:alpine caddy validate --config /etc/caddy/Caddyfile
```

Caddy's `caddy reload` gracefully falls back to the previous running configuration on syntax error.
A failed Caddyfile deploy does not guarantee a service outage — the previous config remains active.
However, a failed deploy must still be treated as a deployment failure and investigated; do not
assume self-recovery is complete without verifying the running config.

---

## Examples

### Verifying headers in Chrome DevTools

1. Open Chrome DevTools (F12)
2. Go to the Network tab
3. Navigate to the Hera login page (`https://<hera-domain>/login`)
4. Click the document request (the HTML response)
5. Inspect the Response Headers panel

You should see all of the following:
- `content-security-policy: default-src 'self'; script-src 'self' 'nonce-...` (unique per request)
- `strict-transport-security: max-age=31536000; includeSubDomains; preload`
- `x-frame-options: DENY`
- `x-content-type-options: nosniff`
- `referrer-policy: strict-origin-when-cross-origin`
- `permissions-policy: geolocation=(), microphone=(), camera=()`

If any of the Caddy-layer headers are absent, the `(security_headers)` snippet may not be imported
on that vhost. Verify the relevant vhost block in `platform/prod/Caddyfile`.

### Verifying nonce is applied to script tags

In Chrome DevTools Elements tab, run in the console:

```javascript
document.querySelectorAll('script[nonce]').length
// Expected: all scripts have a nonce attribute matching the CSP header nonce
```

### Verifying no duplicate headers

Each security header should appear exactly once in the response. If `content-security-policy`
appears twice, Caddy is also emitting CSP — check that no Caddy vhost sets a
`Content-Security-Policy` header directive. Duplicate `X-Frame-Options` would mean both Caddy
and a Next.js header config are emitting it — the Caddy `(security_headers)` snippet is the
sole source; Next.js must not set this header.

---

## Edge Cases

### CSP violation blocks a third-party script during development

CSP is active in local dev — it is not disabled for development. When a CSP violation blocks a
resource, the browser console shows the blocked URL and the violated directive.

To allow a new script origin during development, add it to the CSP module (`src/lib/csp.ts` in
Athena; `src/middleware.ts` in Hera). Do not set `'unsafe-inline'` or `'unsafe-eval'` as a
production workaround — this defeats the CSP.

**Athena development exception**: Athena's `buildCsp()` adds `'unsafe-eval'` to `script-src`
when `NODE_ENV=development` to support Next.js HMR. This is intentional and CI-gated — a CI
artifact check verifies `'unsafe-eval'` is absent from the production edge bundle. See
`athena/docs/csp-configuration.md` for details.

### Adding a new `<Script>` to Hera or Athena

Any new `<Script>` component or inline `<script>` block added to Hera or Athena must receive the
nonce attribute. Read the nonce from `x-nonce` in the layout and pass it as the `nonce` prop:

```tsx
// layout.tsx
const nonce = (await headers()).get('x-nonce') ?? '';
return <Script src="/my-script.js" nonce={nonce} />;
```

Scripts added without a nonce attribute are blocked by the CSP.

### Embedding Hera or Athena in an iframe

`frame-ancestors 'none'` in the CSP is a **breaking change** for any integration that embeds
Hera or Athena in an iframe. Browser-based iframe embedding of the consent page, login page, or
admin panel is no longer possible by design. This is intentional security hardening.

If your integration relied on iframe embedding, you must move to a redirect-based OAuth2 flow.
There is no supported workaround — the framing restriction is a deliberate security control.

### Caddy syntax error (once Caddy layer is implemented)

If a Caddyfile change passes the `caddy validate` CI step but fails to reload in production
(rare), Caddy retains the previous running configuration. The deployment is considered failed —
investigate and fix the Caddyfile before retrying. Do not attempt to skip validation or deploy
a known-invalid Caddyfile.

---

## Security Considerations

### Caddy-layer headers are implemented

As of platform#18, the prod Caddyfile emits HSTS, X-Frame-Options, X-Content-Type-Options,
Referrer-Policy, and Permissions-Policy via the `(security_headers)` snippet. Browsers connecting
to all browser-facing vhosts receive the full header set.

- HSTS (`max-age=31536000; includeSubDomains; preload`) is active. Browsers will pin HTTPS for all
  covered domains after the first visit. Ensure the preload list submission is tracked separately
  if HSTS preloading is required.
- Clickjacking protection is now layered: `frame-ancestors 'none'` in the CSP (Hera and Athena only)
  plus `X-Frame-Options: DENY` from Caddy (all vhosts including Site).
- The Site vhost now receives `X-Frame-Options: DENY` from the Caddy `(security_headers)` snippet —
  this is its sole framing control (Site has no CSP middleware).

### Frame-ancestors ownership (once Caddy layer ships)

`frame-ancestors 'none'` in the CSP is authoritative for Hera and Athena. Changing `X-Frame-Options`
in the Caddyfile for those vhosts does not change the effective framing policy in any browser that
supports CSP (all current browsers). Future framing policy changes must update `middleware.ts`, not
the Caddyfile.

### Known limitation: `unsafe-inline` in `style-src`

Both Hera and Athena CSPs include `style-src 'unsafe-inline'`. This permits inline `<style>` blocks
and `style=` attributes, which is a CSS injection vector. In a CIAM context, CSS injection can be used
for credential-phishing overlays (styled form overlays that mimic the login form).

The risk is lower than script injection because CSS injection cannot exfiltrate data via network
requests directly. However, it is a real attack surface. Removing `unsafe-inline` from Hera's
`style-src` is tracked in hera#48 Phase 2, which is blocked on canvas#46 resolving its inline style
dependencies. The equivalent Athena hardening is tracked as a follow-on security task.

Do not add `'unsafe-inline'` to `script-src`. The nonce model means `'unsafe-inline'` in `script-src`
is ignored by the browser per spec, but it communicates incorrect intent. Always use nonces for scripts.

For the full CSP architecture for each app, see:
- Hera: `hera/docs/csp-configuration.md`
- Athena: `athena/docs/csp-configuration.md`

### Token handling

The CSP `connect-src 'self'` directive in Athena restricts all browser-initiated fetch calls to
same-origin. Cross-origin fetch calls from Athena pages to external endpoints are blocked by the CSP.
Server-side fetch calls (API routes, server components) are not subject to the CSP.

### Compliance

Implemented (platform#18):
- `frame-ancestors 'none'` in CSP directly addresses OWASP A05:2021 Security Misconfiguration
  (clickjacking protection) for Hera and Athena
- CSP `script-src` with nonce enforcement addresses OWASP A03:2021 Injection (XSS)
- HSTS (`max-age=31536000; includeSubDomains; preload`) satisfies SOC2 encryption-in-transit
  requirements by enforcing HTTPS on all subsequent requests from the browser
- `X-Content-Type-Options: nosniff` prevents MIME-type sniffing attacks on API responses
- `X-Frame-Options: DENY` provides legacy-browser clickjacking fallback for Hera and Athena;
  sole framing control for the Site vhost
