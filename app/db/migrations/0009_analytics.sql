-- Lightweight product analytics events for the pilot dashboard.
CREATE TABLE IF NOT EXISTS analytics_events (
  id text PRIMARY KEY,
  user_id uuid,
  event text NOT NULL,
  props jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS analytics_events_event_idx ON analytics_events (event, created_at DESC);
