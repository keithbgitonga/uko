-- Driver online shift sessions (used for shift summary / online time).
CREATE TABLE IF NOT EXISTS driver_shifts (
  id text PRIMARY KEY,
  driver_id uuid NOT NULL,
  started_at timestamptz NOT NULL,
  ended_at timestamptz,
  online boolean NOT NULL DEFAULT true
);
CREATE INDEX IF NOT EXISTS driver_shifts_driver_idx ON driver_shifts (driver_id, started_at DESC);
