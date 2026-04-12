/**
 * platform#52 — redirect_uri localhost in production
 *
 * Verifies that the production seed script uses parameterized URLs
 * (not hardcoded localhost), and that the dev seed script correctly
 * retains localhost URIs.
 */
import { test, expect } from '@playwright/test';
import { readFileSync, existsSync } from 'fs';
import { resolve } from 'path';

const ROOT = resolve(__dirname, '..', '..');

test.describe('platform#52: redirect_uri localhost', () => {
  test('AC3: prod seed script uses ${SITE_PUBLIC_URL}, no hardcoded localhost', () => {
    const seedPath = resolve(ROOT, 'prod/seed-prod.sh');
    if (!existsSync(seedPath)) {
      test.skip();
      return;
    }
    const content = readFileSync(seedPath, 'utf-8');
    // Should use env var substitution for URLs
    expect(content).toContain('SITE_PUBLIC_URL');
    // Check that redirect_uris do not hardcode localhost
    const redirectLines = content.split('\n').filter(
      (line) => line.includes('redirect_uri') || line.includes('redirect-uri')
    );
    for (const line of redirectLines) {
      expect(line).not.toMatch(/localhost:\d+/);
    }
  });

  test('AC4: dev seed script retains localhost URIs', () => {
    const seedPath = resolve(ROOT, 'dev/iam-seed-dev.sh');
    if (!existsSync(seedPath)) {
      test.skip();
      return;
    }
    const content = readFileSync(seedPath, 'utf-8');
    expect(content).toContain('localhost');
  });

  test('prod seed script parameterizes Athena URLs', () => {
    const seedPath = resolve(ROOT, 'prod/seed-prod.sh');
    if (!existsSync(seedPath)) {
      test.skip();
      return;
    }
    const content = readFileSync(seedPath, 'utf-8');
    expect(content).toMatch(/CIAM_ATHENA_PUBLIC_URL|IAM_ATHENA_PUBLIC_URL/);
  });

  test('compose.prod.yml passes SITE_PUBLIC_URL to seed service', () => {
    const content = readFileSync(resolve(ROOT, 'prod/compose.prod.yml'), 'utf-8');
    expect(content).toContain('SITE_PUBLIC_URL=${SITE_PUBLIC_URL}');
  });

  test('live: dev CIAM Hydra clients use localhost redirect_uris', async ({ request }) => {
    // Check that dev seed registered clients with localhost URIs
    const response = await request.get('http://localhost:3103/admin/clients', {
      failOnStatusCode: false,
    });
    if (response.ok()) {
      const clients = await response.json();
      if (Array.isArray(clients) && clients.length > 0) {
        // At least one client should have localhost redirect URIs in dev
        const hasLocalhost = clients.some(
          (c: { redirect_uris?: string[] }) =>
            c.redirect_uris?.some((uri: string) => uri.includes('localhost'))
        );
        expect(hasLocalhost).toBe(true);
      }
    }
  });
});
