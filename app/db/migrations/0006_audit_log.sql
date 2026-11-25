-- Ops audit trail for dispatch actions.
CREATE TABLE IF NOT EXISTS audit_log (
  id text PRIMARY KEY,
  actor_id uuid,
  actor_phone text,
  action text NOT NULL,
  entity text NOT NULL,
  entity_id text,
  detail jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS audit_log_created_idx ON audit_log (created_at DESC);
