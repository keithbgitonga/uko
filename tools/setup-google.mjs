#!/usr/bin/env node
// One-command setup for Firebase server credentials and the Google Maps key.
// Usage:
//   node tools/setup-google.mjs firebase /path/to/service-account.json
//   node tools/setup-google.mjs maps <maps-api-key>
//   node tools/setup-google.mjs status
import fs from 'node:fs';
import path from 'node:path';

const root = path.resolve(path.dirname(new URL(import.meta.url).pathname), '..');
const apps = ['rider', 'driver'];

function upsertEnv(file, values) {
  let text = fs.existsSync(file) ? fs.readFileSync(file, 'utf-8') : '';
  for (const [key, value] of Object.entries(values)) {
    const line = `${key}=${value}`;
    const re = new RegExp(`^${key}=.*$`, 'm');
    text = re.test(text) ? text.replace(re, line) : `${text}${text.endsWith('\n') || text === '' ? '' : '\n'}${line}\n`;
  }
  fs.writeFileSync(file, text, { mode: 0o600 });
}

function readEnv(file) {
  const out = {};
  if (!fs.existsSync(file)) return out;
  for (const line of fs.readFileSync(file, 'utf-8').split('\n')) {
    const m = line.match(/^([A-Z0-9_]+)=(.*)$/);
    if (m) out[m[1]] = m[2];
  }
  return out;
}

const [, , command, arg] = process.argv;

if (command === 'firebase') {
  if (!arg) { console.error('usage: node tools/setup-google.mjs firebase /path/to/service-account.json'); process.exit(1); }
  const sa = JSON.parse(fs.readFileSync(arg, 'utf-8'));
  if (!sa.project_id || !sa.client_email || !sa.private_key) {
    console.error('Not a Firebase/Google service-account JSON (need project_id, client_email, private_key)');
    process.exit(1);
  }
  const values = {
    PUSH_PROVIDER: 'fcm',
    FCM_PROJECT_ID: sa.project_id,
    FCM_CLIENT_EMAIL: sa.client_email,
    FCM_PRIVATE_KEY: `"${sa.private_key.replace(/\n/g, '\\n')}"`,
  };
  const deploy = path.join(root, 'app/deploy/.env');
  const bench = path.join(root, 'app/services/api/.env');
  for (const file of [deploy, bench]) {
    fs.mkdirSync(path.dirname(file), { recursive: true });
    upsertEnv(file, values);
    console.log(`updated ${path.relative(root, file)}`);
  }
  console.log(`\nFirebase HTTP v1 configured for project ${sa.project_id}.`);
  console.log('Restart the bench API and trigger a ride; real pushes now go to registered devices.');
  process.exit(0);
}

if (command === 'status') {
  let ok = true;
  for (const app of apps) {
    const gs = path.join(root, 'app/apps', app, 'android/app/google-services.json');
    if (!fs.existsSync(gs)) { console.log(`FAIL ${app}: missing google-services.json`); ok = false; continue; }
    try {
      const j = JSON.parse(fs.readFileSync(gs, 'utf-8'));
      const packages = (j.client || []).map((c) => c.client_info?.android_client_info?.package_name);
      console.log(`ok   ${app}: Firebase project ${j.project_info?.project_id} (${packages.join(', ')})`);
    } catch { console.log(`FAIL ${app}: google-services.json is not valid JSON`); ok = false; }
    console.log(`ok   ${app}: maps use OpenStreetMap (no API key required)`);
  }
  const env = readEnv(path.join(root, 'app/deploy/.env'));
  console.log(`${env.FCM_PROJECT_ID ? 'ok  ' : '----'} FCM service account ${env.FCM_PROJECT_ID ? `configured for ${env.FCM_PROJECT_ID}` : 'missing'}`);
  if (env.FCM_PROJECT_ID && !ok) process.exit(1);
  process.exit(0);
}

console.error('usage: node tools/setup-google.mjs firebase <service-account.json> | status');
process.exit(1);
