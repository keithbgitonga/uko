-- Nairobi pilot zone + Boda pricing seed.
INSERT INTO zones (id, name, city, currency, boundary, active)
VALUES (
  '00000000-0000-0000-0000-000000000001',
  'Nairobi pilot zone',
  'Nairobi',
  'KES',
  ST_GeomFromText('MULTIPOLYGON(((
    36.70 -1.36, 36.95 -1.36, 36.95 -1.20, 36.70 -1.20, 36.70 -1.36
  )))', 4326),
  true
)
ON CONFLICT (id) DO NOTHING;

INSERT INTO pricing_rules (zone_id, category, base_fare, per_km, per_minute, minimum_fare,
                           cancellation_fee, commission_percent, surge_enabled, active)
VALUES ('00000000-0000-0000-0000-000000000001', 'boda', 50, 25, 3, 80, 0, 20, false, true)
ON CONFLICT (zone_id, category) DO UPDATE
SET base_fare = EXCLUDED.base_fare,
    per_km = EXCLUDED.per_km,
    per_minute = EXCLUDED.per_minute,
    minimum_fare = EXCLUDED.minimum_fare,
    cancellation_fee = EXCLUDED.cancellation_fee,
    commission_percent = EXCLUDED.commission_percent,
    surge_enabled = EXCLUDED.surge_enabled,
    active = EXCLUDED.active;
