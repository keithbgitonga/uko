import pg from 'pg';
const client = new pg.Client({ host: '127.0.0.1', port: 55432, user: 'uko', database: 'postgres' });
await client.connect();
const res = await client.query("SELECT 1 FROM pg_database WHERE datname='uko'");
if (res.rowCount === 0) {
  await client.query('CREATE DATABASE uko');
  console.log('created database uko');
}
await client.end();
