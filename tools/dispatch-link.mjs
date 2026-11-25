#!/usr/bin/env node
// Generate a ready-to-open dispatch console URL with a fresh access token.
// Usage: API_BASE=https://.../v1 DISPATCH_WEB=https://.../ node tools/dispatch-link.mjs +254712345678
const api = (process.env.API_BASE || 'http://localhost:3100/v1').replace(/\/$/, '');
const web = (process.env.DISPATCH_WEB || 'http://localhost:8085').replace(/\/$/, '');
const phone = process.argv[2] || process.env.DISPATCH_PHONE || '+254712345678';

async function post(path, body) {
  const res = await fetch(`${api}${path}`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(body) });
  const json = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(`${path} ${res.status}: ${JSON.stringify(json)}`);
  return json;
}

const otp = await post('/auth/otp/request', { phone });
if (!otp.dev_code) {
  console.error('No dev_code returned (OTP is not exposed). Log in via the dispatch console with the SMS code instead.');
  process.exit(1);
}
const verified = await post('/auth/otp/verify', { phone, code: otp.dev_code });
const token = verified.tokens?.accessToken;
if (!token) throw new Error('No access token returned');
const url = `${web}/?api=${encodeURIComponent(api)}&token=${encodeURIComponent(token)}`;
console.log(url);
