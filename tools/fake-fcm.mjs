#!/usr/bin/env node
// Fake FCM legacy endpoint for notification integration tests.
import http from 'node:http';

const port = Number(process.env.PORT || 8091);
let counter = 0;
http.createServer(async (req, res) => {
  const chunks = [];
  for await (const chunk of req) chunks.push(chunk);
  const raw = Buffer.concat(chunks).toString('utf-8');
  console.log(JSON.stringify({ method: req.method, url: req.url, auth: req.headers.authorization ? 'present' : 'missing', body: raw.slice(0, 400) }));
  if (req.url === '/fcm/send' && req.method === 'POST') {
    counter += 1;
    res.writeHead(200, { 'content-type': 'application/json' });
    res.end(JSON.stringify({ success: 1, failure: 0, results: [{ message_id: `fake-msg-${counter}` }] }));
    return;
  }
  res.writeHead(404, { 'content-type': 'application/json' });
  res.end(JSON.stringify({ error: 'not found' }));
}).listen(port, () => console.log(`fake FCM on http://localhost:${port}`));
