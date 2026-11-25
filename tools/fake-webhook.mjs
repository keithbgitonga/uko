#!/usr/bin/env node
// Fake Slack-compatible webhook for alert delivery tests.
import http from 'node:http';

const port = Number(process.env.PORT || 8093);
http.createServer(async (req, res) => {
  const chunks = [];
  for await (const chunk of req) chunks.push(chunk);
  const raw = Buffer.concat(chunks).toString('utf-8');
  console.log(JSON.stringify({ method: req.method, url: req.url, body: raw.slice(0, 500) }));
  res.writeHead(200, { 'content-type': 'application/json' });
  res.end(JSON.stringify({ ok: true }));
}).listen(port, () => console.log(`fake webhook on http://localhost:${port}`));
