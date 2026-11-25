#!/usr/bin/env node
// Applies the SQL migrations in order, recording them in schema_migrations.
// Used by the production deployment (migrate service) and by ops.
import fs from 'node:fs/promises';
import path from 'node:path';
import pg from 'pg';

const connectionString = process.env.DATABASE_URL;
if (!connectionString) {
  console.error('DATABASE_URL is required');
  process.exit(1);
}
const migrationsDir = process.env.MIGRATIONS_DIR || path.resolve(process.cwd(), 'migrations');
const files = (await fs.readdir(migrationsDir)).filter((f) => f.endsWith('.sql')).sort();

const ssl = process.env.DATABASE_SSL === 'true' || connectionString.includes('sslmode=require') ? { rejectUnauthorized: false } : undefined;
const client = new pg.Client({ connectionString, ssl });
await client.connect();
await client.query(`CREATE TABLE IF NOT EXISTS schema_migrations (
  filename text PRIMARY KEY,
  applied_at timestamptz NOT NULL DEFAULT now()
)`);
const applied = new Set((await client.query('SELECT filename FROM schema_migrations')).rows.map((r) => r.filename));

let appliedCount = 0;
let skippedCount = 0;
for (const file of files) {
  if (applied.has(file)) {
    skippedCount += 1;
    continue;
  }
  if (file.startsWith('0002') && process.env.SKIP_POSTGIS === '1') {
    console.log(`skipped ${file} (SKIP_POSTGIS=1)`);
    continue;
  }
  const sql = await fs.readFile(path.join(migrationsDir, file), 'utf-8');
  try {
    await client.query('BEGIN');
    await client.query(sql);
    await client.query('INSERT INTO schema_migrations (filename) VALUES ($1)', [file]);
    await client.query('COMMIT');
    console.log(`applied ${file}`);
    appliedCount += 1;
  } catch (err) {
    await client.query('ROLLBACK').catch(() => undefined);
    console.error(`failed ${file}: ${err instanceof Error ? err.message : err}`);
    await client.end();
    process.exit(1);
  }
}
await client.end();
console.log(`migrations complete: applied=${appliedCount} skipped=${skippedCount}`);
