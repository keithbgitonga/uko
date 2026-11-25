#!/usr/bin/env node
// Pilot smoke test: exercises the API paths the pilot depends on and reports PASS/FAIL.
const BASE = process.env.API_BASE || 'http://localhost:3100/v1';
const RIDER_PHONE = process.env.SMOKE_RIDER_PHONE || '+254712345678';
const DRIVER_PHONE = process.env.SMOKE_DRIVER_PHONE || '+254700000001';
const checks = [];
const tokens = {};

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

function check(name, condition, detail = '') {
  checks.push({ name, pass: !!condition, detail });
  console.log(`${condition ? 'PASS' : 'FAIL'}  ${name}${detail ? ' — ' + detail : ''}`);
}

async function login(phone) {
  const otp = await call('POST', '/auth/otp/request', { phone });
  const code = otp.body.dev_code;
  const verified = await call('POST', '/auth/otp/verify', { phone, code });
  return { ok: otp.status === 201 && verified.status === 201, token: verified.body.tokens?.accessToken };
}

const health = await call('GET', '/health');
check('health endpoint', health.status === 200, `status ${health.status}`);

const rider = await login(RIDER_PHONE);
tokens.rider = rider.token;
check('rider OTP login', rider.ok);

const driver = await login(DRIVER_PHONE);
tokens.driver = driver.token;
check('driver OTP login', driver.ok);

const quote = await call('POST', '/quotes', {
  pickup: { lat: -1.2921, lng: 36.8219, address: 'Kenyatta Avenue' },
  dropoff: { lat: -1.2648, lng: 36.8031, address: 'Westlands' },
}, rider.token);
check('quote created', quote.status === 201 && quote.body.quote?.fare > 0, `KES ${quote.body.quote?.fare}`);
const quoteId = quote.body.quote?.id;

const ride = await call('POST', '/rides', { quoteId, paymentMethod: 'cash' }, rider.token);
check('ride requested', ride.status === 201 && !!ride.body.ride?.id, ride.body.ride?.state);
const rideId = ride.body.ride?.id;
const cancel = await call('POST', `/rides/${rideId}/cancel`, {}, rider.token);
check('rider cancellation', cancel.status === 201, cancel.body.ride?.state);

const scheduledAt = new Date(Date.now() + 2 * 3600_000).toISOString();
const scheduled = await call('POST', '/scheduled-rides', {
  pickup: { lat: -1.2921, lng: 36.8219, address: 'Kenyatta Avenue' },
  dropoff: { lat: -1.2648, lng: 36.8031, address: 'Westlands' },
  scheduledAt, paymentMethod: 'mpesa',
}, rider.token);
check('scheduled ride created', scheduled.status === 201 && !!scheduled.body.scheduledRide?.id, scheduled.body.scheduledRide?.status);

const contact = await call('POST', '/safety/contacts', { name: 'Pilot Smoke', phone: '+254799000222' }, rider.token);
check('safety contact created', contact.status === 201);
const sos = await call('POST', '/safety/sos', { note: 'Pilot smoke test' }, rider.token);
check('SOS incident created', sos.status === 201, sos.body.incident?.state);
const sosId = sos.body.incident?.id;
let sosState = sos.body.incident?.state;
for (let i = 0; i < 12 && sosState === 'OPEN'; i += 1) {
  await new Promise((resolve) => setTimeout(resolve, 500));
  const current = await call('GET', `/safety/incidents/${sosId}`, undefined, rider.token);
  sosState = current.body.incident?.state;
}
check('SOS acknowledged by ops simulation', sosState === 'ACKED', sosState);
const cancelSos = await call('POST', `/safety/incidents/${sosId}/cancel`, {}, rider.token);
check('SOS cancelled cleanly', cancelSos.status === 201, cancelSos.body.incident?.state);

const online = await call('POST', '/driver/online', { online: true }, driver.token);
check('driver online', online.status === 201);
const offers = await call('GET', '/driver/offers', undefined, driver.token);
check('driver offers endpoint', offers.status === 200, `${(offers.body.offers || []).length} offer(s)`);
const overview = await call('GET', '/dispatch/overview', undefined, rider.token);
check('dispatch overview', overview.status === 200, `active ${overview.body.metrics?.activeRides}, incidents ${overview.body.metrics?.openIncidents}`);
const audit = await call('GET', '/dispatch/audit', undefined, rider.token);
check('dispatch audit endpoint', audit.status === 200, `${(audit.body.entries || []).length} entries`);

const failed = checks.filter((c) => !c.pass);
console.log(`\n${checks.length - failed.length}/${checks.length} checks passed`);
if (tokens.rider) await import('node:fs/promises').then((fs) => fs.writeFile('/tmp/pilot_smoke_token.txt', tokens.rider));
process.exit(failed.length === 0 ? 0 : 1);
