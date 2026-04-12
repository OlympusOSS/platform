/**
 * platform#9 — Kratos/Hydra secrets verification
 *
 * Verifies that production Kratos/Hydra configs do NOT contain hardcoded
 * dev secrets, and that compose.prod.yml provides env var overrides for
 * every secret. Also checks check-secrets.sh startup shim is in place.
 */
import { test, expect } from '@playwright/test';
import { readFileSync } from 'fs';
import { resolve } from 'path';

const ROOT = resolve(__dirname, '..', '..');

// Known insecure dev placeholders that must NOT appear in prod configs
const INSECURE_PLACEHOLDERS = [
  'PLEASE-CHANGE-ME-I-AM-VERY-INSECURE',
  'ciam-hydra-secret-change-me',
  'iam-hydra-pairwise-salt',
  'iam-kratos-cookie-secret-change-me',
  'iam-kratos-cipher-secret',
  '32-LONG-SECRET-NOT-SECURE-AT-ALL',
];

test.describe('platform#9: Kratos/Hydra secrets verification', () => {
  test('prod CIAM Kratos config has no hardcoded secrets', () => {
    const content = readFileSync(resolve(ROOT, 'prod/ciam-kratos/kratos.yml'), 'utf-8');
    for (const placeholder of INSECURE_PLACEHOLDERS) {
      expect(content).not.toContain(placeholder);
    }
  });

  test('prod IAM Kratos config has no hardcoded secrets', () => {
    const content = readFileSync(resolve(ROOT, 'prod/iam-kratos/kratos.yml'), 'utf-8');
    for (const placeholder of INSECURE_PLACEHOLDERS) {
      expect(content).not.toContain(placeholder);
    }
  });

  test('prod CIAM Kratos config uses env var substitutions for secrets', () => {
    const content = readFileSync(resolve(ROOT, 'prod/ciam-kratos/kratos.yml'), 'utf-8');
    // Prod config should reference env vars via comments, not have inline secrets
    expect(content).not.toMatch(/secrets:\s*\n\s+cookie:\s*\n\s+-\s+\S+/);
  });

  test('prod IAM Kratos config uses env var substitutions for secrets', () => {
    const content = readFileSync(resolve(ROOT, 'prod/iam-kratos/kratos.yml'), 'utf-8');
    expect(content).not.toMatch(/secrets:\s*\n\s+cookie:\s*\n\s+-\s+\S+/);
  });

  test('compose.prod.yml provides SECRETS_COOKIE override for CIAM Kratos', () => {
    const content = readFileSync(resolve(ROOT, 'prod/compose.prod.yml'), 'utf-8');
    expect(content).toContain('SECRETS_COOKIE=${CIAM_KRATOS_SECRET_COOKIE}');
  });

  test('compose.prod.yml provides SECRETS_CIPHER override for CIAM Kratos', () => {
    const content = readFileSync(resolve(ROOT, 'prod/compose.prod.yml'), 'utf-8');
    expect(content).toContain('SECRETS_CIPHER=${CIAM_KRATOS_SECRET_CIPHER}');
  });

  test('compose.prod.yml provides SECRETS_COOKIE override for IAM Kratos', () => {
    const content = readFileSync(resolve(ROOT, 'prod/compose.prod.yml'), 'utf-8');
    expect(content).toContain('SECRETS_COOKIE=${IAM_KRATOS_SECRET_COOKIE}');
  });

  test('compose.prod.yml provides SECRETS_SYSTEM override for CIAM Hydra', () => {
    const content = readFileSync(resolve(ROOT, 'prod/compose.prod.yml'), 'utf-8');
    expect(content).toContain('SECRETS_SYSTEM=${CIAM_HYDRA_SECRET_SYSTEM}');
  });

  test('compose.prod.yml provides SECRETS_SYSTEM override for IAM Hydra', () => {
    const content = readFileSync(resolve(ROOT, 'prod/compose.prod.yml'), 'utf-8');
    expect(content).toContain('SECRETS_SYSTEM=${IAM_HYDRA_SECRET_SYSTEM}');
  });

  test('check-secrets.sh startup shim is used for all Kratos/Hydra services', () => {
    const content = readFileSync(resolve(ROOT, 'prod/compose.prod.yml'), 'utf-8');
    // All 4 main services and 4 migrate services should use check-secrets.sh
    const shimMatches = content.match(/check-secrets\.sh/g);
    expect(shimMatches).not.toBeNull();
    expect(shimMatches!.length).toBeGreaterThanOrEqual(8);
  });

  test('check-secrets.sh exists and is executable logic', () => {
    const content = readFileSync(resolve(ROOT, 'prod/check-secrets.sh'), 'utf-8');
    expect(content.length).toBeGreaterThan(0);
    // Should check for empty env vars
    expect(content).toMatch(/(-z|empty|unset)/i);
  });
});
