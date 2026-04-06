// pgAdmin Hydra claims mapper — platform#21
//
// Injects the 'roles' array from IAM Kratos identity traits into the ID token
// so pgAdmin's OAUTH2_ADDITIONAL_CLAIMS_VALIDATION hook can enforce 'dba' role
// membership as a second access control layer.
//
// IMPORTANT: Uses null-safe std.get() form — NOT direct trait access.
// Direct access (std.extVar('session').identity.traits.roles) throws a Jsonnet
// evaluation error for all existing identities that have no 'roles' trait.
// std.get() returns the default [] instead, which is safe and correct.
//
// Reference: docs/state/architecture-brief-pgadmin-oauth2-auto-create-user.md
local claims = {
  iss: std.extVar('claims').iss,
  sub: std.extVar('claims').sub,
  email: std.extVar('claims').email,
  roles: std.get(std.extVar('session').identity.traits, 'roles', []),
};
claims
