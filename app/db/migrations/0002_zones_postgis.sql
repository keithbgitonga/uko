-- Zones + pricing (requires PostGIS; production compose image includes it).
CREATE EXTENSION IF NOT EXISTS postgis;

CREATE TABLE zones (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  city text NOT NULL,
  currency text NOT NULL DEFAULT 'KES',
  boundary geometry(MultiPolygon, 4326) NOT NULL,
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX zones_boundary_gist ON zones USING gist(boundary);
CREATE TRIGGER zones_updated_at BEFORE UPDATE ON zones FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TABLE pricing_rules (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  zone_id uuid NOT NULL REFERENCES zones(id) ON DELETE CASCADE,
  category vehicle_category NOT NULL,
  base_fare numeric(10,2) NOT NULL,
  per_km numeric(10,2) NOT NULL,
  per_minute numeric(10,2) NOT NULL,
  minimum_fare numeric(10,2) NOT NULL,
  cancellation_fee numeric(10,2) NOT NULL DEFAULT 0,
  commission_percent numeric(5,2) NOT NULL DEFAULT 20,
  surge_enabled boolean NOT NULL DEFAULT false,
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (zone_id, category)
);
CREATE TRIGGER pricing_rules_updated_at BEFORE UPDATE ON pricing_rules FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- Sprint 2+ tables (bookings, rides, offers, payments, ledger, incidents) are added by later migrations.
