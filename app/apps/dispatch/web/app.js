const params = new URLSearchParams(location.search);
const LOCAL_API = 'http://localhost:3100/v1';
const API_KEY = 'uko_dispatch_api';
let apiBase = (params.get('api') || localStorage.getItem(API_KEY) || (['localhost', '127.0.0.1'].includes(location.hostname) ? LOCAL_API : '')).replace(/\/$/, '');
const TOKEN_KEY = 'uko_dispatch_token';
let token = params.get('token') || localStorage.getItem(TOKEN_KEY) || '';
let currentView = params.get('view') || 'overview';
let refreshTimer = null;
let state = { metrics: null, rides: [], incidents: [], scheduled: [], series: [], audit: [], documents: [], ready: null, system: null, alerts: null, reconciliation: null };

const $ = (id) => document.getElementById(id);

function escapeHtml(value) {
  return String(value ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
}

function fmtWhen(value) {
  if (!value) return '—';
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return value;
  return date.toLocaleString('en-GB', { timeZone: 'Africa/Nairobi', day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit', hour12: false });
}

async function api(path, options = {}) {
  if (!apiBase) throw new Error('Set the API URL first');
  const response = await fetch(`${apiBase}${path}`, {
    ...options,
    headers: {
      'content-type': 'application/json',
      ...(token ? { authorization: `Bearer ${token}` } : {}),
      ...(options.headers || {}),
    },
  });
  const body = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error(body.message || body.error || `HTTP ${response.status}`);
  return body;
}

function showLogin() {
  $('app').classList.add('hidden');
  $('login').classList.remove('hidden');
  $('api-base').textContent = apiBase || 'not set';
  if ($('api-input') && !$('api-input').value) $('api-input').value = apiBase;
}

function showApp() {
  $('login').classList.add('hidden');
  $('app').classList.remove('hidden');
  setView(currentView);
  refresh();
  refreshTimer = setInterval(refresh, 5000);
}

function setView(view) {
  currentView = view;
  document.querySelectorAll('.nav-item').forEach((el) => el.classList.toggle('active', el.dataset.view === view));
  document.querySelectorAll('.view').forEach((el) => el.classList.add('hidden'));
  $('view-' + view).classList.remove('hidden');
  $('view-title').textContent = { overview: 'Overview', rides: 'Rides', incidents: 'Incidents', scheduled: 'Scheduled', audit: 'Audit', system: 'System', documents: 'Documents', money: 'Money' }[view] || 'Overview';
}

function renderMetrics(metrics) {
  const cards = [
    { label: 'Active rides', value: metrics.activeRides, hint: 'searching, assigned or on trip' },
    { label: 'Completed today', value: metrics.completedToday, hint: `KES ${metrics.grossToday} gross` },
    { label: 'Open incidents', value: metrics.openIncidents, hint: 'SOS needing attention' },
    { label: 'Drivers online', value: metrics.driversOnline, hint: 'available now' },
    { label: 'Scheduled upcoming', value: metrics.scheduledUpcoming, hint: 'single + series occurrences' },
    { label: 'Pilot zone', value: 'Thika', hint: 'Boda only' },
  ];
  $('metrics').innerHTML = cards.map((c) => `
    <div class="metric">
      <div class="label">${escapeHtml(c.label)}</div>
      <div class="value">${escapeHtml(c.value)}</div>
      <div class="hint">${escapeHtml(c.hint)}</div>
    </div>`).join('');
}

function rideRows(rides) {
  if (!rides.length) return '<div class="empty">No rides yet.</div>';
  return `<table><thead><tr><th>When</th><th>Rider</th><th>Route</th><th>Fare</th><th>State</th><th></th></tr></thead><tbody>
    ${rides.map((r) => `<tr>
      <td>${escapeHtml(fmtWhen(r.createdAt))}</td>
      <td>${escapeHtml(r.riderPhone || '—')}</td>
      <td class="route">${escapeHtml(r.pickup?.address || '—')} → ${escapeHtml(r.dropoff?.address || '—')}</td>
      <td>KES ${escapeHtml(r.fare)}</td>
      <td><span class="chip ${escapeHtml(r.state)}">${escapeHtml(r.state)}</span>
        ${r.cancellation?.label ? `<div class="muted small">${escapeHtml(r.cancellation.label)}</div>` : ''}
      </td>
      <td>${['SEARCHING','ASSIGNED','ARRIVING','ARRIVED','IN_PROGRESS'].includes(r.state)
        ? `<button class="link-button" data-cancel-ride="${escapeHtml(r.id)}">Cancel</button>` : ''}</td>
    </tr>`).join('')}
  </tbody></table>`;
}

function incidentRows(incidents) {
  if (!incidents.length) return '<div class="empty">No incidents.</div>';
  return `<table><thead><tr><th>When</th><th>Rider</th><th>Note</th><th>State</th><th></th></tr></thead><tbody>
    ${incidents.map((i) => `<tr>
      <td>${escapeHtml(fmtWhen(i.createdAt))}</td>
      <td>${escapeHtml(i.riderId ? i.riderId.slice(0, 8) : '—')}</td>
      <td>${escapeHtml(i.note || i.type || 'SOS')}</td>
      <td><span class="chip ${escapeHtml(i.state)}">${escapeHtml(i.state)}</span></td>
      <td>${['OPEN','ACKED'].includes(i.state)
        ? `<button class="link-button" data-resolve-incident="${escapeHtml(i.id)}">Resolve</button>` : ''}</td>
    </tr>`).join('')}
  </tbody></table>`;
}

function scheduledRows(rides) {
  if (!rides.length) return '<div class="empty">No scheduled rides.</div>';
  return `<table><thead><tr><th>When</th><th>Rider</th><th>Route</th><th>Fare</th><th>State</th></tr></thead><tbody>
    ${rides.map((r) => `<tr>
      <td>${escapeHtml(fmtWhen(r.scheduledAt))}</td>
      <td>${escapeHtml(r.riderPhone || '—')}</td>
      <td class="route">${escapeHtml(r.pickup?.address || '—')} → ${escapeHtml(r.dropoff?.address || '—')}</td>
      <td>KES ${escapeHtml(r.fare)}</td>
      <td><span class="chip ${escapeHtml(r.status)}">${escapeHtml(r.status)}</span></td>
    </tr>`).join('')}
  </tbody></table>`;
}

function auditRows(entries) {
  if (!entries.length) return '<div class="empty">No audit entries yet.</div>';
  return `<table><thead><tr><th>When</th><th>Actor</th><th>Action</th><th>Entity</th><th>Detail</th></tr></thead><tbody>
    ${entries.map((e) => `<tr>
      <td>${escapeHtml(fmtWhen(e.createdAt))}</td>
      <td>${escapeHtml(e.actorPhone || '—')}</td>
      <td><span class="chip IN_PROGRESS">${escapeHtml(e.action)}</span></td>
      <td>${escapeHtml(e.entity)} ${escapeHtml((e.entityId || '').slice(0, 10))}</td>
      <td>${escapeHtml(JSON.stringify(e.detail || {}))}</td>
    </tr>`).join('')}
  </tbody></table>`;
}

function seriesRows(series) {
  if (!series.length) return '<div class="empty">No weekly series.</div>';
  return `<table><thead><tr><th>Days</th><th>Time</th><th>Window</th><th>Occurrences</th><th>State</th></tr></thead><tbody>
    ${series.map((s) => `<tr>
      <td>${escapeHtml((s.weekdays || []).map((d) => ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'][d - 1]).join(' & '))}</td>
      <td>${escapeHtml(s.timeOfDay)}</td>
      <td>${escapeHtml(s.startDate)} → ${escapeHtml(s.endDate)}</td>
      <td>${escapeHtml((s.occurrences || []).length)}</td>
      <td><span class="chip ${escapeHtml(s.status)}">${escapeHtml(s.status)}</span></td>
    </tr>`).join('')}
  </tbody></table>`;
}

function renderMoney() {
  const rec = state.reconciliation || {};
  const cards = [
    { label: 'Completed rides', value: rec.completedRides ?? 0, hint: rec.date || '' },
    { label: 'Gross fare', value: `KES ${rec.grossFare ?? 0}`, hint: 'completed today' },
    { label: 'Paid', value: `KES ${rec.paidAmount ?? 0}`, hint: `${rec.paidCount ?? 0} rides` },
    { label: 'Unpaid', value: `KES ${rec.unpaidAmount ?? 0}`, hint: `${rec.unpaidCount ?? 0} rides` },
    { label: 'Commission', value: `KES ${rec.commission?.commission ?? 0}`, hint: `${rec.commission?.rate ?? 20}% of paid gross` },
    { label: 'Driver payout', value: `KES ${rec.commission?.net ?? 0}`, hint: 'net for paid rides' },
  ];
  $('money-metrics').innerHTML = cards.map((c) => `
    <div class="metric"><div class="label">${escapeHtml(c.label)}</div><div class="value">${escapeHtml(c.value)}</div><div class="hint">${escapeHtml(c.hint)}</div></div>`).join('');
  const byMethod = rec.byMethod || {};
  $('money-methods').innerHTML = Object.keys(byMethod).length
    ? `<table><thead><tr><th>Method</th><th>Rides</th><th>Paid</th><th>Amount</th></tr></thead><tbody>${Object.entries(byMethod).map(([m, v]) => `<tr><td>${escapeHtml(m.toUpperCase())}</td><td>${v.rides}</td><td>${v.paid}</td><td>KES ${v.amount}</td></tr>`).join('')}</tbody></table>`
    : '<div class="empty">No completed rides today.</div>';
  const c = rec.commission || {};
  $('money-commission').innerHTML = `<table><tbody>
    <tr><th>Paid gross</th><td>KES ${c.gross ?? 0}</td></tr>
    <tr><th>Commission (${c.rate ?? 20}%)</th><td>KES ${c.commission ?? 0}</td></tr>
    <tr><th>Driver payout</th><td>KES ${c.net ?? 0}</td></tr>
  </tbody></table>`;
  const mismatches = rec.mismatches || [];
  $('money-mismatches').innerHTML = mismatches.length
    ? `<table><thead><tr><th>Ride</th><th>Reason</th><th>Fare</th><th>Detail</th></tr></thead><tbody>${mismatches.map((m) => `<tr><td>${escapeHtml((m.rideId || '').slice(0, 14))}</td><td><span class="chip ACKED">${escapeHtml(m.reason)}</span></td><td>KES ${escapeHtml(m.fare ?? '')}</td><td>${escapeHtml(m.paymentStatus || m.paymentAmount || m.count || '')}</td></tr>`).join('')}</tbody></table>`
    : '<div class="empty">No mismatches — all completed rides have a matching successful payment.</div>';
}

function documentRows(documents) {
  if (!documents.length) return '<div class="empty">No driver documents yet.</div>';
  return `<table><thead><tr><th>Uploaded</th><th>Driver</th><th>Type</th><th>File</th><th>Status</th><th></th></tr></thead><tbody>
    ${documents.map((d) => `<tr>
      <td>${escapeHtml(fmtWhen(d.createdAt))}</td>
      <td>${escapeHtml((d.driverId || '').slice(0, 8))}</td>
      <td>${escapeHtml((d.type || '').replaceAll('_', ' ').toUpperCase())}</td>
      <td>${escapeHtml(d.fileName || '—')}</td>
      <td><span class="chip ${d.status === 'APPROVED' ? 'COMPLETED' : d.status === 'REJECTED' ? 'CANCELLED' : 'ACKED'}">${escapeHtml(d.status)}</span></td>
      <td>${d.status === 'PENDING' ? `<div class="row-actions"><button class="link-button" data-approve-doc="${escapeHtml(d.id)}">Approve</button><button class="link-button" data-reject-doc="${escapeHtml(d.id)}">Reject</button></div>` : ''}</td>
    </tr>`).join('')}
  </tbody></table>`;
}

function renderSystem() {
  const ready = state.ready || {};
  const system = state.system || {};
  const http = system.requests || {};
  const cards = [
    { label: 'Readiness', value: (ready.status || 'unknown').toUpperCase(), hint: ready.checks?.database?.ok ? `DB ok · ${ready.checks.database.latencyMs} ms` : 'database unavailable' },
    { label: 'API requests', value: http.total ?? 0, hint: `${http.failures ?? 0} failures` },
    { label: 'Average response', value: `${http.averageMs ?? 0} ms`, hint: 'since API start' },
    { label: 'Uptime', value: `${Math.floor((system.uptimeSeconds || 0) / 60)}m`, hint: `${system.uptimeSeconds ?? 0}s` },
    { label: 'Rides', value: system.database?.counts?.rides ?? 0, hint: 'stored rides' },
    { label: 'Notifications', value: system.database?.counts?.notifications ?? 0, hint: 'outbox rows' },
  ];
  $('system-metrics').innerHTML = cards.map((c) => `
    <div class="metric"><div class="label">${escapeHtml(c.label)}</div><div class="value">${escapeHtml(c.value)}</div><div class="hint">${escapeHtml(c.hint)}</div></div>`).join('');
  $('system-ready').innerHTML = ready.status
    ? `<table><tbody>
        <tr><th>Status</th><td>${escapeHtml(ready.status)}</td></tr>
        <tr><th>Database</th><td>${ready.checks?.database?.ok ? 'ok' : 'degraded'}${ready.checks?.database?.latencyMs != null ? ` · ${ready.checks.database.latencyMs} ms` : ''}</td></tr>
        ${Object.entries(ready.counts || {}).map(([k, v]) => `<tr><th>${escapeHtml(k)}</th><td>${escapeHtml(v)}</td></tr>`).join('')}
      </tbody></table>`
    : '<div class="empty">No readiness data.</div>';
  const events = system.events24h || [];
  const alerts = state.alerts || {};
  const alertList = alerts.alerts || [];
  $('system-alerts').innerHTML = alertList.length
    ? `<table><thead><tr><th>Level</th><th>Code</th><th>Message</th></tr></thead><tbody>${alertList.map((a) => `<tr><td><span class="chip ${a.level === 'critical' ? 'CANCELLED' : 'ACKED'}">${escapeHtml(a.level.toUpperCase())}</span></td><td>${escapeHtml(a.code)}</td><td>${escapeHtml(a.message)}</td></tr>`).join('')}</tbody></table>`
    : `<div class="empty">No alerts — system status: ${escapeHtml(alerts.status || 'unknown')}.</div>`;
  $('system-events').innerHTML = events.length
    ? `<table><thead><tr><th>Event</th><th>Count</th></tr></thead><tbody>${events.map((e) => `<tr><td>${escapeHtml(e.event)}</td><td>${escapeHtml(e.count)}</td></tr>`).join('')}</tbody></table>`
    : '<div class="empty">No events yet.</div>';
}

function render() {
  renderMetrics(state.metrics || { activeRides: 0, completedToday: 0, grossToday: 0, openIncidents: 0, driversOnline: 0, scheduledUpcoming: 0 });
  $('overview-rides').innerHTML = rideRows(state.rides.slice(0, 5));
  $('overview-incidents').innerHTML = incidentRows(state.incidents.slice(0, 5));
  $('rides-table').innerHTML = rideRows(state.rides);
  $('incidents-table').innerHTML = incidentRows(state.incidents);
  $('scheduled-table').innerHTML = scheduledRows(state.scheduled);
  $('series-table').innerHTML = seriesRows(state.series);
  $('audit-table').innerHTML = auditRows(state.audit);
  $('documents-table').innerHTML = documentRows(state.documents);
  renderMoney();
  renderSystem();
  $('last-updated').textContent = 'Updated ' + new Date().toLocaleTimeString('en-GB', { timeZone: 'Africa/Nairobi', hour12: false });
  bindActions();
}

function bindActions() {
  document.querySelectorAll('[data-cancel-ride]').forEach((el) => {
    el.onclick = async () => {
      if (!confirm('Cancel this ride?')) return;
      try { await api(`/dispatch/rides/${el.dataset.cancelRide}/cancel`, { method: 'POST' }); refresh(); }
      catch (err) { alert(err.message); }
    };
  });
  document.querySelectorAll('[data-approve-doc]').forEach((el) => {
    el.onclick = async () => {
      try { await api(`/dispatch/documents/${el.dataset.approveDoc}/approve`, { method: 'POST' }); refresh(); }
      catch (err) { alert(err.message); }
    };
  });
  document.querySelectorAll('[data-reject-doc]').forEach((el) => {
    el.onclick = async () => {
      try { await api(`/dispatch/documents/${el.dataset.rejectDoc}/reject`, { method: 'POST', body: JSON.stringify({ reason: 'Document not clear' }) }); refresh(); }
      catch (err) { alert(err.message); }
    };
  });
  document.querySelectorAll('[data-resolve-incident]').forEach((el) => {
    el.onclick = async () => {
      try { await api(`/dispatch/incidents/${el.dataset.resolveIncident}/resolve`, { method: 'POST' }); refresh(); }
      catch (err) { alert(err.message); }
    };
  });
}

async function refresh() {
  if (!token) return;
  try {
    const [overview, rides, incidents, scheduled, audit, documents, reconciliation, ready, system, alerts] = await Promise.all([
      api('/dispatch/overview'),
      api('/dispatch/rides'),
      api('/dispatch/incidents'),
      api('/dispatch/scheduled'),
      api('/dispatch/audit'),
      api('/dispatch/documents'),
      api('/dispatch/reconciliation'),
      api('/health/ready'),
      api('/metrics'),
      api('/health/alerts'),
    ]);
    state.metrics = overview.metrics;
    state.rides = rides.rides || [];
    state.incidents = incidents.incidents || [];
    state.scheduled = scheduled.scheduledRides || [];
    state.series = scheduled.series || [];
    state.audit = audit.entries || [];
    state.documents = documents.documents || [];
    state.reconciliation = reconciliation;
    state.ready = ready;
    state.system = system;
    state.alerts = alerts;
    render();
  } catch (err) {
    if (/401|ACCESS|invalid/i.test(err.message)) {
      localStorage.removeItem(TOKEN_KEY);
      token = '';
      showLogin();
    }
    $('last-updated').textContent = 'Refresh failed: ' + err.message;
  }
}

$('send-code').onclick = async () => {
  $('login-error').textContent = '';
  const typed = ($('api-input')?.value || '').trim().replace(/\/$/, '');
  if (!typed) { $('login-error').textContent = 'Enter the API URL, e.g. https://your-api.onrender.com/v1'; return; }
  apiBase = typed;
  localStorage.setItem(API_KEY, apiBase);
  $('api-base').textContent = apiBase;
  try {
    const body = await api('/auth/otp/request', { method: 'POST', body: JSON.stringify({ phone: $('phone').value.trim() }) });
    $('otp-block').classList.remove('hidden');
    if (body.dev_code) {
      $('dev-code').textContent = `dev code: ${body.dev_code}`;
      $('otp').value = body.dev_code;
    }
  } catch (err) { $('login-error').textContent = err.message; }
};

$('verify').onclick = async () => {
  $('login-error').textContent = '';
  try {
    const body = await api('/auth/otp/verify', { method: 'POST', body: JSON.stringify({ phone: $('phone').value.trim(), code: $('otp').value.trim() }) });
    token = body.tokens.accessToken;
    localStorage.setItem(TOKEN_KEY, token);
    $('ops-phone').textContent = body.user.phone;
    showApp();
  } catch (err) { $('login-error').textContent = err.message; }
};

$('refresh').onclick = refresh;
$('signout').onclick = () => { localStorage.removeItem(TOKEN_KEY); token = ''; clearInterval(refreshTimer); showLogin(); };
document.querySelectorAll('[data-view]').forEach((el) => { el.onclick = () => setView(el.dataset.view); });

if (token && apiBase) {
  $('ops-phone').textContent = 'Signed in';
  showApp();
} else {
  showLogin();
}
