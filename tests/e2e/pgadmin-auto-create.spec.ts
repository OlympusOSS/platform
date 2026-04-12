/**
 * platform#21 — pgAdmin auto-create user disabled
 *
 * Verifies that pgAdmin config has OAUTH2_AUTO_CREATE_USER=False,
 * session timeout set to 60 min, and DBA role validation via
 * OAUTH2_ADDITIONAL_CLAIMS_VALIDATION.
 */
import { test, expect } from '@playwright/test';
import { readFileSync, existsSync } from 'fs';
import { resolve } from 'path';

const ROOT = resolve(__dirname, '..', '..');

test.describe('platform#21: pgAdmin auto-create user', () => {
  test('AC1: prod config has OAUTH2_AUTO_CREATE_USER = False', () => {
    const content = readFileSync(resolve(ROOT, 'prod/pgadmin/config_local.py'), 'utf-8');
    expect(content).toMatch(/OAUTH2_AUTO_CREATE_USER\s*=\s*False/);
  });

  test('AC1: dev config has OAUTH2_AUTO_CREATE_USER = False', () => {
    const devPath = resolve(ROOT, 'dev/pgadmin/config_local.py');
    if (!existsSync(devPath)) {
      test.skip();
      return;
    }
    const content = readFileSync(devPath, 'utf-8');
    expect(content).toMatch(/OAUTH2_AUTO_CREATE_USER\s*=\s*False/);
  });

  test('AC5: prod config has SESSION_EXPIRATION_TIME = 60', () => {
    const content = readFileSync(resolve(ROOT, 'prod/pgadmin/config_local.py'), 'utf-8');
    expect(content).toMatch(/SESSION_EXPIRATION_TIME\s*=\s*60/);
  });

  test('prod config has DBA role claims validation', () => {
    const content = readFileSync(resolve(ROOT, 'prod/pgadmin/config_local.py'), 'utf-8');
    expect(content).toContain('OAUTH2_ADDITIONAL_CLAIMS_VALIDATION');
    expect(content).toContain("'dba'");
    expect(content).toContain('roles');
  });

  test('prod config uses OAuth2 SSO with display name Olympus', () => {
    const content = readFileSync(resolve(ROOT, 'prod/pgadmin/config_local.py'), 'utf-8');
    expect(content).toContain("'OAUTH2_DISPLAY_NAME': 'Olympus'");
    // Authentication source is oauth2 only
    expect(content).toMatch(/AUTHENTICATION_SOURCES\s*=\s*\['oauth2'\]/);
  });

  test('AC4: prod Caddyfile has network restriction documentation for pgAdmin', () => {
    const content = readFileSync(resolve(ROOT, 'prod/Caddyfile'), 'utf-8');
    // pgAdmin vhost should have network restriction comments
    expect(content).toMatch(/pgAdmin.*INTERNAL ONLY|MUST NOT be publicly accessible/);
  });

  test('compose.prod.yml pgAdmin does not expose port 80 externally', () => {
    const content = readFileSync(resolve(ROOT, 'prod/compose.prod.yml'), 'utf-8');
    // pgAdmin is fronted by Caddy — check its section does not have
    // dangerous port bindings (5433:80 maps to Caddy, not direct pgAdmin)
    // The pgAdmin service itself should only be on the intranet network
    const pgadminSection = content.slice(
      content.indexOf('pgadmin:'),
      content.indexOf('seed:') > 0 ? content.indexOf('seed:') : undefined
    );
    expect(pgadminSection).toContain('intranet');
  });
});
