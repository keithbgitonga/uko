-- Snapshot persistence for domains being moved off in-memory stores.
-- A later migration will normalise these documents into relational tables.
CREATE TABLE IF NOT EXISTS domain_documents (
  domain text NOT NULL,
  id text NOT NULL,
  doc jsonb NOT NULL,
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (domain, id)
);
CREATE INDEX IF NOT EXISTS domain_documents_domain_idx ON domain_documents (domain);
