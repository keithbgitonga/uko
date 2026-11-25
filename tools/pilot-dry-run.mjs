#!/usr/bin/env node
// Scripted pilot dry run: rider, driver, documents, trip, payment, rating,
// scheduling, SOS, dispatch review, notifications and analytics in one pass.
import { writeFile } from 'node:fs/promises';

const BASE = process.env.API_BASE || 'http://localhost:3100/v1';
const RIDER_PHONE = process.env.DRY_RIDER_PHONE || '+254712345678';
const DRIVER_PHONE = process.env.DRY_DRIVER_PHONE || '+254700000020';
const password = 'dry-run';
const checks = [];
const startedAt = new Date().toISOString();

async function call(method, path, body, token, raw = false) {
  const response = await fetch(BASE + path, {
    method,
    headers: {
      ...(raw ? {} : { 'content-type': 'application/json' }),
      ...(token ? { authorization: `Bearer ${token}` } : {}),
    },
    body: body === undefined ? undefined : raw ? body : JSON.stringify(body),
  });
  const text = await response.text();
  let json = {};
  try { json = text ? JSON.parse(text) : {}; } catch { json = { raw: text }; }
  return { status: response.status, body: json };
}

function check(name, ok, detail = '') {
  checks.push({ name, pass: !!ok, detail });
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${detail ? ' — ' + detail : ''}`);
}

async function login(phone) {
  const otp = await call('POST', '/auth/otp/request', { phone });
  const verified = await call('POST', '/auth/otp/verify', { phone, code: otp.body.dev_code });
  return verified.body.tokens?.accessToken;
}

const readiness = await call('GET', '/health/ready');
check('readiness ok', readiness.status === 200 && readiness.body.status === 'ok', readiness.body.status);

const rider = await login(RIDER_PHONE);
check('rider login', !!rider);
const driver = await login(DRIVER_PHONE);
check('driver login', !!driver);

// Documents: upload, verify gate, approve, online.
async function upload(type, fileName) {
  const form = new FormData();
  form.set('type', type);
  form.set('documentNumber', `${type.toUpperCase()}-DRY`);
  form.set('file', new Blob([`Uko? dry-run ${type} document`], { type: 'text/plain' }), fileName);
  const response = await fetch(`${BASE}/driver/documents`, {
    method: 'POST',
    headers: { authorization: `Bearer ${driver}` },
    body: form,
  });
  return { status: response.status, body: await response.json().catch(() => ({})) };
}
const licence = await upload('licence', 'dry-licence.txt');
const insurance = await upload('insurance', 'dry-insurance.txt');
check('licence uploaded', licence.status === 201 && licence.body.document?.status === 'PENDING');
check('insurance uploaded', insurance.status === 201 && insurance.body.document?.status === 'PENDING');

const gated = await call('POST', '/driver/online', { online: true }, driver);
check('online blocked while pending', gated.status === 403 && gated.body.code === 'DOCUMENTS_PENDING', gated.body.code);

const uploadedIds = [licence.body.document?.id, insurance.body.document?.id].filter(Boolean);
for (const id of uploadedIds) {
  await call('POST', `/dispatch/documents/${id}/approve`, {}, rider);
}
const reviewed = await call('GET', '/dispatch/documents', undefined, rider);
const reviewedDocs = (reviewed.body.documents || []).filter((d) => uploadedIds.includes(d.id));
const approvedCount = reviewedDocs.filter((d) => d.status === 'APPROVED').length;
check('documents approved by dispatch', approvedCount === 2, `${approvedCount} approved`);

const online = await call('POST', '/driver/online', { online: true }, driver);
check('driver online after approval', online.status === 201 && online.body.online === true);

// Ride lifecycle.
const quote = await call('POST', '/quotes', {
  pickup: { lat: -1.2921, lng: 36.8219, address: 'Kenyatta Avenue' },
  dropoff: { lat: -1.2648, lng: 36.8031, address: 'Westlands' },
}, rider);
check('quote', quote.status === 201 && quote.body.quote?.fare > 0, `KES ${quote.body.quote?.fare}`);
const ride = await call('POST', '/rides', { quoteId: quote.body.quote.id, paymentMethod: 'cash' }, rider);
check('ride requested', ride.status === 201 && ride.body.ride?.state === 'SEARCHING');
const offers = await call('GET', '/driver/offers', undefined, driver);
const offer = (offers.body.offers || []).find((o) => o.rideId === ride.body.ride.id);
check('driver sees offer', !!offer);
const accept = await call('POST', `/driver/offers/${offer.id}/accept`, {}, driver);
check('offer accepted', accept.status === 201 && accept.body.trip?.state === 'ACCEPTED');
const tripId = accept.body.trip.id;
for (const action of ['arrived', 'start', 'complete']) {
  const result = await call('POST', `/driver/trips/${tripId}/${action}`, {}, driver);
  check(`trip ${action}`, result.status === 201);
}
const cash = await call('POST', '/payments/cash/confirm', { rideId: ride.body.ride.id }, rider);
check('cash payment', cash.status === 201 && cash.body.payment?.status === 'SUCCESS', cash.body.payment?.receipt);

// Rating.
const rating = await call('POST', '/ratings', { rideId: ride.body.ride.id, rating: 5 }, rider);
check('rating saved', rating.status === 201 && rating.body.rating?.rating === 5 && !!rating.body.rating?.driverId);

// Scheduling.
const when = new Date(Date.now() + 2 * 3600_000).toISOString();
const scheduled = await call('POST', '/scheduled-rides', {
  pickup: { lat: -1.2921, lng: 36.8219, address: 'Kenyatta Avenue' },
  dropoff: { lat: -1.2648, lng: 36.8031, address: 'Westlands' },
  scheduledAt: when, paymentMethod: 'mpesa',
}, rider);
check('scheduled ride', scheduled.status === 201 && scheduled.body.scheduledRide?.status === 'SCHEDULED');
const end = new Date(Date.now() + 3 * 7 * 24 * 3600_000).toISOString();
const repeat = await call('POST', `/scheduled-rides/${scheduled.body.scheduledRide.id}/repeat`, {
  weekdays: [new Date().getDay() === 0 ? 7 : new Date().getDay()], endDate: end,
}, rider);
check('weekly series', repeat.status === 201 && !!repeat.body.series?.id);

// Safety.
const sos = await call('POST', '/safety/sos', { note: 'Pilot dry run SOS' }, rider);
check('SOS created', sos.status === 201, sos.body.incident?.state);
const sosId = sos.body.incident.id;
let sosState = sos.body.incident.state;
for (let i = 0; i < 12 && sosState === 'OPEN'; i += 1) {
  await new Promise((r) => setTimeout(r, 500));
  const current = await call('GET', `/safety/incidents/${sosId}`, undefined, rider);
  sosState = current.body.incident?.state;
}
check('SOS acknowledged', sosState === 'ACKED', sosState);
const cancelled = await call('POST', `/safety/incidents/${sosId}/cancel`, {}, rider);
check('SOS cancelled', cancelled.status === 201 && cancelled.body.incident?.state === 'CANCELLED');

// Notifications and dispatch.
const riderNotifications = await call('GET', '/notifications', undefined, rider);
check('rider notifications', (riderNotifications.body.notifications || []).length > 0, `${(riderNotifications.body.notifications || []).length} items`);
const driverNotifications = await call('GET', '/notifications', undefined, driver);
check('driver notifications', (driverNotifications.body.notifications || []).length > 0, `${(driverNotifications.body.notifications || []).length} items`);
const overview = await call('GET', '/dispatch/overview', undefined, rider);
check('dispatch overview', overview.status === 200 && overview.body.metrics?.completedToday >= 1);
const audit = await call('GET', '/dispatch/audit', undefined, rider);
const actions = (audit.body.entries || []).map((e) => e.action);
check('document approvals audited', actions.filter((a) => a === 'document.approve').length >= 2);
const metrics = await call('GET', '/metrics');
const events = (metrics.body.events24h || []).map((e) => e.event);
check('analytics events', ['ride_requested', 'rating_submitted', 'sos_triggered'].every((e) => events.includes(e)), events.join(', '));

const failed = checks.filter((c) => !c.pass);
const report = {
  startedAt,
  finishedAt: new Date().toISOString(),
  api: BASE,
  checks,
  passed: checks.length - failed.length,
  total: checks.length,
  ok: failed.length === 0,
};
await writeFile('testbench/evidence/pilot-dry-run-report.json', JSON.stringify(report, null, 2));
console.log(`\n${report.passed}/${report.total} checks passed — report: testbench/evidence/pilot-dry-run-report.json`);
process.exit(report.ok ? 0 : 1);
