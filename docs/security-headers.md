# Security Headers

## Overview

Olympus applies HTTP security headers at two layers: Caddy (the reverse proxy) owns structural,
protocol-level headers; Next.js middleware owns Content-Security-Policy. Each header is owned by
exactly one layer. The same header must never appear in both.

This two-layer model was implemented in platform#18. The Caddy layer prevents clickjacking, HTTPS
downgrades, and MIME-type sniffing attacks across all vhosts. The Next.js layer provides a
per-request nonce-based CSP that restricts which scripts may execute in the browser.

---

## How It Works

### Header Ownership — Authoritative Assignment

| Header | Owner | Set Where |
|--------|-------|-----------|
| `Strict-Transport-Security` | Caddy | Caddyfile `(security_headers)` snippet |
| `X-Frame-Options` | Caddy | Caddyfile `(security_headers)` snippet |
| `X-Content-Type-Options` | Caddy | Caddyfile `(security_headers)` snippet |
| `Referrer-Policy` | Caddy | Caddyfile `(security_headers)` snippet |
| `Permissions-Policy` | Caddy | Caddyfile `(security_headers)` snippet |
| `Content-Security-Policy` | Next.js | `src/middleware.ts` in Hera and Athena |

**Rule**: Next.js must not emit `X-Frame-Options`, `Strict-Transport-Security`, `X-Content-Type-Options`,
or `Referrer-Policy`. Caddy must not emit `Content-Security-Policy`.

### Caddy Snippets

Two Caddyfile snippets handle the UI vs. API vhost distinction:

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

**`(api_security_headers)`** — applied to Hydra API vhosts (no `X-Frame-Options`; Hydra serves API
responses, not browser UIs):

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
script-src 'self' 'nonce-{NONCE}' https://challenges.cloudflare.com;
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
It supersedes `X-Frame-Options` in all modern browsers. `X-Frame-Options: DENY` in Caddy is the
legacy-browser fallback only.

**Consequence for future changes**: if you need to modify the framing policy for Hera or Athena,
update `frame-ancestors` in `src/middleware.ts`. Changing `X-Frame-Options` in the Caddyfile for
those vhosts has no effect in modern browsers. For the Site vhost (which has no CSP), `X-Frame-Options`
in the Caddyfile is the only framing control.

---

## API / Technical Details

### Nonce Propagation in Next.js

```typescript
// middleware.ts (Hera)
const nonceBytes = new Uint8Array(16);
crypto.getRandomValues(nonceBytes);
const nonce = btoa(String.fromCharCode(...nonceBytes));

const csp = [
  "default-src 'self'",
  `script-src 'self' 'nonce-${nonce}' https://challenges.cloudflare.com`,
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

A `caddy validate` CI step runs before the Caddyfile is synced to production, using the Caddy
Docker image to avoid runner dependency issues:

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

You should see:
- `content-security-policy: default-src 'self'; script-src 'self' 'nonce-...` (unique per request)
- `strict-transport-security: max-age=31536000; includeSubDomains; preload`
- `x-frame-options: DENY`
- `x-content-type-options: nosniff`
- `referrer-policy: strict-origin-when-cross-origin`
- `permissions-policy: geolocation=(), microphone=(), camera=()`

### Verifying nonce is applied to script tags

In Chrome DevTools Elements tab, run in the console:

```javascript
document.querySelectorAll('script[nonce]').length
// Expected: all scripts have a nonce attribute matching the CSP header nonce
```

### Verifying no duplicate headers

Each security header should appear exactly once in the response. If `content-security-policy`
appears twice, Caddy is also emitting CSP — check that no Caddy vhost sets a `Content-Security-Policy`
header directive.

---

## Edge Cases

### CSP violation blocks a third-party script during development

CSP is active in local dev — it is not disabled for development. When a CSP violation blocks a
resource, the browser console shows the blocked URL and the violated directive.

To allow a new script origin during development, add it to the middleware CSP template in
`src/middleware.ts`. Do not set `'unsafe-inline'` or `'unsafe-eval'` as a workaround — this
defeats the CSP entirely.

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

### Caddy syntax error

If a Caddyfile change passes the `caddy validate` CI step but fails to reload in production
(rare), Caddy retains the previous running configuration. The deployment is considered failed —
investigate and fix the Caddyfile before retrying. Do not attempt to skip validation or deploy
a known-invalid Caddyfile.

---

## Security Considerations

### Frame-ancestors ownership

`frame-ancestors 'none'` in the CSP is authoritative for Hera and Athena. Changing `X-Frame-Options`
in the Caddyfile for those vhosts does not change the effective framing policy in any browser that
supports CSP (all current browsers). Future framing policy changes must update `middleware.ts`, not
the Caddyfile.

### Known limitation: `unsafe-inline` in `style-src`

The current CSP allows `'unsafe-inline'` in `style-src`. This permits inline `<style>` blocks and
`style=` attributes, which is a CSS injection vector. In a CIAM context, CSS injection can be used
for credential-phishing overlays (styled form overlays that mimic the login form).

The risk is lower than script injection because CSS injection cannot exfiltrate data via network
requests directly. However, it is a real attack surface. Follow-on tickets hera#48 and the equivalent
in athena track the work to remove `unsafe-inline` from `style-src` using nonce-based or hash-based
style sources.

Do not add `'unsafe-inline'` to `script-src`. The nonce model means `'unsafe-inline'` in `script-src`
is ignored by the browser per spec, but it communicates incorrect intent. Always use nonces for scripts.

### Token handling

The CSP `connect-src 'self'` directive in Athena restricts all browser-initiated fetch calls to
same-origin. Cross-origin fetch calls from Athena pages to external endpoints are blocked by the CSP.
Server-side fetch calls (API routes, server components) are not subject to the CSP.

### Compliance

- HSTS (`max-age=31536000; includeSubDomains; preload`) satisfies SOC2 encryption-in-transit
  requirements by enforcing HTTPS on all subsequent requests from the browser
- `X-Content-Type-Options: nosniff` prevents MIME-type sniffing attacks on API responses
- `frame-ancestors 'none'` and `X-Frame-Options: DENY` directly address OWASP A05:2021 Security
  Misconfiguration (clickjacking protection)
- CSP `script-src` with nonce enforcement addresses OWASP A03:2021 Injection (XSS)
