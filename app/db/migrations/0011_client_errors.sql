-- Client crash/error reports from the rider and driver apps.
CREATE TABLE IF NOT EXISTS client_errors (
  id text PRIMARY KEY,
  user_id uuid,
  app text NOT NULL,
  version text,
  platform text,
  message text NOT NULL,
  stack text,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS client_errors_created_idx ON client_errors (created_at DESC);
