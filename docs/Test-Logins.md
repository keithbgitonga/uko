# One-tap test logins

For pilot/demo testing. **Do not leave enabled on a public production deployment.**

Controlled by:

```text
ALLOW_TEST_LOGINS=true
```

When enabled, the API exposes:

```text
GET  /v1/auth/test-accounts
POST /v1/auth/test-login   {"role":"rider|driver|dispatch|safety|admin"}
```

## Accounts

| Role | Phone | Where |
|---|---|---|
| Rider | +254712345678 | Rider app |
| Driver | +254700000001 | Driver app |
| Dispatch | +254700000010 | Dispatch console |
| Safety | +254700000011 | Dispatch console |
| Admin | +254700000012 | Dispatch console |

## Apps

- Rider app: **Test logins** card under the phone form → one tap signs in as Test Rider.
- Driver app: **Test logins** card → one tap signs in as Test Driver.
- Dispatch: **Show test logins** on the login screen → Dispatch, Safety, Admin buttons.
- The normal SMS OTP flow remains available.

## Safety

- Set `ALLOW_TEST_LOGINS=false` and redeploy before inviting real riders/drivers.
- The test accounts have no SMS/OTP protection while enabled.
- Test phones are allowed into dispatch only while `ALLOW_TEST_LOGINS=true`.
- Rotate `JWT_SECRET` and redeploy after switching test logins off if the URL has been shared.
