-- Driver onboarding documents (licence, insurance, vehicle photo) with ops review.
CREATE TABLE IF NOT EXISTS driver_documents (
  id text PRIMARY KEY,
  driver_id uuid NOT NULL,
  type text NOT NULL,
  status text NOT NULL DEFAULT 'PENDING',
  document_number text,
  expires_at text,
  file_name text,
  file_path text,
  file_size int,
  mime_type text,
  reviewed_by uuid,
  reviewed_at timestamptz,
  rejection_reason text,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS driver_documents_driver_idx ON driver_documents (driver_id, created_at DESC);
CREATE INDEX IF NOT EXISTS driver_documents_status_idx ON driver_documents (status, created_at DESC);
