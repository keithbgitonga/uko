#!/usr/bin/env node
// Local Daraja simulator for integration tests: OAuth token + STK push, then
// posts a success/failure callback to the API like the real gateway would.
import http from 'node:http';

const port = Number(process.env.PORT || 8090);
const callbackUrl = process.env.CALLBACK_URL || 'http://localhost:3100/v1/payments/mpesa/callback?secret=devsecret';
const fail = process.env.FAKE_DARAJA_FAIL === '1';
let counter = 0;

const server = http.createServer(async (req, res) => {
  const chunks = [];
  for await (const chunk of req) chunks.push(chunk);
  const raw = Buffer.concat(chunks).toString('utf-8');
  console.log(JSON.stringify({ method: req.method, url: req.url, auth: req.headers.authorization ? 'present' : 'missing', body: raw.slice(0, 300) }));

  if (req.url.startsWith('/oauth/v1/generate')) {
    res.writeHead(200, { 'content-type': 'application/json' });
    res.end(JSON.stringify({ access_token: 'fake-daraja-token', expires_in: '3599' }));
    return;
  }
  if (req.url.startsWith('/mpesa/stkpush/v1/processrequest')) {
    counter += 1;
    const checkoutRequestId = `ws_CO_FAKE_${Date.now()}_${counter}`;
    const merchantRequestId = `mr_FAKE_${counter}`;
    res.writeHead(200, { 'content-type': 'application/json' });
    res.end(JSON.stringify({
      MerchantRequestID: merchantRequestId,
      CheckoutRequestID: checkoutRequestId,
      ResponseCode: '0',
      ResponseDescription: 'Success. Request accepted for processing',
      CustomerMessage: 'Success. Request accepted for processing',
    }));
    setTimeout(() => {
      const payload = fail
        ? {
            Body: { stkCallback: {
              MerchantRequestID: merchantRequestId,
              CheckoutRequestID: checkoutRequestId,
              ResultCode: 1032,
              ResultDesc: 'Request cancelled by user',
            } },
          }
        : {
            Body: { stkCallback: {
              MerchantRequestID: merchantRequestId,
              CheckoutRequestID: checkoutRequestId,
              ResultCode: 0,
              ResultDesc: 'The service request is processed successfully.',
              CallbackMetadata: { Item: [
                { Name: 'Amount', Value: 172 },
                { Name: 'MpesaReceiptNumber', Value: 'MPESA-FAKE123' },
                { Name: 'PhoneNumber', Value: '254712345678' },
              ] },
            } },
          };
      fetch(callbackUrl, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(payload) })
        .then((r) => console.log(`callback -> ${r.status}`))
        .catch((err) => console.error(`callback failed: ${err.message}`));
    }, 1200);
    return;
  }
  res.writeHead(404, { 'content-type': 'application/json' });
  res.end(JSON.stringify({ error: 'not found' }));
});

server.listen(port, () => console.log(`fake Daraja on http://localhost:${port} (fail=${fail})`));
