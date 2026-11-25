-- Rider ratings for completed rides.
CREATE TABLE IF NOT EXISTS ride_ratings (
  id text PRIMARY KEY,
  ride_id text NOT NULL UNIQUE,
  rider_id uuid NOT NULL,
  driver_id uuid,
  rating int NOT NULL CHECK (rating BETWEEN 1 AND 5),
  comment text,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS ride_ratings_driver_idx ON ride_ratings (driver_id, created_at DESC);
