-- These databases are created on first PostgreSQL start only
-- (entrypoint initdb scripts run when the data volume is empty).

CREATE DATABASE ciam_kratos;
CREATE DATABASE ciam_hydra;
CREATE DATABASE iam_kratos;
CREATE DATABASE iam_hydra;
CREATE DATABASE olympus;

-- Application settings tables (one per domain)
\c olympus

CREATE TABLE IF NOT EXISTS ciam_settings (
  key        TEXT PRIMARY KEY,
  value      TEXT NOT NULL,
  encrypted  BOOLEAN NOT NULL DEFAULT FALSE,
  category   TEXT NOT NULL DEFAULT 'general',
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS iam_settings (
  key        TEXT PRIMARY KEY,
  value      TEXT NOT NULL,
  encrypted  BOOLEAN NOT NULL DEFAULT FALSE,
  category   TEXT NOT NULL DEFAULT 'general',
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
