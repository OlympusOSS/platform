# OIDC Email Verification Trust Path — Architectural Decision

**Decision recorded**: 2026-04-05
**Context**: platform#24 (SR: Verify mandatory email verification in CIAM Kratos)
**Required by**: Security Expert APPROVED WITH CONDITIONS, Condition 3 — OIDC Architecture Brief prerequisite

---

## Decision

**Option B is the current deliberate behaviour**: Kratos always requires its own email verification, regardless of whether the OIDC provider asserts `email_verified: true` in the ID token.

This means: when a user registers via an OIDC provider (e.g. Google), even if the provider's token contains `email_verified: true`, Kratos will:
1. Create the identity with the provider-supplied email address
2. Mark the email as unverified in Kratos's internal state
3. Block the user's first login attempt via the `require_verified_address` hook
4. Send a verification email to the provider-supplied address
5. Allow login only after the user clicks the verification link

## Rationale

- Option B is the default Kratos behaviour — no mapper configuration is required
- No OIDC provider is currently configured in either dev or prod Kratos configs; this decision is recorded in advance for when OIDC is added
- Option B is more conservative: it does not trust provider-side claims, which could be stale or (in edge cases) spoofed
- The trade-off is a worse first-login UX for social users: they must re-verify an email they already verified with their provider

## When This Decision Must Be Revisited

When the OIDC social login feature story is implemented, the Architecture Brief for that story **MUST** explicitly resolve the Option A vs Option B choice. This document is a required prerequisite for that Architecture Brief to be approved.

If the team decides to adopt Option A (trust `email_verified: true` from specific providers), the implementation requires:
1. A Jsonnet mapper that sets the identity's email verification state to `true` when the provider claim `email_verified: true` is present
2. Per-provider configuration (trusting Google's claim is not the same as trusting all providers)
3. A Security Expert review of the trust decision for each provider

**This document must be referenced in the OIDC Architecture Brief review as condition of approval.**

## Current Config State

Neither `platform/dev/ciam-kratos/kratos.yml` nor `platform/prod/ciam-kratos/kratos.yml` currently has any `selfservice.methods.oidc` section. There are no OIDC providers configured today. The `require_verified_address` hook will enforce Option B for any OIDC provider added without explicit mapper configuration.

## Relevant Config (both dev and prod)

```yaml
selfservice:
  flows:
    login:
      after:
        hooks:
          - hook: require_verified_address  # This blocks unverified OIDC users on first login
```

## References

- platform#24 — SR: Verify mandatory email verification in CIAM Kratos
- Architecture Brief (Architect comment on platform#24) — Section 2, DA Condition 2
- Security Expert review (platform#24) — V2, SR-EMAIL-VERIFY-2
- DA review (platform#24) — Condition 3
