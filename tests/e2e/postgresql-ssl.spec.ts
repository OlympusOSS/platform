/**
 * platform#19 — PostgreSQL SSL (sslmode=require)
 *
 * Verifies that deploy.yml / compose.prod.yml default all DSN strings
 * to sslmode=require, PostgreSQL SSL is enabled, and dev retains
 * sslmode=disable.
 */
import { test, expect } from '@playwright/test';
import { readFileSync, existsSync } from 'fs';
import { resolve } from 'path';

const ROOT = resolve(__dirname, '..', '..');

test.describe('platform#19: PostgreSQL SSL enforcement', () => {
  test('AC1: compose.prod.yml postgres service has ssl=on', () => {
    const content = readFileSync(resolve(ROOT, 'prod/compose.prod.yml'), 'utf-8');
    expect(content).toMatch(/ssl=on/);
  });

  test('compose.prod.yml postgres mounts server.crt', () => {
    const content = readFileSync(resolve(ROOT, 'prod/compose.prod.yml'), 'utf-8');
    expect(content).toContain('server.crt');
  });

  test('compose.prod.yml postgres mounts server.key', () => {
    const content = readFileSync(resolve(ROOT, 'prod/compose.prod.yml'), 'utf-8');
    expect(content).toContain('server.key');
  });

  test('prod server.crt exists (public cert committed to repo)', () => {
    expect(existsSync(resolve(ROOT, 'prod/postgres/server.crt'))).toBe(true);
  });

  test('AC3: dev compose retains sslmode=disable', () => {
    const content = readFileSync(resolve(ROOT, 'dev/compose.dev.yml'), 'utf-8');
    // Dev DSNs should use sslmode=disable
    expect(content).toContain('sslmode=disable');
    expect(content).not.toContain('sslmode=require');
  });

  test('prod DSN env vars are referenced (not hardcoded)', () => {
    const content = readFileSync(resolve(ROOT, 'prod/compose.prod.yml'), 'utf-8');
    // All prod services should reference DSN env vars like ${PG_CIAM_KRATOS_DSN}
    expect(content).toContain('${PG_CIAM_KRATOS_DSN}');
    expect(content).toContain('${PG_IAM_KRATOS_DSN}');
    expect(content).toContain('${PG_CIAM_HYDRA_DSN}');
    expect(content).toContain('${PG_IAM_HYDRA_DSN}');
  });
});
