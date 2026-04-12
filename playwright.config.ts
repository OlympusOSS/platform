import { defineConfig } from '@playwright/test';

/**
 * Playwright config for platform infrastructure E2E tests.
 *
 * These tests verify Kratos/Hydra configuration, Caddy reverse proxy,
 * PostgreSQL, pgAdmin, and CI/CD pipeline integrity. Most tests are
 * API-level (using Playwright's `request` fixture) — no webServer
 * is needed because the tests target already-running infrastructure
 * services via their dev ports.
 *
 * Run with: npx playwright test
 * Prerequisite: `podman compose up -d` from platform/dev/
 */
export default defineConfig({
  testDir: './tests/e2e',
  timeout: 30_000,
  retries: 0,
  reporter: [['list'], ['html', { open: 'never' }]],
  use: {
    // Base URL for CIAM Kratos public API (dev)
    baseURL: 'http://localhost:3100',
    extraHTTPHeaders: {
      Accept: 'application/json',
    },
  },
  projects: [
    {
      name: 'platform-infra',
      testDir: './tests/e2e',
    },
  ],
});
