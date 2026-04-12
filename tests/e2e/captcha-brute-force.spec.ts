/**
 * platform#17 — CAPTCHA/brute-force protection
 *
 * Verifies that production compose defaults CAPTCHA to enabled,
 * HaveIBeenPwned is enabled in prod Kratos configs, and dev
 * compose retains CAPTCHA disabled.
 */
import { test, expect } from '@playwright/test';
import { readFileSync } from 'fs';
import { resolve } from 'path';

const ROOT = resolve(__dirname, '..', '..');

test.describe('platform#17: CAPTCHA/brute-force protection', () => {
  test('AC1: compose.prod.yml defaults CIAM CAPTCHA_ENABLED to true', () => {
    const content = readFileSync(resolve(ROOT, 'prod/compose.prod.yml'), 'utf-8');
    expect(content).toContain('CAPTCHA_ENABLED=${CIAM_CAPTCHA_ENABLED:-true}');
  });

  test('AC1: compose.prod.yml defaults IAM CAPTCHA_ENABLED to true', () => {
    const content = readFileSync(resolve(ROOT, 'prod/compose.prod.yml'), 'utf-8');
    expect(content).toContain('CAPTCHA_ENABLED=${IAM_CAPTCHA_ENABLED:-true}');
  });

  test('AC2: prod CIAM Kratos has haveibeenpwned_enabled: true', () => {
    const content = readFileSync(resolve(ROOT, 'prod/ciam-kratos/kratos.yml'), 'utf-8');
    expect(content).toMatch(/haveibeenpwned_enabled:\s*true/);
  });

  test('AC2: prod IAM Kratos has haveibeenpwned_enabled: true', () => {
    const content = readFileSync(resolve(ROOT, 'prod/iam-kratos/kratos.yml'), 'utf-8');
    expect(content).toMatch(/haveibeenpwned_enabled:\s*true/);
  });

  test('AC4: dev compose.dev.yml keeps CAPTCHA_ENABLED=false for CIAM Hera', () => {
    const content = readFileSync(resolve(ROOT, 'dev/compose.dev.yml'), 'utf-8');
    // Should find CAPTCHA_ENABLED=false in ciam-hera and iam-hera sections
    const matches = content.match(/CAPTCHA_ENABLED=false/g);
    expect(matches).not.toBeNull();
    expect(matches!.length).toBeGreaterThanOrEqual(2);
  });

  test('dev CIAM Kratos has haveibeenpwned_enabled: false (intentional for dev)', () => {
    const content = readFileSync(resolve(ROOT, 'dev/ciam-kratos/kratos.yml'), 'utf-8');
    expect(content).toMatch(/haveibeenpwned_enabled:\s*false/);
  });

  test('prod compose does not set ALLOW_DEMO_ACCOUNTS to true', () => {
    const content = readFileSync(resolve(ROOT, 'prod/compose.prod.yml'), 'utf-8');
    expect(content).toContain('ALLOW_DEMO_ACCOUNTS=${ALLOW_DEMO_ACCOUNTS:-false}');
    expect(content).not.toMatch(/ALLOW_DEMO_ACCOUNTS=true/);
  });

  test('Caddy rate limiting is configured on CIAM login routes', () => {
    const content = readFileSync(resolve(ROOT, 'prod/Caddyfile'), 'utf-8');
    expect(content).toContain('rate_limit');
    expect(content).toMatch(/zone\s+login_limit/);
    expect(content).toMatch(/path\s+\/login/);
    expect(content).toMatch(/method\s+POST/);
  });
});
