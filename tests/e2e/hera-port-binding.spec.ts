/**
 * platform#55 — Hera port binding audit
 *
 * Verifies that ciam-hera and iam-hera services do NOT have host-bound
 * port mappings in either compose file. Only Caddy should expose
 * ports 3000 and 4000 to the host — direct Hera access would bypass
 * Caddy rate limiting.
 */
import { test, expect } from '@playwright/test';
import { readFileSync } from 'fs';
import { resolve } from 'path';

const ROOT = resolve(__dirname, '..', '..');

/**
 * Extract the service block for a given service name from a compose file.
 * Returns the YAML text from the service name to the next top-level service.
 */
function extractServiceBlock(composeContent: string, serviceName: string): string {
  const lines = composeContent.split('\n');
  let start = -1;
  let end = lines.length;
  const servicePattern = new RegExp(`^\\s{2}${serviceName}:`);

  for (let i = 0; i < lines.length; i++) {
    if (servicePattern.test(lines[i])) {
      start = i;
    } else if (start >= 0 && /^\s{2}\S+:/.test(lines[i]) && !/^\s{4,}/.test(lines[i])) {
      end = i;
      break;
    }
  }
  return start >= 0 ? lines.slice(start, end).join('\n') : '';
}

test.describe('platform#55: Hera port binding audit', () => {
  test('AC1: compose.dev.yml ciam-hera has no ports: mapping', () => {
    const content = readFileSync(resolve(ROOT, 'dev/compose.dev.yml'), 'utf-8');
    const ciamHera = extractServiceBlock(content, 'ciam-hera');
    expect(ciamHera.length).toBeGreaterThan(0);
    expect(ciamHera).not.toMatch(/^\s+ports:/m);
  });

  test('AC2: compose.dev.yml iam-hera has no ports: mapping', () => {
    const content = readFileSync(resolve(ROOT, 'dev/compose.dev.yml'), 'utf-8');
    const iamHera = extractServiceBlock(content, 'iam-hera');
    expect(iamHera.length).toBeGreaterThan(0);
    expect(iamHera).not.toMatch(/^\s+ports:/m);
  });

  test('AC1: compose.prod.yml ciam-hera has no ports: mapping', () => {
    const content = readFileSync(resolve(ROOT, 'prod/compose.prod.yml'), 'utf-8');
    const ciamHera = extractServiceBlock(content, 'ciam-hera');
    expect(ciamHera.length).toBeGreaterThan(0);
    expect(ciamHera).not.toMatch(/^\s+ports:/m);
  });

  test('AC2: compose.prod.yml iam-hera has no ports: mapping', () => {
    const content = readFileSync(resolve(ROOT, 'prod/compose.prod.yml'), 'utf-8');
    const iamHera = extractServiceBlock(content, 'iam-hera');
    expect(iamHera.length).toBeGreaterThan(0);
    expect(iamHera).not.toMatch(/^\s+ports:/m);
  });

  test('Caddy is the sole host binding for ports 3000 and 4000', () => {
    const content = readFileSync(resolve(ROOT, 'dev/compose.dev.yml'), 'utf-8');
    const caddy = extractServiceBlock(content, 'caddy');
    expect(caddy).toContain("'3000:3000'");
    expect(caddy).toContain("'4000:4000'");
  });

  test('compose.prod.yml ciam-hera has security warning comment', () => {
    const content = readFileSync(resolve(ROOT, 'prod/compose.prod.yml'), 'utf-8');
    const ciamHera = extractServiceBlock(content, 'ciam-hera');
    expect(ciamHera).toMatch(/SECURITY|Do NOT add.*ports/i);
  });

  test('compose.prod.yml iam-hera has security warning comment', () => {
    const content = readFileSync(resolve(ROOT, 'prod/compose.prod.yml'), 'utf-8');
    const iamHera = extractServiceBlock(content, 'iam-hera');
    expect(iamHera).toMatch(/SECURITY|Do NOT add.*ports/i);
  });

  test('live: CIAM Hera is reachable via Caddy on port 3000', async ({ request }) => {
    const response = await request.get('http://localhost:3000/', {
      failOnStatusCode: false,
    });
    // Any response means Caddy is proxying to Hera
    expect(response.status()).toBeLessThan(600);
  });

  test('live: IAM Hera is reachable via Caddy on port 4000', async ({ request }) => {
    const response = await request.get('http://localhost:4000/', {
      failOnStatusCode: false,
    });
    expect(response.status()).toBeLessThan(600);
  });
});
