/**
 * platform#18 — Missing security headers
 *
 * Verifies Caddy security headers snippet is present and applied
 * to all vhosts, and that the running dev stack returns the
 * expected headers on HTTP responses.
 */
import { test, expect } from '@playwright/test';
import { readFileSync } from 'fs';
import { resolve } from 'path';

const ROOT = resolve(__dirname, '..', '..');

const REQUIRED_HEADERS = [
  { name: 'Strict-Transport-Security', value: 'max-age=31536000; includeSubDomains' },
  { name: 'X-Frame-Options', value: 'DENY' },
  { name: 'X-Content-Type-Options', value: 'nosniff' },
  { name: 'Referrer-Policy', value: 'strict-origin-when-cross-origin' },
  { name: 'Permissions-Policy', value: 'camera=(), microphone=(), geolocation=()' },
];

test.describe('platform#18: Security headers — config verification', () => {
  test('prod Caddyfile contains security_headers snippet', () => {
    const content = readFileSync(resolve(ROOT, 'prod/Caddyfile'), 'utf-8');
    expect(content).toMatch(/\(security_headers\)/);
  });

  test('prod Caddyfile security_headers contains all required headers', () => {
    const content = readFileSync(resolve(ROOT, 'prod/Caddyfile'), 'utf-8');
    for (const h of REQUIRED_HEADERS) {
      expect(content).toContain(h.name);
    }
  });

  test('HSTS max-age is 31536000 with includeSubDomains', () => {
    const content = readFileSync(resolve(ROOT, 'prod/Caddyfile'), 'utf-8');
    expect(content).toContain('max-age=31536000; includeSubDomains');
  });

  test('X-Frame-Options is DENY (not SAMEORIGIN)', () => {
    const content = readFileSync(resolve(ROOT, 'prod/Caddyfile'), 'utf-8');
    expect(content).toMatch(/X-Frame-Options\s+"DENY"/);
  });

  test('all prod app vhosts import security_headers', () => {
    const content = readFileSync(resolve(ROOT, 'prod/Caddyfile'), 'utf-8');
    // Count import security_headers occurrences (Site, CIAM Hera, CIAM Hydra,
    // CIAM Athena, IAM Hera, IAM Hydra, IAM Athena, pgAdmin = 8)
    const matches = content.match(/import security_headers/g);
    expect(matches).not.toBeNull();
    expect(matches!.length).toBeGreaterThanOrEqual(8);
  });

  test('dev Caddyfile also includes security headers (parity)', () => {
    const content = readFileSync(resolve(ROOT, 'dev/Caddyfile'), 'utf-8');
    expect(content).toMatch(/security_headers|X-Frame-Options|X-Content-Type-Options/);
  });
});

test.describe('platform#18: Security headers — live verification', () => {
  // These tests require the dev stack to be running (podman compose up -d)

  test('CIAM Hera (port 3000) returns security headers', async ({ request }) => {
    const response = await request.get('http://localhost:3000/', {
      failOnStatusCode: false,
    });
    const headers = response.headers();
    expect(headers['x-content-type-options']).toBe('nosniff');
    expect(headers['x-frame-options']).toBe('DENY');
    expect(headers['referrer-policy']).toBe('strict-origin-when-cross-origin');
  });

  test('CIAM Athena (port 3001) returns security headers', async ({ request }) => {
    const response = await request.get('http://localhost:3001/', {
      failOnStatusCode: false,
    });
    const headers = response.headers();
    expect(headers['x-content-type-options']).toBe('nosniff');
    expect(headers['x-frame-options']).toBe('DENY');
  });

  test('IAM Hera (port 4000) returns security headers', async ({ request }) => {
    const response = await request.get('http://localhost:4000/', {
      failOnStatusCode: false,
    });
    const headers = response.headers();
    expect(headers['x-content-type-options']).toBe('nosniff');
    expect(headers['x-frame-options']).toBe('DENY');
  });

  test('Site (port 2000) returns security headers', async ({ request }) => {
    const response = await request.get('http://localhost:2000/', {
      failOnStatusCode: false,
    });
    const headers = response.headers();
    expect(headers['x-content-type-options']).toBe('nosniff');
    expect(headers['x-frame-options']).toBe('DENY');
  });

  test('CIAM Hydra public (port 3102) returns security headers', async ({ request }) => {
    const response = await request.get('http://localhost:3102/.well-known/openid-configuration', {
      failOnStatusCode: false,
    });
    const headers = response.headers();
    expect(headers['x-content-type-options']).toBe('nosniff');
  });

  test('each header appears exactly once per response (no duplicates)', async ({ request }) => {
    const response = await request.get('http://localhost:3000/', {
      failOnStatusCode: false,
    });
    // Playwright merges duplicate headers with comma — check for comma in
    // single-value headers to detect duplication
    const xfo = response.headers()['x-frame-options'];
    if (xfo) {
      expect(xfo).not.toContain(',');
    }
    const xcto = response.headers()['x-content-type-options'];
    if (xcto) {
      expect(xcto).not.toContain(',');
    }
  });
});
