#!/usr/bin/env node
// Fake Africa's Talking messaging endpoint for SMS integration tests.
import http from 'node:http';

const port = Number(process.env.PORT || 8092);
http.createServer(async (req, res) => {
  const chunks = [];
  for await (const chunk of req) chunks.push(chunk);
  const raw = Buffer.concat(chunks).toString('utf-8');
  console.log(JSON.stringify({ method: req.method, url: req.url, auth: req.headers.apikey ? 'present' : 'missing', body: raw }));
  if (req.url.startsWith('/version1/messaging') && req.method === 'POST') {
    res.writeHead(201, { 'content-type': 'application/json' });
    res.end(JSON.stringify({ SMSMessageData: { Message: 'Sent to 1/1 Total Cost: KES 0.8000', Recipients: [{ statusCode: 101, status: 'Success', number: '+254700000000' }] } }));
    return;
  }
  res.writeHead(404, { 'content-type': 'application/json' });
  res.end(JSON.stringify({ error: 'not found' }));
}).listen(port, () => console.log(`fake SMS on http://localhost:${port}`));
