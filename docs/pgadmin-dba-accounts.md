# pgAdmin Pre-Provisioned DBA Accounts

## Overview

`OAUTH2_AUTO_CREATE_USER = False` in pgAdmin's configuration means pgAdmin never automatically
creates an account for an authenticating IAM identity. A pgAdmin user record must exist before
a DBA can log in. This file is the registry of those pre-provisioned accounts.

**Deployment gate**: at least one DBA account must be pre-provisioned and verified to log in
successfully before `OAUTH2_AUTO_CREATE_USER = False` is deployed. Deploying the config change
without a pre-provisioned account locks out all current DBAs. This requirement was established
as a blocking AC condition in platform#21.

---

## Provisioned Accounts

| Email | pgAdmin Role | IAM Kratos Identity | Provisioned Date | Provisioned By | Notes |
|-------|-------------|--------------------|-----------------|-----------------------|-------|
| _(populate before deploying platform#21)_ | | | | | |

**pgAdmin Role** values: `Administrator` (full user management access) or `User` (database access only).

To verify an account is active: the DBA must successfully log in via pgAdmin SSO ("Login with
Olympus") and reach the pgAdmin dashboard before the entry is marked provisioned.

---

## How to Add an Account

1. Verify the DBA has an IAM Kratos identity with `"dba"` in their `roles` trait. See the
   provisioning steps in [pgadmin-access.md](./pgadmin-access.md).
2. Log in to pgAdmin as an existing pgAdmin Administrator.
3. Navigate to User Management (top menu — click your username, then "User Management").
4. Click "Add User", enter the DBA's email (must match IAM Kratos identity email exactly),
   set the pgAdmin role, and save.
5. Add the DBA's email to the table above with the provisioned date and your name.
6. Instruct the DBA to verify access via pgAdmin SSO.

---

## How to Remove an Account

Follow the offboarding runbook at [runbook-pgadmin-dba-offboarding.md](./runbook-pgadmin-dba-offboarding.md).
Remove the entry from the table above after offboarding step 3 (pgAdmin user record deleted)
is confirmed.

---

## Registry Notes

This file is maintained manually. It is the source of truth for pgAdmin access audit purposes.

- All changes to this file must go through a pull request — do not edit directly on main
- The registry must be kept current: add entries when provisioning, remove entries when
  offboarding is complete
- For SOC2 CC6.3 evidence, this registry documents the current set of identities with
  privileged database access
- Access to this file is not restricted — it is an internal documentation artifact, not a
  secret. Email addresses in this file are IAM identities, not credentials.
