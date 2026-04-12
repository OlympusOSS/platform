/**
 * platform#51 — Proxy-in-front IP extraction documentation
 *
 * Verifies that both prod and dev Caddyfiles contain documentation
 * about the TCP peer address rate limit key limitation, the required
 * change for proxy-in-front topology, and accepted residual risks.
 */
import { test, expect } from '@playwright/test';
import { readFileSync } from 'fs';
import { resolve } from 'path';

const ROOT = resolve(__dirname, '..', '..');

test.describe('platform#51: Proxy-in-front IP extraction', () => {
  test('AC1: prod Caddyfile documents TCP peer address limitation', () => {
    const content = readFileSync(resolve(ROOT, 'prod/Caddyfile'), 'utf-8');
    expect(content).toMatch(/TCP\s+peer\s+address|remote.host|remote\.ip/i);
    expect(content).toMatch(/proxy|load\s*balancer|CDN/i);
  });

  test('AC1: prod Caddyfile documents X-Forwarded-For requirement', () => {
    const content = readFileSync(resolve(ROOT, 'prod/Caddyfile'), 'utf-8');
    expect(content).toContain('X-Forwarded-For');
    expect(content).toContain('trusted_proxies');
  });

  test('AC2: dev Caddyfile contains same documentation', () => {
    const content = readFileSync(resolve(ROOT, 'dev/Caddyfile'), 'utf-8');
    // Dev Caddyfile should also document the proxy limitation
    expect(content).toMatch(/proxy|X-Forwarded-For|trusted_proxies/i);
  });

  test('AC3: distributed brute force is documented as accepted residual risk', () => {
    const content = readFileSync(resolve(ROOT, 'prod/Caddyfile'), 'utf-8');
    expect(content).toMatch(/[Dd]istributed.*brute\s*force|IP\s+rotation|botnet/i);
    expect(content).toMatch(/accepted|residual\s+risk/i);
  });

  test('CIDR scoping warning present (never use 0.0.0.0/0)', () => {
    const content = readFileSync(resolve(ROOT, 'prod/Caddyfile'), 'utf-8');
    expect(content).toContain('0.0.0.0/0');
    expect(content).toMatch(/[Nn]ever|NEVER|spoof/);
  });

  test('caddy validate caveat documented', () => {
    const content = readFileSync(resolve(ROOT, 'prod/Caddyfile'), 'utf-8');
    expect(content).toMatch(/caddy\s+validate|verify.*module.*version/i);
  });
});
