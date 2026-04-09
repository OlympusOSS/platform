# Caddy Supply-Chain Hardening

**Related tickets**: platform#47, platform#48, platform#49, platform#51
**Implemented**: 2026-04-08

## Overview

The custom Caddy image that powers Olympus rate limiting is built from source using `xcaddy`. This document covers the supply-chain controls in place for that build: version pinning, post-build verification, SHA-tagged image releases, and topology documentation for operators running Olympus behind a proxy.

These controls apply to the `ghcr.io/olympusoss/caddy` image and the `caddy-build.yml` CI workflow.

---

## How It Works

```
xcaddy build
  --with github.com/mholt/caddy-ratelimit@v0.1.0   # pinned — platform#47
       │
       ▼
  docker/build-push-action
    tags: latest, sha-<commit-sha>                   # SHA tag — platform#49
       │
       ▼
  verify job (needs: build-and-push)                 # smoke test — platform#48
    docker run caddy list-modules | grep http.handlers.rate_limit
```

The build-and-push step runs first, then the verify job. A failed verify job marks the workflow as failed and indicates the pushed image should not be referenced in `compose.prod.yml` until the build is fixed.

---

## Version Pin: caddy-ratelimit (platform#47)

The `mholt/caddy-ratelimit` module is pinned to a specific tagged release in `platform/caddy/Containerfile`:

```dockerfile
RUN xcaddy build --with github.com/mholt/caddy-ratelimit@v0.1.0
```

Without a version pin, xcaddy resolves to the latest commit on the default branch at build time. A malicious or accidental upstream change could silently alter rate limiting behavior in production.

**Pinned version details:**

| Property | Value |
|----------|-------|
| Tag | `v0.1.0` |
| Commit SHA | `12435ecef5dbb1b137eb68002b85d775a9d5cdb2` |
| Tag object SHA | `0233197853598a2c6ec005bdfdc7992876625a60` |
| Tagger | Matthew Holt (PGP-verified) |
| Pin date | 2026-04-08 |

The commit SHA is recorded in the Containerfile for supply-chain traceability. To verify independently:

```bash
gh api repos/mholt/caddy-ratelimit/git/refs/tags/v0.1.0
```

The returned object SHA should dereference to commit `12435ecef5dbb1b137eb68002b85d775a9d5cdb2`.

**Upgrade procedure** (documented in `platform/caddy/Containerfile`):
1. Check mholt/caddy-ratelimit releases for the new version
2. Verify the new tag exists and is a real release (not a pre-release or commit SHA)
3. Update the `@v<version>` pin in the Containerfile
4. Record the new commit SHA and update the Containerfile comment
5. Run the smoke test (see below) to confirm the module builds correctly

**Residual risk**: The Caddy base image (`caddy:2-builder-alpine`, `caddy:2-alpine`) uses mutable floating tags. This is tracked in platform#72 as a future hardening item.

---

## Post-Build Smoke Test (platform#48)

Every build of the Caddy image is verified by a `verify` job in `caddy-build.yml`:

```bash
docker run --rm ghcr.io/olympusoss/caddy:latest caddy list-modules | grep -q http.handlers.rate_limit
```

The verify job runs after `build-and-push` completes (enforced via `needs: [build-and-push]`).

**What this test IS**: A build-time module presence check. It confirms the `http.handlers.rate_limit` module binary is present in the built image.

**What this test IS NOT**: This check does not verify Caddyfile parse correctness, module initialization, or runtime rate limiting behavior. A green verify job does not constitute a PASS verdict on rate limiting — it confirms the module was built into the image. Runtime verification is performed during deployment health checks.

**If the verify job fails**: The workflow is marked failed. Do not update `compose.prod.yml` to reference the new image until the workflow is green. There is no automated process that pulls `caddy:latest` from GHCR — the compose file is operator-updated only.

**Rate-limiting debugging chain** for operators:

1. `caddy-build.yml` verify job green → module binary is present in the image
2. `caddy validate` with the production Caddyfile → configuration is syntactically valid
3. Deployment health check passes → Caddy is running and handling requests
4. Test a rate-limit breach with a controlled request flood → rate limiting is active at runtime

A failure at step 1 means the module was not built into the image. A failure at step 2-4 while step 1 is green means a configuration or initialization issue.

---

## SHA-Tagged Image Releases (platform#49)

Every successful `caddy-build.yml` run pushes two tags to GHCR:

| Tag | Mutability | Purpose |
|-----|-----------|---------|
| `ghcr.io/olympusoss/caddy:latest` | Mutable — overwritten on each build | Current production image |
| `ghcr.io/olympusoss/caddy:sha-<full-sha>` | Effectively immutable per commit | Rollback reference |

The SHA tag uses the full 40-character commit SHA (`github.sha`), not a 7-character abbreviation. This eliminates collision risk and allows copy-paste from GitHub Actions run logs without truncation.

**Rollback procedure** (also documented in `platform/prod/compose.prod.yml`):

1. Find the target SHA: open the `caddy-build.yml` workflow run in GitHub Actions and confirm the verify job was green
2. Copy the full commit SHA from the run
3. Pull the sha-tagged image: `podman pull ghcr.io/olympusoss/caddy:sha-<full-sha>`
4. Update `compose.prod.yml`: change `image: ghcr.io/olympusoss/caddy:latest` to `image: ghcr.io/olympusoss/caddy:sha-<full-sha>`
5. Redeploy and verify the health check passes

Only use images from workflow runs where both the `build-and-push` and `verify` jobs completed green.

**Known limitation**: GHCR does not enforce tag immutability by default. If a workflow is re-run on the same commit, the sha-tag is overwritten with the new build (same commit SHA, different image digest). Treat sha-tags as write-once — avoid re-running workflows on the same commit in production.

**Follow-up tracked in platform#72**: Pinning `compose.prod.yml` to sha-tagged images instead of `latest` will close the operational traceability gap where the exact running image digest is not recorded at deploy time.

---

## Proxy-in-Front Topology (platform#51)

The Caddy rate limit key is `remote.host` (TCP peer address). This is correct for the current direct-connect topology where Caddy is the first hop from clients.

**If you deploy Olympus behind a load balancer, CDN, or reverse proxy**, the `remote.host` key will rate-limit on the proxy's IP address rather than the real client IP, effectively counting all users as one.

### What to change

When introducing a proxy in front of Caddy, update the rate limit configuration in both `platform/dev/Caddyfile` and `platform/prod/Caddyfile`:

```caddy
# Current (direct-connect topology):
key    remote.host

# Required (proxy-in-front topology):
trusted_proxies <proxy-cidr-only>       # e.g. 10.0.0.0/8
key    {http.request.header.X-Forwarded-For}
```

Before deploying, verify the exact key placeholder syntax against the installed caddy-ratelimit module version:

```bash
caddy validate --config /path/to/Caddyfile
```

Do not copy the `{http.request.header.X-Forwarded-For}` placeholder verbatim without validating against the module version in use — placeholder syntax may vary across caddy-ratelimit releases.

### CIDR scoping requirement

Set `trusted_proxies` to the specific CIDR of the upstream proxy only. Never use `trusted_proxies 0.0.0.0/0`. Trusting all source IPs enables any client to supply an arbitrary `X-Forwarded-For` value, allowing them to impersonate any source IP and bypass per-IP rate limiting entirely.

### Accepted residual risk

Per-IP rate limiting does not mitigate distributed brute force where an attacker rotates IP addresses across a botnet. This is an accepted residual risk at the rate-limiting layer. The CAPTCHA layer (platform#17) provides additional protection. Botnet-scale attacks require a WAF or Cloudflare-level control outside the scope of the Caddy configuration.

---

## Security Considerations

- **Version pin**: the `caddy-ratelimit@v0.1.0` pin prevents silent upstream changes from altering rate limiting behavior. Monitor mholt/caddy-ratelimit releases for security patches and update the pin promptly.
- **Smoke test scope**: a green `caddy-build.yml` verify job confirms module presence only — not runtime correctness. Do not use it as evidence that rate limiting is active in production.
- **SHA tag rollback**: before rolling back to a sha-tagged image, verify the workflow run was fully green (both build-and-push and verify jobs). A sha-tag from a failed run may reference a broken image.
- **GHCR force-push policy**: treat sha-tagged images as write-once. Re-running a workflow on the same commit overwrites the sha-tag with a new image digest, which invalidates the rollback reference.
- **Proxy CIDR scope**: `trusted_proxies 0.0.0.0/0` silently disables IP-based rate limiting by allowing spoofed X-Forwarded-For headers. Always scope to the specific upstream proxy CIDR.

---

## CI Enforcement

| Check | Workflow | Trigger | What it catches |
|-------|----------|---------|----------------|
| Module present in built image | `caddy-build.yml` (verify job) | Push to `caddy/`, `workflow_dispatch` | Build that silently drops the rate-limit module |
| Containerfile version pin | Static review | PR touching `caddy/Containerfile` | Removal of `@v<version>` suffix from xcaddy `--with` flag |

For the Kratos `leak_sensitive_values` CI check, see [kratos-production-config.md](kratos-production-config.md).
