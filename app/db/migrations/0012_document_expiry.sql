ALTER TABLE driver_documents ADD COLUMN IF NOT EXISTS expiry_notified_at timestamptz;
