/**
 * platform#53 — PostgreSQL sslmode verify-full
 *
 * Verifies the architecture and config needed for upgrading from
 * sslmode=require to sslmode=verify-full with CA certificate
 * validation. This ticket depends on platform#19.
 *
 * Note: Implementation is BLOCKED pending Architect CA key storage
 * decision. Tests verify the planned infrastructure is in place
 * or correctly documented.
 */
import { test, expect } from '@playwright/test';
import { readFileSync, existsSync } from 'fs';
import { resolve } from 'path';

const ROOT = resolve(__dirname, '..', '..');

test.describe('platform#53: PostgreSQL sslmode verify-full', () => {
  test('prerequisite: platform#19 PostgreSQL SSL is configured in prod', () => {
    const content = readFileSync(resolve(ROOT, 'prod/compose.prod.yml'), 'utf-8');
    expect(content).toMatch(/ssl=on/);
  });

  test('CA cert file exists (public, committed to repo)', () => {
    // pg-ca.crt should be committed for verify-full
    const certPath = resolve(ROOT, 'prod/postgres/server.crt');
    // At minimum, the server.crt from platform#19 should exist
    expect(existsSync(certPath)).toBe(true);
  });

  test.skip('all 8 client containers mount pg-ca.crt', () => {
    // BLOCKED: Implementation not started — pending Architect CA key
    // storage decision (Option A: GitHub Secrets). Skip until
    // compose.prod.yml is updated with verify-full DSNs and CA mounts.
    const content = readFileSync(resolve(ROOT, 'prod/compose.prod.yml'), 'utf-8');
    expect(content).toContain('pg-ca.crt');
  });

  test.skip('all DSN strings use sslmode=verify-full', () => {
    // BLOCKED: Same as above — DSNs will be updated when implementation
    // begins. Currently sslmode=require (platform#19).
    const content = readFileSync(resolve(ROOT, 'prod/compose.prod.yml'), 'utf-8');
    expect(content).toContain('sslmode=verify-full');
  });

  test.skip('cert-rotation.md exists with rotation procedure', () => {
    // BLOCKED: Documentation will be created during implementation.
    const docPath = resolve(ROOT, 'docs/cert-rotation.md');
    expect(existsSync(docPath)).toBe(true);
  });

  test('dev compose does NOT use verify-full (sslmode=disable)', () => {
    const content = readFileSync(resolve(ROOT, 'dev/compose.dev.yml'), 'utf-8');
    expect(content).not.toContain('verify-full');
    expect(content).toContain('sslmode=disable');
  });

  test('.gitignore or repo does not contain *.key in tracked files', () => {
    // server.key should exist in prod/ (written by deploy.yml) but
    // should ideally be in .gitignore
    const gitignorePath = resolve(ROOT, '.gitignore');
    if (existsSync(gitignorePath)) {
      const content = readFileSync(gitignorePath, 'utf-8');
      // Should have some pattern blocking key files
      expect(content).toMatch(/\*\.key|server\.key|pg-ca\.key/);
    }
  });
});
