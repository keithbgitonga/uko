#!/usr/bin/env node
// Restores a backup JSON into a fresh database, applying the schema first,
// then verifies row counts against the backup manifest.
import fs from 'node:fs/promises';
import path from 'node:path';
import pg from 'pg';

const file = process.argv[2];
if (!file) {
  console.error('usage: node restore.mjs <backup.json> [target-database]');
  process.exit(1);
}
const targetDb = process.argv[3] || 'uko_restore';
const baseUrl = new URL(process.env.DATABASE_URL || 'postgres://uko@127.0.0.1:55432/uko');
const admin = new pg.Client({ connectionString: baseUrl.toString() });
await admin.connect();
const exists = await admin.query('SELECT 1 FROM pg_database WHERE datname=$1', [targetDb]);
if (exists.rowCount === 0) await admin.query(`CREATE DATABASE "${targetDb}"`);
await admin.end();

const targetUrl = new URL(baseUrl.toString());
targetUrl.pathname = `/${targetDb}`;
const client = new pg.Client({ connectionString: targetUrl.toString() });
await client.connect();
const backup = JSON.parse(await fs.readFile(file, 'utf-8'));

const here = path.dirname(new URL(import.meta.url).pathname);
const migrationDir = path.resolve(here, '../../app/db/migrations');
const migrations = [
  '0001_core.sql', '0003_domain_documents.sql', '0004_normalized_domains.sql',
  '0005_driver_shifts.sql', '0006_audit_log.sql', '0007_notifications.sql',
  '0008_ride_ratings.sql', '0009_analytics.sql', '0010_driver_documents.sql',
  '0011_client_errors.sql', '0012_document_expiry.sql', '0013_scheduled_activation.sql',
];
for (const migration of migrations) {
  const sql = await fs.readFile(path.join(migrationDir, migration), 'utf-8');
  await client.query(sql);
  console.log(`schema: ${migration}`);
}

const columnTypes = new Map();
const typeRows = await client.query(
  `SELECT table_name, column_name, udt_name FROM information_schema.columns WHERE table_schema='public'`,
);
for (const row of typeRows.rows) {
  columnTypes.set(`${row.table_name}.${row.column_name}`, row.udt_name);
}

await client.query('SET session_replication_role = replica');
let inserted = 0;
for (const [table, rows] of Object.entries(backup.tables)) {
  if (table === 'schema_migrations') continue;
  for (const row of rows) {
    const cols = Object.keys(row);
    if (cols.length === 0) continue;
    const placeholders = cols.map((_, i) => `$${i + 1}`).join(',');
    await client.query(
      `INSERT INTO "${table}" (${cols.map((c) => `"${c}"`).join(',')}) VALUES (${placeholders}) ON CONFLICT DO NOTHING`,
      cols.map((c) => {
        const type = columnTypes.get(`${table}.${c}`);
        const value = row[c];
        if (value !== null && (type === 'json' || type === 'jsonb')) return JSON.stringify(value);
        return value;
      }),
    );
    inserted += 1;
  }
}
await client.query('SET session_replication_role = origin');

let ok = true;
for (const [table, rows] of Object.entries(backup.tables)) {
  if (table === 'schema_migrations') continue;
  const count = (await client.query(`SELECT count(*)::int AS n FROM "${table}"`)).rows[0].n;
  const expected = rows.length;
  if (count !== expected) {
    ok = false;
    console.error(`MISMATCH ${table}: restored=${count} expected=${expected}`);
  }
}
await client.end();
console.log(`restored ${inserted} rows into ${targetDb}; verification ${ok ? 'PASSED' : 'FAILED'}`);
process.exit(ok ? 0 : 1);
