/**
 * platform#47 — Pin caddy-ratelimit version
 *
 * Verifies that the Caddy Containerfile pins the caddy-ratelimit
 * module to a specific tagged version (not unversioned HEAD),
 * includes pin date and upgrade procedure documentation, and
 * records the full commit SHA for supply-chain traceability.
 */
import { test, expect } from '@playwright/test';
import { readFileSync } from 'fs';
import { resolve } from 'path';

const ROOT = resolve(__dirname, '..', '..');

test.describe('platform#47: Pin caddy-ratelimit version', () => {
  test('F1: Containerfile xcaddy command includes @v0.1.0', () => {
    const content = readFileSync(resolve(ROOT, 'caddy/Containerfile'), 'utf-8');
    expect(content).toMatch(/caddy-ratelimit@v\d+\.\d+\.\d+/);
    expect(content).toContain('@v0.1.0');
  });

  test('F2: pin date and upgrade procedure documented in Containerfile', () => {
    const content = readFileSync(resolve(ROOT, 'caddy/Containerfile'), 'utf-8');
    expect(content).toMatch(/[Pp]inned.*\d{4}/);
    expect(content).toMatch(/[Uu]pgrade|[Uu]pdate/);
  });

  test('F3: full commit SHA recorded for supply-chain traceability', () => {
    const content = readFileSync(resolve(ROOT, 'caddy/Containerfile'), 'utf-8');
    // Full SHA is 40 hex chars
    expect(content).toMatch(/12435ecef5dbb1b137eb68002b85d775a9d5cdb2/);
  });

  test('Caddy base image is also pinned (not floating latest)', () => {
    const content = readFileSync(resolve(ROOT, 'caddy/Containerfile'), 'utf-8');
    // Builder and runtime images should be pinned to major version
    expect(content).toContain('caddy:2-builder-alpine');
    expect(content).toContain('caddy:2-alpine');
  });

  test('no unversioned caddy-ratelimit reference', () => {
    const content = readFileSync(resolve(ROOT, 'caddy/Containerfile'), 'utf-8');
    // Should NOT have bare module reference without version
    const lines = content.split('\n');
    for (const line of lines) {
      if (line.includes('caddy-ratelimit') && !line.startsWith('#')) {
        expect(line).toMatch(/@v\d+/);
      }
    }
  });
});
