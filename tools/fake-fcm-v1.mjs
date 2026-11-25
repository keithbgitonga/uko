#!/usr/bin/env node
// Fake Google OAuth2 + FCM HTTP v1 endpoints for integration tests.
import http from 'node:http';

const port = Number(process.env.PORT || 8094);
let counter = 0;
http.createServer(async (req, res) => {
  const chunks = [];
  for await (const chunk of req) chunks.push(chunk);
  const raw = Buffer.concat(chunks).toString('utf-8');
  console.log(JSON.stringify({ method: req.method, url: req.url, auth: req.headers.authorization ? 'present' : 'missing', body: raw.slice(0, 300) }));
  if (req.url === '/token' && req.method === 'POST') {
    res.writeHead(200, { 'content-type': 'application/json' });
    res.end(JSON.stringify({ access_token: 'fake-v1-access-token', expires_in: 3599, token_type: 'Bearer' }));
    return;
  }
  if (req.url?.startsWith('/v1/projects/') && req.url.endsWith('/messages:send') && req.method === 'POST') {
    counter += 1;
    res.writeHead(200, { 'content-type': 'application/json' });
    res.end(JSON.stringify({ name: `projects/uko-pilot/messages/fake-v1-${counter}` }));
    return;
  }
  res.writeHead(404, { 'content-type': 'application/json' });
  res.end(JSON.stringify({ error: 'not found' }));
}).listen(port, () => console.log(`fake FCM v1 on http://localhost:${port}`));
