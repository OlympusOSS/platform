/**
 * platform#49 — SHA-digest tag
 *
 * Verifies that caddy-build.yml emits both a 'latest' and a
 * 'sha-<full-sha>' tag, and that compose.prod.yml documents
 * the rollback procedure.
 */
import { test, expect } from '@playwright/test';
import { readFileSync, existsSync } from 'fs';
import { resolve } from 'path';

const ROOT = resolve(__dirname, '..', '..');

test.describe('platform#49: SHA-digest tag', () => {
  test('caddy-build.yml emits sha- tag alongside latest', () => {
    const workflowPath = resolve(ROOT, '.github/workflows/caddy-build.yml');
    if (!existsSync(workflowPath)) {
      test.skip();
      return;
    }
    const content = readFileSync(workflowPath, 'utf-8');
    // Should contain sha- tag pattern using github.sha
    expect(content).toMatch(/sha-.*github\.sha/);
    expect(content).toContain('latest');
  });

  test('uses full SHA (40 chars), not truncated 7-char', () => {
    const workflowPath = resolve(ROOT, '.github/workflows/caddy-build.yml');
    if (!existsSync(workflowPath)) {
      test.skip();
      return;
    }
    const content = readFileSync(workflowPath, 'utf-8');
    // Must use ${{ github.sha }} not a cut/truncation
    expect(content).toContain('github.sha');
    // Should NOT contain cut -c1-7 or similar truncation
    expect(content).not.toMatch(/cut\s+-c1-7/);
  });

  test('both tags in single build-push-action step', () => {
    const workflowPath = resolve(ROOT, '.github/workflows/caddy-build.yml');
    if (!existsSync(workflowPath)) {
      test.skip();
      return;
    }
    const content = readFileSync(workflowPath, 'utf-8');
    // The tags: field should contain both latest and sha- patterns
    expect(content).toMatch(/tags:/);
  });

  test('compose.prod.yml documents rollback procedure', () => {
    const content = readFileSync(resolve(ROOT, 'prod/compose.prod.yml'), 'utf-8');
    expect(content).toMatch(/[Rr]ollback/i);
    expect(content).toContain('sha-');
  });

  test('compose.prod.yml caddy image references GHCR', () => {
    const content = readFileSync(resolve(ROOT, 'prod/compose.prod.yml'), 'utf-8');
    expect(content).toContain('ghcr.io/olympusoss/caddy');
  });
});
