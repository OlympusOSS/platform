# RELOAD_API_KEY Rotation Runbook

**Last updated**: 2026-04-05
**Ticket**: platform#31
**ADR reference**: `docs/state/ADR-003-social-login-config-reload.md`

---

> **NOTE: This runbook is pre-work pending platform#50 (sidecar compose implementation).**
> The `ciam-kratos-reload-sidecar` service is not yet defined in either compose file.
> This runbook documents the intended operational model and rotation procedure against
> the interface contract specified in ADR-003. It cannot be end-to-end validated until
> platform#50 is merged. When platform#50 lands, validate this runbook against the
> actual compose definition and remove this notice.

---

## Overview

The `CIAM_RELOAD_API_KEY` is a platform-layer pre-shared key that authenticates
`ciam-athena`'s calls to the `ciam-kratos-reload-sidecar` internal reload endpoint
(`POST /internal/kratos/reload`). It is sent in the `X-Reload-Api-Key` HTTP header on
each call. The sidecar validates the header before accepting the reload instruction.

This key is **not user-facing** and is **never returned in API responses**. It is a
platform secret, analogous to a database password.

**Services holding this key**:
- `ciam-athena` — sends it in the `X-Reload-Api-Key` header
- `ciam-kratos-reload-sidecar` — validates the header; rejects with 401 on mismatch

**Key lifetime**: Maximum 90 days (recommended). Rotate immediately on suspected compromise.

---

## Key Generation

Generate a new 32-byte cryptographically random key:

```bash
openssl rand -hex 32
```

This produces a 64-character hex string (256-bit entropy). Do not use any other
generation method. Do not reuse previous values. Do not copy from one environment
to another.

---

## Safe Rotation Ordering

Both `ciam-athena` and `ciam-kratos-reload-sidecar` must hold the same key value for
reload calls to succeed. Restarting one container without the other creates a window
where reload calls fail with 401.

**During this window**: any social connection config save in Athena will succeed at the
SDK write layer (the config is stored in the database) but the Kratos config reload will
not execute. The social connection change will appear saved in the UI but will not be
applied to Kratos until the next successful reload.

**Specified safe ordering** (minimises the window to seconds):

1. Generate a new key: `openssl rand -hex 32`
2. Update the key value in the appropriate location (see environment-specific sections below)
3. Restart `ciam-kratos-reload-sidecar` first — the sidecar now validates the new key;
   any in-flight reload calls from Athena using the old key will 401 until Athena restarts
4. Restart `ciam-athena` **immediately** after step 3 — Athena picks up the new key from
   its environment; from this point all reload calls use the new key and succeed

Execute steps 3 and 4 in immediate succession. The window between them is bounded by
the time to issue the second restart command (seconds in practice).

---

## Post-Rotation Verification

After both containers are restarted:

**Step 1 — Verify key synchronization (Athena-to-sidecar hop)**:
1. Log in to CIAM Athena (localhost:3001 in dev; `$CIAM_ATHENA_PUBLIC_URL` in prod)
2. Navigate to Social Connections settings
3. Save a social connection config without changing any values (no-op save)
4. Confirm the UI shows a success response (not a 401 or error)

**Step 2 — Verify Kratos reloaded its config (full chain)**:
After the no-op save succeeds, check the `ciam-kratos` container logs for a config
reload event. A SIGHUP-triggered reload produces a log entry confirming the config
was parsed.

In dev:
```bash
podman logs ciam-kratos 2>&1 | grep -i -E "(reload|sighup|config)" | tail -20
```

In prod (via the deployment server):
```bash
podman logs ciam-kratos 2>&1 | grep -i -E "(reload|sighup|config)" | tail -20
```

Confirm there is a recent log entry (timestamp matching the rotation time) indicating
Kratos acknowledged the SIGHUP and reloaded its configuration. If no such entry is
present, Kratos may not have received the SIGHUP or the config may have failed to parse.
In that case, check `ciam-kratos-reload-sidecar` logs and inspect the OIDC config fragment.

**If Athena shows a 401 on the no-op save** (rotation window hit):
This means Athena and the sidecar still hold different key values. Confirm both containers
have finished restarting and check which container is using the old value. Re-run steps 3-4
of the rotation ordering above. Then re-run the post-rotation verification steps.

---

## Dev Environment Rotation

1. Generate a new key:
   ```bash
   openssl rand -hex 32
   ```
2. Update `CIAM_RELOAD_API_KEY` in `platform/dev/.env`
3. From `platform/dev/`:
   ```bash
   podman compose restart ciam-kratos-reload-sidecar
   podman compose restart ciam-athena
   ```
4. Perform post-rotation verification (see above)

**Dev environment dependency**: The post-rotation verification step requires:
- A social connection configured in the dev environment
- Both `ciam-athena` and `ciam-kratos-reload-sidecar` running and healthy
- The overall dev environment operational

If the dev environment is degraded (check current status in `docs/state/system-status.md`),
resolve the instability first, then re-validate the rotation.

---

## Production Rotation

> **POLICY**: All production deployments go through GitHub Actions (deploy.yml).
> Direct SSH access to restart containers in production is **prohibited by the platform
> deployment policy** (CLAUDE.md: "All production deployments go through GitHub Actions —
> never deploy directly from a local machine via SSH, rsync, or manual commands").
>
> A targeted single-credential rotation workflow (`rotate-key.yml`) that would restart
> only the two affected containers without a full-stack redeploy is a planned V2
> improvement. Until it is available, the `deploy.yml` full-stack path is the only
> policy-compliant production rotation mechanism.

### Current production rotation procedure (deploy.yml)

1. Generate a new key:
   ```bash
   openssl rand -hex 32
   ```
2. Update the `CIAM_RELOAD_API_KEY` GitHub Secret in `OlympusOSS/platform`:
   - Repository Settings → Secrets and Variables → Actions → Secrets
   - Update `CIAM_RELOAD_API_KEY` with the new value
3. Trigger `deploy.yml` (full-stack redeployment):
   - Actions → Deploy → Run workflow → production
4. Wait for the workflow to complete
5. Perform post-rotation verification (see above):
   - Navigate to CIAM Athena in production
   - Perform a no-op social connection config save
   - Confirm success response
   - Check `ciam-kratos` container logs for a SIGHUP reload event

**Blast radius note**: `deploy.yml` redeploys the full platform stack. All services restart,
not just the two containers holding the key. This causes a brief downtime for all users
during the restart window. This is a known limitation of the current rotation mechanism.

### V2 improvement (future)

A dedicated `rotate-key.yml` GitHub Actions workflow is planned that will:
- Target only `ciam-kratos-reload-sidecar` and `ciam-athena` for restart
- Eliminate full-stack redeployment for credential rotation
- Provide zero-downtime key rotation without direct server access

This is tracked as a separate backlog story. See the GitHub project board for status.

---

## Dev/Prod Key Separation

Dev and prod environments **MUST use independently generated key values**. Never:
- Copy a key from dev to prod or vice versa
- Reuse a previous key value
- Use the same value in multiple environments

**Current state**: Neither `platform/dev/compose.dev.yml` nor `platform/prod/compose.prod.yml`
currently defines `CIAM_RELOAD_API_KEY`. This is a gap, not a security property. The variable
will be added to both environments when platform#50 (sidecar compose definition) is implemented.

**For new environment provisioning**: run `openssl rand -hex 32` independently for each
environment at initial setup. Store in:
- Dev: `platform/dev/.env` as `CIAM_RELOAD_API_KEY=<generated value>`
- Prod: GitHub Secret `CIAM_RELOAD_API_KEY` in `OlympusOSS/platform`

---

## 90-Day Rotation Cadence

The recommended maximum key lifetime is 90 days. Rotate immediately if there is any
suspicion of key compromise (e.g. accidental log exposure, unauthorized access to the
production server, GitHub Secrets audit anomaly).

An automated 90-day rotation reminder (scheduled GitHub Actions workflow) is a planned
V2 improvement. Until it is available, the rotation schedule must be tracked manually
(calendar reminder, team process, etc.).

---

## Related

- `docs/state/ADR-003-social-login-config-reload.md` — sidecar architecture decision record
- platform#50 — Add ciam-kratos-reload-sidecar service to compose files (BLOCKING prerequisite)
- platform#31 — This runbook's origin ticket
