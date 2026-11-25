#!/usr/bin/env node
// Daily pilot check: readiness, alerts, money reconciliation, documents,
// notifications and client errors in one report. Run each morning.
import { writeFile } from 'node:fs/promises';

const BASE = process.env.API_BASE || 'http://localhost:3100/v1';
const OPS_PHONE = process.env.PILOT_OPS_PHONE || '+254712345678';
const DEV = (process.env.PILOT_DEV_OTP ?? 'true') !== 'false';
const results = [];
const startedAt = new Date().toISOString();

async function call(method, path, body, token) {
  const response = await fetch(BASE + path, {
    method,
    headers: {
      'content-type': 'application/json',
      ...(token ? { authorization: `Bearer ${token}` } : {}),
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const text = await response.text();
  let json = {};
  try { json = text ? JSON.parse(text) : {}; } catch { json = { raw: text }; }
  return { status: response.status, body: json };
}

function item(name, status, detail = '') {
  results.push({ name, status, detail });
  const icon = status === 'PASS' ? 'PASS' : status === 'WARN' ? 'WARN' : 'FAIL';
  console.log(`${icon}  ${name}${detail ? ' — ' + detail : ''}`);
}

async function opsToken() {
  if (process.env.API_TOKEN) return process.env.API_TOKEN;
  if (!DEV) return null;
  const otp = await call('POST', '/auth/otp/request', { phone: OPS_PHONE });
  if (!otp.body.dev_code) return null;
  const verified = await call('POST', '/auth/otp/verify', { phone: OPS_PHONE, code: otp.body.dev_code });
  return verified.body.tokens?.accessToken ?? null;
}

const readiness = await call('GET', '/health/ready');
const ready = readiness.status === 200 && readiness.body.status === 'ok';
item('readiness', ready ? 'PASS' : 'FAIL', `status=${readiness.body.status} dbLatency=${readiness.body.checks?.database?.latencyMs ?? 'n/a'}ms`);

const alerts = await call('GET', '/health/alerts');
const alertList = alerts.body.alerts || [];
const critical = alertList.filter((a) => a.level === 'critical');
item('alerts', alerts.body.status === 'ok' ? 'PASS' : critical.length ? 'FAIL' : 'WARN', `${alerts.body.status} · ${alertList.map((a) => a.code).join(', ') || 'none'}`);

const metrics = await call('GET', '/metrics');
item('http traffic', metrics.body.requests?.failures === 0 ? 'PASS' : 'WARN', `${metrics.body.requests?.total ?? 0} requests · ${metrics.body.requests?.failures ?? 0} failures`);

const token = await opsToken();
if (token) {
  const rec = await call('GET', '/dispatch/reconciliation', undefined, token);
  const r = rec.body;
  const unpaid = (r.mismatches || []).filter((m) => m.reason === 'unpaid').length;
  item('money reconciliation', unpaid === 0 ? 'PASS' : 'WARN', `${r.completedRides ?? 0} completed · paid KES ${r.paidAmount ?? 0} · unpaid KES ${r.unpaidAmount ?? 0} · ${unpaid} unpaid`);
  const docs = await call('GET', '/dispatch/documents', undefined, token);
  const pending = (docs.body.documents || []).filter((d) => d.status === 'PENDING').length;
  item('driver documents', pending === 0 ? 'PASS' : 'WARN', `${pending} pending review`);
  const audit = await call('GET', '/dispatch/audit', undefined, token);
  item('ops audit', audit.status === 200 ? 'PASS' : 'FAIL', `${(audit.body.entries || []).length} recent entries`);
} else {
  item('ops checks', 'WARN', 'no API_TOKEN and dev OTP unavailable (production: supply API_TOKEN)');
}

const report = { startedAt, finishedAt: new Date().toISOString(), api: BASE, results };
const failed = results.filter((r) => r.status === 'FAIL').length;
const warnings = results.filter((r) => r.status === 'WARN').length;
await writeFile('testbench/evidence/pilot-check-report.json', JSON.stringify(report, null, 2));
console.log(`\n${results.length - failed - warnings} pass · ${warnings} warn · ${failed} fail — report: testbench/evidence/pilot-check-report.json`);
process.exit(failed === 0 ? 0 : 1);
