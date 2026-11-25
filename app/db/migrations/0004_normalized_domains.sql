-- Normalised tables for domains previously stored as JSONB snapshots.
-- Complex shapes (pickup/dropoff, events, occurrences) stay JSONB; key
-- queryable fields become columns.

CREATE TABLE IF NOT EXISTS quotes (
  id text PRIMARY KEY,
  rider_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  rider_phone text NOT NULL,
  pickup jsonb NOT NULL,
  dropoff jsonb NOT NULL,
  distance_km numeric(8,2) NOT NULL,
  duration_min int NOT NULL,
  fare int NOT NULL,
  breakdown jsonb NOT NULL,
  currency text NOT NULL DEFAULT 'KES',
  expires_at bigint NOT NULL,
  created_at text NOT NULL
);

CREATE TABLE IF NOT EXISTS rides (
  id text PRIMARY KEY,
  rider_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  rider_phone text NOT NULL,
  quote_id text,
  pickup jsonb NOT NULL,
  dropoff jsonb NOT NULL,
  fare int NOT NULL,
  currency text NOT NULL DEFAULT 'KES',
  payment_method text NOT NULL,
  state text NOT NULL,
  driver jsonb,
  driver_trip_id text,
  pickup_code text,
  events jsonb NOT NULL DEFAULT '[]'::jsonb,
  created_at text NOT NULL
);
CREATE INDEX IF NOT EXISTS rides_rider_idx ON rides (rider_id, created_at DESC);
CREATE INDEX IF NOT EXISTS rides_state_idx ON rides (state);

CREATE TABLE IF NOT EXISTS driver_trips (
  id text PRIMARY KEY,
  ride_id text NOT NULL,
  driver_id uuid NOT NULL,
  rider_name text NOT NULL,
  pickup jsonb NOT NULL,
  dropoff jsonb NOT NULL,
  fare int NOT NULL,
  currency text NOT NULL DEFAULT 'KES',
  pickup_code text NOT NULL,
  state text NOT NULL,
  events jsonb NOT NULL DEFAULT '[]'::jsonb,
  created_at text NOT NULL
);
CREATE INDEX IF NOT EXISTS driver_trips_driver_idx ON driver_trips (driver_id, created_at DESC);

CREATE TABLE IF NOT EXISTS driver_availability (
  driver_id uuid PRIMARY KEY,
  online boolean NOT NULL,
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS driver_rejections (
  driver_id uuid NOT NULL,
  ride_id text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (driver_id, ride_id)
);

CREATE TABLE IF NOT EXISTS payments (
  id text PRIMARY KEY,
  ride_id text NOT NULL,
  rider_id uuid NOT NULL,
  amount int NOT NULL,
  currency text NOT NULL DEFAULT 'KES',
  method text NOT NULL,
  status text NOT NULL,
  checkout_request_id text,
  merchant_request_id text,
  customer_message text,
  receipt text,
  created_at bigint NOT NULL,
  updated_at bigint NOT NULL
);
CREATE INDEX IF NOT EXISTS payments_ride_idx ON payments (ride_id);

CREATE TABLE IF NOT EXISTS safety_contacts (
  id text PRIMARY KEY,
  rider_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name text NOT NULL,
  phone text NOT NULL,
  relationship text,
  created_at text NOT NULL
);

CREATE TABLE IF NOT EXISTS safety_incidents (
  id text PRIMARY KEY,
  rider_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  ride_id text,
  type text NOT NULL DEFAULT 'SOS',
  state text NOT NULL,
  lat double precision,
  lng double precision,
  note text,
  contacts jsonb NOT NULL DEFAULT '[]'::jsonb,
  events jsonb NOT NULL DEFAULT '[]'::jsonb,
  created_at text NOT NULL
);

CREATE TABLE IF NOT EXISTS scheduled_rides (
  id text PRIMARY KEY,
  rider_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  rider_phone text NOT NULL,
  pickup jsonb NOT NULL,
  dropoff jsonb NOT NULL,
  scheduled_at text NOT NULL,
  fare int NOT NULL,
  currency text NOT NULL DEFAULT 'KES',
  payment_method text NOT NULL,
  state text NOT NULL,
  series_id text,
  created_at text NOT NULL
);

CREATE TABLE IF NOT EXISTS schedule_series (
  id text PRIMARY KEY,
  rider_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  rider_phone text NOT NULL,
  pickup jsonb NOT NULL,
  dropoff jsonb NOT NULL,
  weekdays int[] NOT NULL,
  time_of_day text NOT NULL,
  start_date date NOT NULL,
  end_date date NOT NULL,
  fare int NOT NULL,
  currency text NOT NULL DEFAULT 'KES',
  payment_method text NOT NULL,
  state text NOT NULL,
  occurrences jsonb NOT NULL DEFAULT '[]'::jsonb,
  created_at text NOT NULL
);

-- Backfill from the JSONB snapshot store.
INSERT INTO quotes SELECT doc->>'id', (doc->>'riderId')::uuid, doc->>'riderPhone', doc->'pickup', doc->'dropoff',
  (doc->>'distanceKm')::numeric, (doc->>'durationMin')::int, (doc->>'fare')::int, doc->'breakdown',
  doc->>'currency', (doc->>'expiresAt')::bigint, doc->>'createdAt'
FROM domain_documents WHERE domain='booking_quote' ON CONFLICT DO NOTHING;

INSERT INTO rides SELECT doc->>'id', (doc->>'riderId')::uuid, doc->>'riderPhone', doc->>'quoteId', doc->'pickup', doc->'dropoff',
  (doc->>'fare')::int, doc->>'currency', doc->>'paymentMethod', doc->>'state', doc->'driver', doc->>'driverTripId',
  doc->>'pickupCode', COALESCE(doc->'events','[]'::jsonb), doc->>'createdAt'
FROM domain_documents WHERE domain='booking_ride' ON CONFLICT DO NOTHING;

INSERT INTO driver_trips SELECT doc->>'id', doc->>'rideId', (doc->>'driverId')::uuid, doc->>'riderName', doc->'pickup', doc->'dropoff',
  (doc->>'fare')::int, doc->>'currency', doc->>'pickupCode', doc->>'state', COALESCE(doc->'events','[]'::jsonb), doc->>'createdAt'
FROM domain_documents WHERE domain='driver_trip' ON CONFLICT DO NOTHING;

INSERT INTO driver_availability SELECT (doc->>'driverId')::uuid, (doc->>'online')::boolean FROM domain_documents
WHERE domain='driver_status' ON CONFLICT (driver_id) DO UPDATE SET online = EXCLUDED.online, updated_at = now();

INSERT INTO driver_rejections SELECT (doc->>'driverId')::uuid, doc->>'rideId' FROM domain_documents
WHERE domain='driver_rejection' ON CONFLICT DO NOTHING;

INSERT INTO payments SELECT doc->>'id', doc->>'rideId', (doc->>'riderId')::uuid, (doc->>'amount')::int, doc->>'currency',
  doc->>'method', doc->>'status', doc->>'checkoutRequestId', doc->>'merchantRequestId', doc->>'customerMessage',
  doc->>'receipt', (doc->>'createdAt')::bigint, (doc->>'updatedAt')::bigint
FROM domain_documents WHERE domain='payment' ON CONFLICT DO NOTHING;

INSERT INTO safety_contacts SELECT doc->>'id', (doc->>'riderId')::uuid, doc->>'name', doc->>'phone', doc->>'relationship', doc->>'createdAt'
FROM domain_documents WHERE domain='safety_contact' ON CONFLICT DO NOTHING;

INSERT INTO safety_incidents SELECT doc->>'id', (doc->>'riderId')::uuid, doc->>'rideId', COALESCE(doc->>'type','SOS'), doc->>'state',
  (doc->>'lat')::double precision, (doc->>'lng')::double precision, doc->>'note',
  COALESCE(doc->'contacts','[]'::jsonb), COALESCE(doc->'events','[]'::jsonb), doc->>'createdAt'
FROM domain_documents WHERE domain='safety_incident' ON CONFLICT DO NOTHING;

INSERT INTO scheduled_rides SELECT doc->>'id', (doc->>'riderId')::uuid, doc->>'riderPhone', doc->'pickup', doc->'dropoff',
  doc->>'scheduledAt', (doc->>'fare')::int, doc->>'currency', doc->>'paymentMethod', doc->>'status', doc->>'seriesId', doc->>'createdAt'
FROM domain_documents WHERE domain='scheduled_ride' ON CONFLICT DO NOTHING;

INSERT INTO schedule_series SELECT doc->>'id', (doc->>'riderId')::uuid, doc->>'riderPhone', doc->'pickup', doc->'dropoff',
  (SELECT array_agg(value::int) FROM jsonb_array_elements_text(doc->'weekdays') value),
  doc->>'timeOfDay', (doc->>'startDate')::date, (doc->>'endDate')::date, (doc->>'fare')::int, doc->>'currency',
  doc->>'paymentMethod', doc->>'status', COALESCE(doc->'occurrences','[]'::jsonb), doc->>'createdAt'
FROM domain_documents WHERE domain='schedule_series' ON CONFLICT DO NOTHING;
