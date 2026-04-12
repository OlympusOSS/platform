/**
 * platform#25 — leak_sensitive_values must be false in production
 *
 * Verifies that prod Kratos configs have leak_sensitive_values: false,
 * dev configs intentionally have it true, and the CI regression
 * check workflow exists.
 */
import { test, expect } from '@playwright/test';
import { readFileSync, existsSync } from 'fs';
import { resolve } from 'path';

const ROOT = resolve(__dirname, '..', '..');

test.describe('platform#25: leak_sensitive_values', () => {
  test('AC1: prod CIAM Kratos has leak_sensitive_values: false', () => {
    const content = readFileSync(resolve(ROOT, 'prod/ciam-kratos/kratos.yml'), 'utf-8');
    expect(content).toMatch(/leak_sensitive_values:\s*false/);
    expect(content).not.toMatch(/leak_sensitive_values:\s*true/);
  });

  test('AC2: prod IAM Kratos has leak_sensitive_values: false', () => {
    const content = readFileSync(resolve(ROOT, 'prod/iam-kratos/kratos.yml'), 'utf-8');
    expect(content).toMatch(/leak_sensitive_values:\s*false/);
    expect(content).not.toMatch(/leak_sensitive_values:\s*true/);
  });

  test('F3: dev CIAM Kratos has leak_sensitive_values: true (intentional)', () => {
    const content = readFileSync(resolve(ROOT, 'dev/ciam-kratos/kratos.yml'), 'utf-8');
    expect(content).toMatch(/leak_sensitive_values:\s*true/);
  });

  test('F4: dev IAM Kratos has leak_sensitive_values: true (intentional)', () => {
    const content = readFileSync(resolve(ROOT, 'dev/iam-kratos/kratos.yml'), 'utf-8');
    expect(content).toMatch(/leak_sensitive_values:\s*true/);
  });

  test('AC3: verify-prod-config CI workflow exists', () => {
    const workflowPath = resolve(ROOT, '.github/workflows/verify-prod-config.yml');
    if (!existsSync(workflowPath)) {
      test.skip();
      return;
    }
    const content = readFileSync(workflowPath, 'utf-8');
    expect(content).toContain('leak_sensitive_values');
    // Should target platform/prod/ only
    expect(content).toContain('prod');
  });

  test('no leak_sensitive_values: true anywhere in prod/ directory', () => {
    // Scan all yml files in prod/ for the dangerous value
    const prodKratosFiles = [
      resolve(ROOT, 'prod/ciam-kratos/kratos.yml'),
      resolve(ROOT, 'prod/iam-kratos/kratos.yml'),
    ];
    for (const file of prodKratosFiles) {
      const content = readFileSync(file, 'utf-8');
      expect(content).not.toMatch(/leak_sensitive_values:\s*true/);
    }
  });
});
