#!/usr/bin/env node
// Logical JSON backup of every public table, with counts and a content hash.
import fs from 'node:fs/promises';
import path from 'node:path';
import crypto from 'node:crypto';
import pg from 'pg';

const databaseUrl = process.env.DATABASE_URL || 'postgres://uko@127.0.0.1:55432/uko';
const client = new pg.Client({ connectionString: databaseUrl });
await client.connect();
const tables = (await client.query(
  `SELECT tablename FROM pg_tables WHERE schemaname='public' ORDER BY tablename`,
)).rows.map((r) => r.tablename);

const data = {};
for (const table of tables) {
  const rows = (await client.query(`SELECT * FROM "${table}"`)).rows;
  data[table] = rows;
}
await client.end();

const payload = { createdAt: new Date().toISOString(), database: databaseUrl.replace(/\/\/.*@/, '//'), tables: data };
const json = JSON.stringify(payload, null, 2);
const hash = crypto.createHash('sha256').update(json).digest('hex');
const dir = path.resolve(path.dirname(new URL(import.meta.url).pathname), 'backups');
await fs.mkdir(dir, { recursive: true });
const stamp = new Date().toISOString().replace(/[:.]/g, '-');
const file = path.join(dir, `uko-backup-${stamp}.json`);
await fs.writeFile(file, json);
const counts = Object.fromEntries(Object.entries(data).map(([t, rows]) => [t, rows.length]));
await fs.writeFile(file.replace(/\.json$/, '.manifest.json'), JSON.stringify({ file, hash, createdAt: payload.createdAt, counts }, null, 2));
console.log(`backup written: ${file}`);
console.log(`tables=${tables.length} rows=${Object.values(counts).reduce((a, b) => a + b, 0)} sha256=${hash.slice(0, 16)}…`);
