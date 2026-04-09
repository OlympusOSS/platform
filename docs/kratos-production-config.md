# Kratos Production Configuration Requirements

**Related ticket**: platform#25
**Implemented**: 2026-04-08

## Overview

This document covers configuration flags in Ory Kratos that have critical security implications in production. It is paired with a CI enforcement workflow (`verify-prod-config.yml`) that prevents dangerous configurations from reaching production.

---

## leak_sensitive_values

The `log.leak_sensitive_values` flag in Ory Kratos controls whether sensitive data is written to structured logs.

When set to `true`, Kratos logs:
- Plaintext TOTP secrets
- Session tokens
- Credentials

These values would appear verbatim in any connected log aggregation system (Datadog, CloudWatch, Loki, Splunk). Any user with log viewer access gains session hijacking material.

**Required production value**: `false` (or absent — Kratos defaults to `false`)

```yaml
# platform/prod/ciam-kratos/kratos.yml
log:
  leak_sensitive_values: false  # line 83

# platform/prod/iam-kratos/kratos.yml
log:
  leak_sensitive_values: false  # line 58
```

**Dev configs intentionally differ**: `platform/dev/ciam-kratos/kratos.yml` (line 102) and `platform/dev/iam-kratos/kratos.yml` (line 74) have `leak_sensitive_values: true` to aid local debugging. This is expected and correct — do not copy dev configs to production.

### CI enforcement

The `verify-prod-config.yml` workflow prevents `leak_sensitive_values: true` from reaching production:

```bash
grep -rE 'leak_sensitive_values:\s*true' platform/prod/
```

The grep targets `platform/prod/` only — dev configs are excluded to avoid false positives from the intentional dev setting.

**Trigger**: every push to `main` (authoritative gate) and every pull request (fast feedback). The push-to-main trigger is the safety net — it catches configs added to non-standard paths that the PR path filter might miss.

**On failure**: the workflow exits non-zero with a clear error identifying the setting. Branch protection must require this check to pass before merge.

**YAML edge case**: Ory Kratos uses Go's `yaml.v3` parser, which does NOT coerce the quoted string `"true"` to a boolean. The pattern `leak_sensitive_values:\s*true` (unquoted) is sufficient — the quoted-string form `leak_sensitive_values: "true"` is inert and will not enable sensitive logging.

### Relationship to platform#9

Platform#9 (secrets audit) confirmed the current production state: both prod Kratos configs have `leak_sensitive_values: false`. Platform#25 adds the CI regression prevention control — the check that catches future accidental changes. The two tickets are complementary.

---

## TOTP Issuer Name

The `selfservice.methods.totp.config.issuer` field controls the name shown in authenticator apps
(Google Authenticator, Authy, 1Password, etc.) when a user enrolls TOTP for their account.

**Required production value**: `Olympus`

```yaml
# platform/prod/ciam-kratos/kratos.yml
selfservice:
  methods:
    totp:
      config:
        issuer: Olympus
      enabled: true
```

**Why this matters**: the issuer name is embedded in the `otpauth://` URI when Kratos generates
the TOTP QR code. It appears as the account label in the authenticator app. If left as `Kratos`,
users see the internal service name — not the product name. This was corrected in platform#20.

**Existing enrollments**: users who enrolled TOTP before this change continue to see the old issuer
name in their authenticator app. The change applies only to new enrollments. Existing TOTP codes
remain valid and functional — the issuer name is cosmetic after enrollment and does not affect
TOTP validation. Users who want to update the displayed name can re-enroll voluntarily.

**Dev and prod must match**: both `platform/dev/ciam-kratos/kratos.yml` and
`platform/prod/ciam-kratos/kratos.yml` use `issuer: Olympus`. IAM Kratos configs also use
`issuer: Olympus` if TOTP is enabled for the IAM domain.

**White-label deployments**: operators customizing Olympus for their own product can change this
value to match their brand. No other configuration changes are required — the issuer name has
no security role; it is purely a display label.

---

## Secrets from environment variables only

All Kratos cookie and cipher secrets must reference environment variable substitutions in both `compose.prod.yml` and the Kratos YAML configs. Hardcoded values are never acceptable.

Production secrets are sourced from GitHub Actions Secrets via `deploy.yml`. See [secrets-audit.md](secrets-audit.md) for the full production secret inventory.

---

## Configuration Files

| File | Purpose | `leak_sensitive_values` |
|------|---------|------------------------|
| `platform/prod/ciam-kratos/kratos.yml` | CIAM production Kratos config | `false` (line 83) |
| `platform/prod/iam-kratos/kratos.yml` | IAM production Kratos config | `false` (line 58) |
| `platform/dev/ciam-kratos/kratos.yml` | CIAM development Kratos config | `true` (intentional — dev debugging) |
| `platform/dev/iam-kratos/kratos.yml` | IAM development Kratos config | `true` (intentional — dev debugging) |

---

## Security Considerations

- **GDPR Article 32**: credential and session token exposure in logs constitutes a failure to implement appropriate technical measures for security of processing. Production configs must have `leak_sensitive_values: false`.
- **SOC2 CC6.1, CC6.7**: audit logging must not contain cleartext credentials. The CI check provides persistent enforcement.
- **Log aggregation**: if your production deployment sends Kratos logs to an external aggregation system, `leak_sensitive_values: true` means TOTP codes and session tokens appear in that system accessible to any log viewer. Treat this setting as security-critical.
- **Dev-to-prod promotion**: the most common misconfiguration path is copying or promoting a dev config file to production without reviewing the diff. The CI check is the catch — it will fail the PR before merge.
- **Operators outside the repo**: the CI check only runs for commits to this repository. Operators deploying Olympus on a fork or via a custom pipeline should include the equivalent grep in their own CI. See the production hardening guide story (DX-25-1) for a planned checklist covering this and other required configuration verifications.
