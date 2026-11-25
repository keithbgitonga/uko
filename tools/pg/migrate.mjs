#!/usr/bin/env node
// Applies SQL migrations in order, tracking them in schema_migrations.
// Usage: node migrate.mjs [file ...]   (default: ../../db/migrations/0001_core.sql)
import fs from 'node:fs/promises';
import path from 'node:path';
import pg from 'pg';

const here = path.dirname(new URL(import.meta.url).pathname);
const client = new pg.Client(
  process.env.DATABASE_URL
    ? { connectionString: process.env.DATABASE_URL }
    : { host: '127.0.0.1', port: 55432, user: 'uko', database: 'uko' },
);
await client.connect();
await client.query(`CREATE TABLE IF NOT EXISTS schema_migrations (
  filename text PRIMARY KEY,
  applied_at timestamptz NOT NULL DEFAULT now()
)`);

const files = process.argv.length > 2
  ? process.argv.slice(2)
  : [path.resolve(here, '../../app/db/migrations/0001_core.sql')];
for (const file of files) {
  const name = path.basename(file);
  const exists = await client.query('SELECT 1 FROM schema_migrations WHERE filename = $1', [name]);
  if (exists.rowCount > 0) {
    console.log(`skip ${name} (already applied)`);
    continue;
  }
  const sql = await fs.readFile(file, 'utf-8');
  console.log(`applying ${name}`);
  await client.query('BEGIN');
  try {
    await client.query(sql);
    await client.query('INSERT INTO schema_migrations (filename) VALUES ($1)', [name]);
    await client.query('COMMIT');
  } catch (err) {
    await client.query('ROLLBACK');
    console.error(`failed ${name}:`, err.message);
    process.exit(1);
  }
}
const tables = await client.query("SELECT tablename FROM pg_tables WHERE schemaname='public' ORDER BY tablename");
console.log('tables:', tables.rows.map((r) => r.tablename).join(', '));
await client.end();
