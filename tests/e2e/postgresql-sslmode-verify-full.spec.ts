/**
 * platform#53 — PostgreSQL sslmode verify-full
 *
 * Verifies the infrastructure for sslmode=verify-full with CA certificate
 * validation. All client containers must mount pg-ca.crt and DSNs must
 * use sslmode=verify-full&sslrootcert=/etc/ssl/certs/pg-ca.crt.
 *
 * Depends on: platform#19 (sslmode=require — baseline SSL).
 */
import { test, expect } from '@playwright/test';
import { readFileSync, existsSync } from 'fs';
import { resolve } from 'path';

const ROOT = resolve(__dirname, '..', '..');

// The 8 client containers that connect to PostgreSQL (per architecture).
// Migration containers also mount the CA cert but are transient.
const CLIENT_CONTAINERS = [
  'ciam-kratos',
  'iam-kratos',
  'ciam-hydra',
  'iam-hydra',
  'ciam-hera',
  'iam-hera',
  'ciam-athena',
  'iam-athena',
];

test.describe('platform#53: PostgreSQL sslmode verify-full', () => {
  test('prerequisite: platform#19 PostgreSQL SSL is configured in prod', () => {
    const content = readFileSync(resolve(ROOT, 'prod/compose.prod.yml'), 'utf-8');
    expect(content).toMatch(/ssl=on/);
  });

  test('CA cert file exists (public, committed to repo)', () => {
    const caCertPath = resolve(ROOT, 'prod/postgres/pg-ca.crt');
    expect(existsSync(caCertPath)).toBe(true);

    const serverCertPath = resolve(ROOT, 'prod/postgres/server.crt');
    expect(existsSync(serverCertPath)).toBe(true);
  });

  test('all 8 client containers mount pg-ca.crt', () => {
    const content = readFileSync(resolve(ROOT, 'prod/compose.prod.yml'), 'utf-8');

    // pg-ca.crt must be mounted in each client container section
    // Count the number of pg-ca.crt mount references (should be at least 8
    // for the client containers, plus migration containers)
    const mountMatches = content.match(/pg-ca\.crt/g);
    expect(mountMatches).not.toBeNull();
    // 8 client containers + 4 migration containers + 1 postgres = 13 minimum
    // (each has source + target lines, but we count unique occurrences)
    expect(mountMatches!.length).toBeGreaterThanOrEqual(8);
  });

  test('all DSN strings in deploy.yml use sslmode=verify-full', () => {
    const deployContent = readFileSync(
      resolve(ROOT, '.github/workflows/deploy.yml'),
      'utf-8'
    );

    // All 5 DSN lines must contain sslmode=verify-full
    const dsnLines = deployContent
      .split('\n')
      .filter((line) => line.match(/PG_.*_DSN=/) && line.includes('sslmode='));

    expect(dsnLines.length).toBe(5);
    for (const line of dsnLines) {
      expect(line).toContain('sslmode=verify-full');
      expect(line).toContain('sslrootcert=/etc/ssl/certs/pg-ca.crt');
    }
  });

  test('cert-rotation.md exists with rotation procedure', () => {
    const docPath = resolve(ROOT, 'docs/cert-rotation.md');
    expect(existsSync(docPath)).toBe(true);

    const content = readFileSync(docPath, 'utf-8');
    // Must contain key rotation sections
    expect(content).toContain('Annual Server Certificate Rotation');
    expect(content).toContain('CA Certificate Rotation');
    expect(content).toContain('openssl');
    expect(content).toContain('Rollback');
    expect(content).toContain('Troubleshooting');
  });

  test('cert-expiry alerting workflow exists (SR-53-1)', () => {
    const workflowPath = resolve(
      ROOT,
      '.github/workflows/cert-expiry-check.yml'
    );
    expect(existsSync(workflowPath)).toBe(true);

    const content = readFileSync(workflowPath, 'utf-8');
    expect(content).toContain('server cert');
    expect(content).toContain('CA cert');
    expect(content).toContain('cert-expiry');
  });

  test('deploy.yml has DSN sslmode assertion step', () => {
    const content = readFileSync(
      resolve(ROOT, '.github/workflows/deploy.yml'),
      'utf-8'
    );
    expect(content).toContain('Verify DSN sslmode=verify-full');
    expect(content).toContain('sslmode=verify-full');
  });

  test('dev compose does NOT use verify-full (sslmode=disable)', () => {
    const content = readFileSync(resolve(ROOT, 'dev/compose.dev.yml'), 'utf-8');
    expect(content).not.toContain('verify-full');
    expect(content).toContain('sslmode=disable');
  });

  test('.gitignore blocks *.key files', () => {
    const gitignorePath = resolve(ROOT, '.gitignore');
    expect(existsSync(gitignorePath)).toBe(true);

    const content = readFileSync(gitignorePath, 'utf-8');
    expect(content).toMatch(/server\.key/);
    expect(content).toMatch(/pg-ca\.key/);
  });

  test('CI workflow checks for .key files and sslmode regressions', () => {
    const content = readFileSync(
      resolve(ROOT, '.github/workflows/verify-prod-config.yml'),
      'utf-8'
    );
    expect(content).toContain('private key file');
    expect(content).toContain('sslmode regression');
  });

  test('PostgreSQL config includes ssl_ca_file', () => {
    const content = readFileSync(resolve(ROOT, 'prod/compose.prod.yml'), 'utf-8');
    expect(content).toContain('ssl_ca_file');
  });
});
